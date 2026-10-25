' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/Framebuffer.cls
' Summary: High-resolution linear framebuffer console driver with double buffering,
'          dirty rectangle burst flushing, and dynamic display management.

Import Sync
Import Arch.X86_64.PortIO
Use Drivers.SerialUart As Serial
Use Mem.KernelHeap As KHeap
Import Drivers.Font8x16

Namespace Drivers

    <Packed>
    Public Structure Multiboot2Tag
        Public TagType As UInt32
        Public TagSize As UInt32
    End Structure

    <Packed>
    Public Structure Multiboot2FramebufferTag
        Public TagType As UInt32
        Public TagSize As UInt32
        Public FramebufferAddr As UInt64
        Public FramebufferPitch As UInt32
        Public FramebufferWidth As UInt32
        Public FramebufferHeight As UInt32
        Public FramebufferBpp As Byte
        Public FramebufferType As Byte
        Public Reserved As UInt16
    End Structure

    <Instancing(SingleUse)>
    Public Class Framebuffer

        Public Declare Function memcpy Lib "libc" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64) As Pointer To Byte

        ' Bochs / QEMU / VirtualBox VBE Graphics Adapter (BGA) I/O Registers
        Public Const VBE_DISPI_IOPORT_INDEX As UInt16 = &H1CE
        Public Const VBE_DISPI_IOPORT_DATA  As UInt16 = &H1CF

        Public Const VBE_DISPI_INDEX_ID     As UInt16 = 0
        Public Const VBE_DISPI_INDEX_XRES   As UInt16 = 1
        Public Const VBE_DISPI_INDEX_YRES   As UInt16 = 2
        Public Const VBE_DISPI_INDEX_BPP    As UInt16 = 3
        Public Const VBE_DISPI_INDEX_ENABLE As UInt16 = 4

        Public Const VBE_DISPI_DISABLED     As UInt16 = &H00
        Public Const VBE_DISPI_ENABLED      As UInt16 = &H01
        Public Const VBE_DISPI_LFB_ENABLED  As UInt16 = &H40

        ' Hardware display geometry and memory layout
        Private physAddr As UInt64
        Private width As UInt32
        Private height As UInt32
        Private pitch As UInt32
        Private bpp As UInt32

        ' RAM backbuffer for double-buffering
        Private backbufferPhys As UInt64
        Private doubleBufferActive As Boolean

        ' Concurrency spinlock
        Private fbLock As Sync.Spinlock

        ''
        ' @brief Check if Bochs / QEMU / VirtualBox VBE Graphics Adapter (BGA) is available.
        ''
        Public Unsafe Function IsBgaAvailable() As Boolean
            Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_ID
            Dim id As UInt16 = Arch.X86_64.PortIO.InW(VBE_DISPI_IOPORT_DATA)
            IsBgaAvailable = (id >= &HB0C0 And id <= &HB0C6)
        End Function

        ''
        ' @brief Scan PCI bus 0 to locate standard VGA controller BAR 0 linear framebuffer address.
        ''
        Public Unsafe Function FindPciVgaLfb() As UInt64
            Dim dev As UInt32 = 0
            While dev < 32
                Dim addr As UInt32 = &H80000000 Or (dev LShift 11)
                Arch.X86_64.PortIO.OutL &HCF8, addr
                Dim id As UInt32 = Arch.X86_64.PortIO.InL(&HCFC)

                If (id And &HFFFF) <> &HFFFF Then
                    Arch.X86_64.PortIO.OutL &HCF8, addr Or 8
                    Dim classCode As UInt32 = Arch.X86_64.PortIO.InL(&HCFC)
                    Dim baseClass As UInt32 = (classCode RShift 24) And &HFF
                    If baseClass = 3 Then
                        Arch.X86_64.PortIO.OutL &HCF8, addr Or &H10
                        Dim bar0 As UInt32 = Arch.X86_64.PortIO.InL(&HCFC)
                        FindPciVgaLfb = CType(UInt64, bar0 And &HFFFFFFF0)
                        Exit Function
                    End If
                End If
                dev = dev + 1
            Wend
            FindPciVgaLfb = &HFD000000
        End Function

        ''
        ' @brief Dynamically transition the display hardware into graphics mode and set resolution.
        ''
        Public Unsafe Sub SetVideoMode(ByVal newWidth As UInt32, ByVal newHeight As UInt32, ByVal newBpp As UInt32)
            If IsBgaAvailable() Then
                ' Disable display controller during reconfiguration
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_ENABLE
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_DATA, VBE_DISPI_DISABLED

                ' Program target display mode
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_XRES
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_DATA, CType(UInt16, newWidth)

                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_YRES
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_DATA, CType(UInt16, newHeight)

                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_BPP
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_DATA, CType(UInt16, newBpp)

                ' Enable linear framebuffer graphics mode (resizes QEMU/VirtualBox window immediately)
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_INDEX, VBE_DISPI_INDEX_ENABLE
                Arch.X86_64.PortIO.OutW VBE_DISPI_IOPORT_DATA, VBE_DISPI_ENABLED Or VBE_DISPI_LFB_ENABLED

                width = newWidth
                height = newHeight
                bpp = newBpp
                pitch = newWidth * (newBpp / 8)

                Dim pciLfb As UInt64 = FindPciVgaLfb()
                If pciLfb <> 0 Then physAddr = pciLfb

                Serial.PrintF "[FB] BGA Graphics Hardware active: %ux%u (%u BPP, LFB: 0x%x)\r\n", _
                              width, height, bpp, CType(UInt32, physAddr And &HFFFFFFFF)
            End If
        End Sub

        ''
        ' @brief Initialize the framebuffer by scanning Multiboot 1 or Multiboot 2 information,
        '        or transitioning to hardware graphics mode via BGA if running in VGA text mode.
        ''
        Public Unsafe Sub Initialize(ByVal magic As UInt32, ByVal mbiAddr As UInt64)
            physAddr = 0
            width = 0
            height = 0
            pitch = 0
            bpp = 0
            backbufferPhys = 0
            doubleBufferActive = False

            If magic = &H36D76289 Then
                ParseMultiboot2Tags mbiAddr
            ElseIf mbiAddr <> 0 Then
                ParseMultiboot1Info mbiAddr
            End If

            ' If no graphics framebuffer was configured by bootloader,
            ' dynamically transition VGA text mode to Graphics Mode via BGA!
            If physAddr = 0 Or physAddr = &HB8000 Or width = 0 Or height = 0 Then
                SetFallbackMode
            End If

            Serial.PrintF "[FB] Linear Framebuffer Online: 0x%x (%ux%u, %u BPP, Pitch: %u bytes)\r\n", _
                          CType(UInt32, physAddr And &HFFFFFFFF), width, height, bpp, pitch
        End Sub

        ' Parse Multiboot 2 tags looking for Tag Type 8 (Framebuffer)
        Private Unsafe Sub ParseMultiboot2Tags(ByVal mbiAddr As UInt64)
            Dim totalSizePtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbiAddr)
            Dim totalSize As UInt32 = totalSizePtr(0)
            Dim currentOffset As UInt64 = 8

            While currentOffset < CType(UInt64, totalSize)
                Dim tagPtr As Volatile Pointer To Multiboot2Tag = CPtr(Volatile Pointer To Multiboot2Tag, mbiAddr + currentOffset)
                If tagPtr.TagType = 0 Then Exit While

                If tagPtr.TagType = 8 Then
                    ' Multiboot 2 Framebuffer Tag
                    Dim fbTag As Volatile Pointer To Multiboot2FramebufferTag
                    fbTag = CPtr(Volatile Pointer To Multiboot2FramebufferTag, mbiAddr + currentOffset)

                    ' Skip legacy 80x25 text mode (0xB8000)
                    If fbTag.FramebufferAddr <> &HB8000 And fbTag.FramebufferWidth > 0 Then
                        physAddr = fbTag.FramebufferAddr
                        pitch = fbTag.FramebufferPitch
                        width = fbTag.FramebufferWidth
                        height = fbTag.FramebufferHeight
                        bpp = CType(UInt32, fbTag.FramebufferBpp)
                        Exit Sub
                    End If
                End If

                ' Advance to next tag (8-byte aligned)
                Dim tagSizeAligned As UInt64 = (CType(UInt64, tagPtr.TagSize) + 7) And (Not CType(UInt64, 7))
                currentOffset = currentOffset + tagSizeAligned
            Wend
        End Sub

        ' Parse Multiboot 1 header for VBE / Framebuffer information
        Private Unsafe Sub ParseMultiboot1Info(ByVal mbiAddr As UInt64)
            Dim flagsPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbiAddr)
            Dim flags As UInt32 = flagsPtr(0)

            ' Check bit 12 (framebuffer table available in Multiboot 0.6.96+)
            If (flags And &H1000) <> 0 Then
                Dim fbAddrPtr As Volatile Pointer To UInt64 = CPtr(Volatile Pointer To UInt64, mbiAddr + 88)
                Dim fbPitchPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbiAddr + 96)
                Dim fbWidthPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbiAddr + 100)
                Dim fbHeightPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbiAddr + 104)
                Dim fbBppPtr As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, mbiAddr + 108)

                If fbAddrPtr(0) <> &HB8000 And fbWidthPtr(0) > 0 Then
                    physAddr = fbAddrPtr(0)
                    pitch = fbPitchPtr(0)
                    width = fbWidthPtr(0)
                    height = fbHeightPtr(0)
                    bpp = CType(UInt32, fbBppPtr(0))
                End If
            End If
        End Sub

        ' Hardware transition fallback via BGA
        Public Unsafe Sub SetFallbackMode()
            If IsBgaAvailable() Then
                SetVideoMode 1024, 768, 32
            Else
                Dim pciLfb As UInt64 = FindPciVgaLfb()
                If pciLfb <> 0 Then
                    physAddr = pciLfb
                Else
                    physAddr = &HFD000000
                End If
                width = 1024
                height = 768
                bpp = 32
                pitch = 1024 * 4
            End If
        End Sub

        ''
        ' @brief Allocate a RAM backbuffer for double-buffered rendering to eliminate MMIO stalls.
        ''
        Public Unsafe Sub InitializeDoubleBuffer()
            If width = 0 Or height = 0 Or pitch = 0 Then Exit Sub

            Dim bufferSize As UInt64 = CType(UInt64, height) * CType(UInt64, pitch)
            backbufferPhys = KHeap.KMalloc(bufferSize)

            If backbufferPhys <> 0 Then
                doubleBufferActive = True
                Serial.PrintF "[FB] RAM Double-Buffering enabled (%u KB allocated at 0x%x)\r\n", _
                              CType(UInt32, bufferSize / 1024), CType(UInt32, backbufferPhys And &HFFFFFFFF)
            Else
                Serial.PrintF "[FB] Warning: Failed to allocate backbuffer. Falling back to direct VRAM.\r\n"
            End If
        End Sub

        ''
        ' @brief Flush a dirty rectangular bounding box from the RAM backbuffer to physical VRAM.
        ''
        Public Unsafe Sub FlushRegion(ByVal x As UInt32, ByVal y As UInt32, ByVal w As UInt32, ByVal h As UInt32)
            If Not doubleBufferActive Or backbufferPhys = 0 Or physAddr = 0 Then Exit Sub

            ' Bounds clipping
            If x >= width Or y >= height Then Exit Sub
            If x + w > width Then w = width - x
            If y + h > height Then h = height - y
            Dim bppBytes As UInt32 = bpp / 8
            Dim rowBytes As UInt64 = CType(UInt64, w) * CType(UInt64, bppBytes)

            Dim row As UInt32 = 0
            While row < h
                Dim offset As UInt64 = (CType(UInt64, y + row) * CType(UInt64, pitch)) + (CType(UInt64, x) * CType(UInt64, bppBytes))
                Dim dstPtr As Pointer To Byte = CPtr(Pointer To Byte, physAddr + offset)
                Dim srcPtr As Pointer To Byte = CPtr(Pointer To Byte, backbufferPhys + offset)
                memcpy dstPtr, srcPtr, rowBytes
                row = row + 1
            Wend

            Asm "sfence" : : : "memory"
        End Sub

        ''
        ' @brief Flush the entire backbuffer to physical VRAM.
        ''
        Public Unsafe Sub FlushAll()
            FlushRegion 0, 0, width, height
        End Sub

        ''
        ' @brief Plot a single pixel at (x, y) with 32-bit color (0x00RRGGBB).
        ''
        Public Unsafe Sub PutPixel(ByVal x As UInt32, ByVal y As UInt32, ByVal color As UInt32)
            If x >= width Or y >= height Then Exit Sub

            Dim targetBase As UInt64 = physAddr
            If doubleBufferActive And backbufferPhys <> 0 Then targetBase = backbufferPhys

            If bpp = 32 Then
                Dim target32 As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, targetBase)
                Dim pixelIndex As UInt64 = (CType(UInt64, y) * (CType(UInt64, pitch) / 4)) + CType(UInt64, x)
                target32(pixelIndex) = color
            ElseIf bpp = 24 Then
                Dim target8 As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, targetBase)
                Dim offset As UInt64 = (CType(UInt64, y) * CType(UInt64, pitch)) + (CType(UInt64, x) * 3)
                target8(offset + 0) = CType(Byte, color And &HFF)
                target8(offset + 1) = CType(Byte, (color RShift 8) And &HFF)
                target8(offset + 2) = CType(Byte, (color RShift 16) And &HFF)
            End If
        End Sub

        ''
        ' @brief Clear the screen or backbuffer to a solid color.
        ''
        Public Unsafe Sub ClearScreen(ByVal color As UInt32)
            Dim targetBase As UInt64 = physAddr
            If doubleBufferActive And backbufferPhys <> 0 Then targetBase = backbufferPhys

            If bpp = 32 Then
                Dim target32 As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, targetBase)
                Dim totalPixels As UInt64 = (CType(UInt64, height) * CType(UInt64, pitch)) / 4
                Dim i As UInt64 = 0
                While i < totalPixels
                    target32(i) = color
                    i = i + 1
                Wend
            Else
                Dim y As UInt32 = 0
                While y < height
                    Dim x As UInt32 = 0
                    While x < width
                        PutPixel x, y, color
                        x = x + 1
                    Wend
                    y = y + 1
                Wend
            End If

            If doubleBufferActive Then FlushAll
        End Sub

        ''
        ' @brief Fill a solid rectangle at (x, y) with dimensions (w, h).
        ''
        Public Unsafe Sub FillRect(ByVal x As UInt32, ByVal y As UInt32, ByVal w As UInt32, ByVal h As UInt32, ByVal color As UInt32)
            Dim curY As UInt32 = y
            Dim endY As UInt32 = y + h
            Dim endX As UInt32 = x + w

            While curY < endY
                Dim curX As UInt32 = x
                While curX < endX
                    PutPixel curX, curY, color
                    curX = curX + 1
                Wend
                curY = curY + 1
            Wend

            If doubleBufferActive Then FlushRegion x, y, w, h
        End Sub

        ''
        ' @brief Draw a single 8x16 ASCII glyph at (x, y) with scaling.
        ''
        Public Unsafe Sub DrawChar(ByVal x As UInt32, ByVal y As UInt32, ByVal ch As Byte, ByVal color As UInt32, ByVal scale As UInt32)
            If scale = 0 Then scale = 1

            Dim row As UInt32 = 0
            While row < 16
                Dim bitmask As Byte = Drivers.Font8x16.GetGlyphByte(CType(UInt32, ch), row)
                Dim col As UInt32 = 0
                While col < 8
                    If (bitmask And CType(Byte, &H80 RShift col)) <> 0 Then
                        Dim sy As UInt32 = 0
                        While sy < scale
                            Dim sx As UInt32 = 0
                            While sx < scale
                                PutPixel x + (col * scale) + sx, y + (row * scale) + sy, color
                                sx = sx + 1
                            Wend
                            sy = sy + 1
                        Wend
                    End If
                    col = col + 1
                Wend
                row = row + 1
            Wend
        End Sub

        ''
        ' @brief Render an ASCII string starting at coordinate (x, y) with optional scaling.
        ''
        Public Unsafe Sub DrawString(ByVal x As UInt32, ByVal y As UInt32, ByVal str As Pointer To Byte, ByVal color As UInt32, ByVal scale As UInt32)
            If str = 0 Then Exit Sub
            If scale = 0 Then scale = 1

            Dim cx As UInt32 = x
            Dim i As UInt32 = 0

            While str(i) <> 0
                Dim ch As Byte = str(i)
                If ch = 10 Then
                    ' Newline: drop down by 16 * scale
                    y = y + (16 * scale)
                    cx = x
                ElseIf ch = 13 Then
                    ' Carriage return
                    cx = x
                Else
                    DrawChar cx, y, ch, color, scale
                    cx = cx + (8 * scale)
                End If
                i = i + 1
            Wend

            If doubleBufferActive Then
                FlushRegion x, y, cx - x, 16 * scale
            End If
        End Sub

        ' Dynamic Display Query API
        Public Function GetDisplayWidth() As UInt32
            GetDisplayWidth = width
        End Function

        Public Function GetDisplayHeight() As UInt32
            GetDisplayHeight = height
        End Function

        Public Function GetDisplayPitch() As UInt32
            GetDisplayPitch = pitch
        End Function

        Public Function GetDisplayBpp() As UInt32
            GetDisplayBpp = bpp
        End Function

        Public Function GetFramebufferPhys() As UInt64
            GetFramebufferPhys = physAddr
        End Function

    End Class

End Namespace
