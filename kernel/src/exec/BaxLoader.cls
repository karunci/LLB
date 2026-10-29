' Project Name: PRK-LLB (Personal Research Kernel) / Low-Level Basic
' Filename: tests/kernel/src/exec/BaxLoader.cls
' Summary: High-performance native NEO/PE-BAX binary loader with memory-mapped resource mapping.

Import Mem
Import Exec
Use Drivers.SerialUart As Serial
Use Mem.PhysicalMemoryManager As PMM
Use Mem.VirtualMemoryManager As VMM

Namespace Exec

    <Instancing(SingleUse)>
    Public Class BaxLoader

        Private Const USER_SPACE_MAX As UInt64 = &H00007FFFFFFFFFFF
        Private Const BAX_MAGIC_VAL  As UInt64 = &H005841422F4F454E
        Private Const BAX_ARCH_X86_64 As UInt16 = 1

        ''
        ' @brief Verify, allocate, map, and load a NEO/PE-BAX executable into a User PML4 address space.
        ' @param userPml4 Physical base address of the task's dedicated PML4 root table.
        ' @param fileStart Starting memory address of the raw .bax binary image.
        ' @param fileSize Length of the .bax binary image in bytes.
        ' @return Application entry point (%rip) ready for Ring 3 dispatch, or 0 on failure.
        ''
        Public Unsafe Function LoadBinary(ByVal userPml4 As UInt64, ByVal fileStart As UInt64, ByVal fileSize As UInt64) As UInt64
            If userPml4 = 0 Or fileStart = 0 Or fileSize < SizeOf(BaxHeader) Then
                Serial.PrintF "[BAX] Error: Invalid loader parameters or buffer too small!\r\n"
                LoadBinary = 0
                Exit Function
            End If

            Dim header As Pointer To BaxHeader = CPtr(Pointer To BaxHeader, fileStart)

            ' 1. Validate NEO/PE-BAX Magic ("NEO/BAX\0")
            If header.Magic <> BAX_MAGIC_VAL Then
                Serial.PrintF "[BAX] Error: Magic mismatch! Expected 'NEO/BAX\\0', got 0x%lx\r\n", header.Magic
                LoadBinary = 0
                Exit Function
            End If

            ' 2. Validate Target Architecture
            If header.TargetArch <> BAX_ARCH_X86_64 Then
                Serial.PrintF "[BAX] Error: Unsupported target architecture: %u\r\n", CType(UInt32, header.TargetArch)
                LoadBinary = 0
                Exit Function
            End If

            ' 3. Validate Segment Table Bounds
            Dim segTableBytes As UInt64 = CType(UInt64, header.SegmentCount) * SizeOf(BaxSegment)
            If (CType(UInt64, header.SegmentsOffset) + segTableBytes) > fileSize Then
                Serial.PrintF "[BAX] Security Alert: Segment table exceeds file boundary!\r\n"
                LoadBinary = 0
                Exit Function
            End If

            Dim segTable As Pointer To BaxSegment = CPtr(Pointer To BaxSegment, fileStart + CType(UInt64, header.SegmentsOffset))

            ' 4. Security Audit: Check virtual address boundaries and file boundary offsets
            Dim s As UInt32
            For s = 0 To CType(UInt32, header.SegmentCount) - 1
                Dim segPtr As Pointer To BaxSegment = segTable + s

                If segPtr.VirtAddr >= USER_SPACE_MAX Or (segPtr.VirtAddr + segPtr.MemSize) > USER_SPACE_MAX Then
                    Serial.PrintF "[BAX SECURITY] Rejecting segment mapped to Kernel/Supervisor space: 0x%lx\r\n", segPtr.VirtAddr
                    LoadBinary = 0
                    Exit Function
                End If

                If (segPtr.FileOffset + segPtr.FileSize) > fileSize Then
                    Serial.PrintF "[BAX SECURITY] Segment file payload exceeds file bounds!\r\n"
                    LoadBinary = 0
                    Exit Function
                End If
            Next s

            ' 5. Map and Load Executable Segments
            For s = 0 To CType(UInt32, header.SegmentCount) - 1
                Dim curSeg As Pointer To BaxSegment = segTable + s
                If curSeg.MemSize > 0 Then
                    Dim startPage As UInt64 = curSeg.VirtAddr And (Not CType(UInt64, 4095))
                    Dim endPage As UInt64 = (curSeg.VirtAddr + curSeg.MemSize + 4095) And (Not CType(UInt64, 4095))

                    Dim pageVirt As UInt64 = startPage
                    While pageVirt < endPage
                        ' Allocate clean physical page frame
                        Dim physPage As UInt64 = PMM.AllocPage()
                        If physPage = 0 Then
                            Serial.PrintF "[BAX] Fatal: Out of physical memory during segment allocation!\r\n"
                            LoadBinary = 0
                            Exit Function
                        End If

                        ' Zero physical frame (guarantees BSS zero-initialization)
                        Dim pageBuf As Pointer To Byte = CPtr(Pointer To Byte, physPage)
                        Dim z As UInt32
                        For z = 0 To 4095
                            pageBuf(z) = 0
                        Next z

                        ' Copy initialized segment data if intersecting current page
                        If curSeg.FileSize > 0 Then
                            Dim segStart As UInt64 = curSeg.VirtAddr
                            Dim segEnd As UInt64 = curSeg.VirtAddr + curSeg.FileSize

                            Dim overlapStart As UInt64 = pageVirt
                            If segStart > pageVirt Then overlapStart = segStart

                            Dim overlapEnd As UInt64 = pageVirt + 4096
                            If segEnd < overlapEnd Then overlapEnd = segEnd

                            If overlapStart < overlapEnd Then
                                Dim copyLen As UInt64 = overlapEnd - overlapStart
                                Dim dstOffset As UInt64 = overlapStart - pageVirt
                                Dim srcOffset As UInt64 = curSeg.FileOffset + (overlapStart - segStart)

                                Dim dstPtr As Pointer To Byte = pageBuf + dstOffset
                                Dim srcPtr As Pointer To Byte = CPtr(Pointer To Byte, fileStart + srcOffset)

                                Dim b As UInt64
                                For b = 0 To copyLen - 1
                                    dstPtr(b) = srcPtr(b)
                                Next b
                            End If
                        End If

                        ' Map page frame into User PML4 (PTE_PRESENT | PTE_WRITABLE | PTE_USER)
                        VMM.MapPage userPml4, pageVirt, physPage, &H07

                        pageVirt = pageVirt + 4096
                    Wend
                End If
            Next s

            ' 6. Map Embedded Resources if present
            If header.ResourceCount > 0 And header.ResourceOffset > 0 Then
                Dim resTableBytes As UInt64 = CType(UInt64, header.ResourceCount) * SizeOf(BaxResourceEntry)
                If (CType(UInt64, header.ResourceOffset) + resTableBytes) <= fileSize Then
                    Dim resDirSrc As Pointer To BaxResourceEntry = CPtr(Pointer To BaxResourceEntry, fileStart + CType(UInt64, header.ResourceOffset))

                    ' Calculate total span of resource virtual memory (Directory + Blobs)
                    Dim maxResEndVirt As UInt64 = header.ResourceVirtAddr + resTableBytes
                    Dim r As UInt32
                    For r = 0 To CType(UInt32, header.ResourceCount) - 1
                        Dim re As Pointer To BaxResourceEntry = resDirSrc + r
                        Dim reEndVirt As UInt64 = re.VirtAddr + re.ByteLength
                        If reEndVirt > maxResEndVirt Then maxResEndVirt = reEndVirt
                    Next r

                    Dim resStartPage As UInt64 = header.ResourceVirtAddr And (Not CType(UInt64, 4095))
                    Dim resEndPage As UInt64 = (maxResEndVirt + 4095) And (Not CType(UInt64, 4095))

                    Dim resPageVirt As UInt64 = resStartPage
                    While resPageVirt < resEndPage
                        Dim resPhys As UInt64 = PMM.AllocPage()
                        If resPhys <> 0 Then
                            Dim rBuf As Pointer To Byte = CPtr(Pointer To Byte, resPhys)
                            Dim rz As UInt32
                            For rz = 0 To 4095
                                rBuf(rz) = 0
                            Next rz

                            ' Copy resource directory and/or asset payload data to this page
                            ' 1) Check intersection with Resource Directory Array
                            Dim rDirStart As UInt64 = header.ResourceVirtAddr
                            Dim rDirEnd As UInt64 = header.ResourceVirtAddr + resTableBytes
                            Dim oDirStart As UInt64 = resPageVirt
                            If rDirStart > oDirStart Then oDirStart = rDirStart
                            Dim oDirEnd As UInt64 = resPageVirt + 4096
                            If rDirEnd < oDirEnd Then oDirEnd = rDirEnd
                            If oDirStart < oDirEnd Then
                                Dim dCopyLen As UInt64 = oDirEnd - oDirStart
                                Dim dDstOff As UInt64 = oDirStart - resPageVirt
                                Dim dSrcOff As UInt64 = CType(UInt64, header.ResourceOffset) + (oDirStart - rDirStart)
                                Dim dDst As Pointer To Byte = rBuf + dDstOff
                                Dim dSrc As Pointer To Byte = CPtr(Pointer To Byte, fileStart + dSrcOff)
                                Dim db As UInt64
                                For db = 0 To dCopyLen - 1
                                    dDst(db) = dSrc(db)
                                Next db
                            End If

                            ' 2) Check intersection with each Asset Payload Blob
                            For r = 0 To CType(UInt32, header.ResourceCount) - 1
                                Dim resItem As Pointer To BaxResourceEntry = resDirSrc + r
                                If resItem.ByteLength > 0 Then
                                    Dim bStart As UInt64 = resItem.VirtAddr
                                    Dim bEnd As UInt64 = resItem.VirtAddr + resItem.ByteLength
                                    Dim obStart As UInt64 = resPageVirt
                                    If bStart > obStart Then obStart = bStart
                                    Dim obEnd As UInt64 = resPageVirt + 4096
                                    If bEnd < obEnd Then obEnd = bEnd
                                    If obStart < obEnd Then
                                        Dim bCopyLen As UInt64 = obEnd - obStart
                                        Dim bDstOff As UInt64 = obStart - resPageVirt
                                        Dim bSrcOff As UInt64 = resItem.FileOffset + (obStart - bStart)
                                        Dim bDst As Pointer To Byte = rBuf + bDstOff
                                        Dim bSrc As Pointer To Byte = CPtr(Pointer To Byte, fileStart + bSrcOff)
                                        Dim bb As UInt64
                                        For bb = 0 To bCopyLen - 1
                                            bDst(bb) = bSrc(bb)
                                        Next bb
                                    End If
                                End If
                            Next r

                            ' Map user resource page
                            VMM.MapPage userPml4, resPageVirt, resPhys, &H07
                        End If
                        resPageVirt = resPageVirt + 4096
                    Wend

                    Serial.PrintF "[BAX] Memory-Mapped %u Resource(s) at virtual 0x%lx\r\n", _
                                  CType(UInt32, header.ResourceCount), header.ResourceVirtAddr
                End If
            End If

            Serial.PrintF "[BAX] Binary loaded successfully. Subsystem: %u, Entry: 0x%lx, ImageSize: %u bytes\r\n", _
                          CType(UInt32, header.Subsystem), header.EntryPoint, CType(UInt32, header.ImageSize)

            LoadBinary = header.EntryPoint
        End Function

    End Class

End Namespace
