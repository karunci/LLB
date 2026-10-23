' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/mem/PhysicalManager.cls
' Summary: Intrusive free-list physical page frame allocator (4KB granularity).

Import Sync
Use Drivers.Terminal
Use Drivers.SerialUart

Namespace Mem

    ' Multiboot 1 Information Structure
    <Packed>
    Public Structure Multiboot1Info
        Public Flags As UInt32
        Public MemLower As UInt32
        Public MemUpper As UInt32
        Public BootDevice As UInt32
        Public Cmdline As UInt32
        Public ModsCount As UInt32
        Public ModsAddr As UInt32
        Public Syms0 As UInt32
        Public Syms1 As UInt32
        Public Syms2 As UInt32
        Public Syms3 As UInt32
        Public MmapLength As UInt32
        Public MmapAddr As UInt32
    End Structure

    <Packed>
    Public Structure Multiboot1MmapEntry
        Public Size As UInt32
        Public BaseAddr As UInt64
        Public Length As UInt64
        Public EntryType As UInt32
    End Structure

    ' Multiboot 2 Tag Header
    <Packed>
    Public Structure MultibootTag
        Public TagType As UInt32
        Public TagSize As UInt32
    End Structure

    <Packed>
    Public Structure MmapEntry
        Public BaseAddr As UInt64
        Public Length As UInt64
        Public EntryType As UInt32
        Public Reserved As UInt32
    End Structure

    <Instancing(SingleUse)>
    Public Class PhysicalManager

        ' Head of intrusive singly-linked physical free-list stack
        Private freeListHeadPhys As UInt64

        ' Memory accounting metrics
        Private freeMemoryBytes As UInt64
        Private totalMemoryBytes As UInt64

        ' SMP-safe spinlock
        Private pmmLock As Sync.Spinlock

        Public Sub Initialize()
            Sync.SpinlockOps.Init pmmLock
            freeListHeadPhys = 0
            freeMemoryBytes = 0
            totalMemoryBytes = 0
        End Sub

        ' Return total free physical memory bytes
        Public Function GetFreeBytes() As UInt64
            GetFreeBytes = freeMemoryBytes
        End Function

        ' Return total discovered RAM bytes
        Public Function GetTotalBytes() As UInt64
            GetTotalBytes = totalMemoryBytes
        End Function

        ' Free a 4KB physical page frame by pushing it to the free-list stack
        Public Unsafe Sub FreePage(ByVal physAddr As UInt64)
            If physAddr = 0 Then
                Exit Sub
            End If

            ' Protect lower 4MB (kernel code, stack, early BSS, and hardware structures)
            If physAddr < &H400000 Then
                Exit Sub
            End If

            ' Protect beyond 4GB for early identity paging
            If physAddr >= &H100000000 Then
                Exit Sub
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(pmmLock)

            ' Intrusive linking: store current head into frame(0)
            Dim nodePtr As Volatile Pointer To UInt64
            nodePtr = CPtr(Volatile Pointer To UInt64, physAddr)
            nodePtr(0) = freeListHeadPhys

            ' Set new head of free stack
            freeListHeadPhys = physAddr
            freeMemoryBytes = freeMemoryBytes + 4096

            Sync.SpinlockOps.ReleaseIrqRestore pmmLock, flags
        End Sub

        ' Allocate a 4KB physical page frame by popping it from the free-list stack
        Public Unsafe Function AllocPage() As UInt64
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(pmmLock)

            If freeListHeadPhys = 0 Then
                Sync.SpinlockOps.ReleaseIrqRestore pmmLock, flags
                AllocPage = 0
                Exit Function
            End If

            Dim allocPhys As UInt64 = freeListHeadPhys

            ' Read next pointer from inside the page
            Dim nodePtr As Volatile Pointer To UInt64
            nodePtr = CPtr(Volatile Pointer To UInt64, allocPhys)
            freeListHeadPhys = nodePtr(0)

            freeMemoryBytes = freeMemoryBytes - 4096

            Sync.SpinlockOps.ReleaseIrqRestore pmmLock, flags
            AllocPage = allocPhys
        End Function

        ' Parse Multiboot 1 or Multiboot 2 memory map and register usable frames
        Public Unsafe Sub ParseMemoryMap(ByVal magic As UInt32, ByVal mbiAddr As UInt64)
            If mbiAddr = 0 Then
                Exit Sub
            End If

            ' Check if bootloader passed Multiboot 1 (QEMU -kernel passes 0x2BADB002)
            If magic = &H2BADB002 Then
                Dim mb1 As Pointer To Multiboot1Info
                mb1 = CPtr(Pointer To Multiboot1Info, mbiAddr)

                Drivers.SerialUart.PrintF "DEBUG - [MB1] Flags: 0x%x, MmapAddr: 0x%x, MmapLen: 0x%x\n", mb1.Flags, mb1.MmapAddr, mb1.MmapLength

                ' Check if MMAP bit (bit 6 = 0x40) is set in Flags
                If (mb1.Flags And &H40) <> 0 Then
                    Dim mmapAddr As UInt64 = CType(UInt64, mb1.MmapAddr)
                    Dim mmapEnd As UInt64 = mmapAddr + CType(UInt64, mb1.MmapLength)

                    Dim currPtr As UInt64 = mmapAddr
                    While currPtr < mmapEnd
                        Dim entry As Pointer To Multiboot1MmapEntry
                        entry = CPtr(Pointer To Multiboot1MmapEntry, currPtr)

                        Drivers.SerialUart.PrintF "DEBUG - [MB1 Mmap] Base: 0x%x, Len: 0x%x, Type: 0x%x\n", entry.BaseAddr, entry.Length, entry.EntryType

                        ' EntryType 1 = Usable RAM strictly
                        If entry.EntryType = 1 Then
                            totalMemoryBytes = totalMemoryBytes + entry.Length

                            Dim startAddr As UInt64 = (entry.BaseAddr + 4095) And (Not CType(UInt64, 4095))
                            Dim endAddr As UInt64 = (entry.BaseAddr + entry.Length) And (Not CType(UInt64, 4095))

                            Dim addr As UInt64 = startAddr
                            While addr < endAddr
                                If addr >= &H400000 And addr < &H100000000 Then
                                    Me.FreePage addr
                                End If
                                addr = addr + 4096
                            Wend
                        End If

                        ' Move to next entry (size field does not include the size field itself)
                        currPtr = currPtr + CType(UInt64, entry.Size) + 4
                    Wend
                End If
                Exit Sub
            End If

            ' Otherwise parse Multiboot 2 (magic 0x36D76289)
            Dim totalSizePtr As Pointer To UInt32
            totalSizePtr = CPtr(Pointer To UInt32, mbiAddr)
            Dim totalSize As UInt32 = totalSizePtr(0)

            If totalSize < 8 Then
                Exit Sub
            End If

            Dim currOffset As UInt64 = mbiAddr + 8
            Dim endOffset As UInt64 = mbiAddr + CType(UInt64, totalSize)

            While currOffset < endOffset
                Dim tagPtr As Pointer To MultibootTag
                tagPtr = CPtr(Pointer To MultibootTag, currOffset)

                Dim tagType As UInt32 = tagPtr.TagType
                Dim tagSize As UInt32 = tagPtr.TagSize

                If tagType = 0 Then
                    Exit While
                End If

                If tagType = 6 Then
                    Dim entrySizePtr As Pointer To UInt32
                    entrySizePtr = CPtr(Pointer To UInt32, currOffset + 8)
                    Dim entrySize As UInt32 = entrySizePtr(0)

                    If entrySize >= 24 Then
                        Dim entryOffset As UInt64 = currOffset + 16
                        Dim tagEndOffset As UInt64 = currOffset + CType(UInt64, tagSize)

                        While entryOffset < tagEndOffset
                            Dim entry2 As Pointer To MmapEntry
                            entry2 = CPtr(Pointer To MmapEntry, entryOffset)

                            If entry2.EntryType = 1 Then
                                totalMemoryBytes = totalMemoryBytes + entry2.Length

                                startAddr = (entry2.BaseAddr + 4095) And (Not CType(UInt64, 4095))
                                endAddr = (entry2.BaseAddr + entry2.Length) And (Not CType(UInt64, 4095))

                                addr = startAddr
                                While addr < endAddr
                                    If addr >= &H400000 And addr < &H100000000 Then
                                        Me.FreePage addr
                                    End If
                                    addr = addr + 4096
                                Wend
                            End If

                            entryOffset = entryOffset + CType(UInt64, entrySize)
                        Wend
                    End If
                End If

                Dim alignedSize As UInt64 = CType(UInt64, (tagSize + 7) And (Not 7))
                currOffset = currOffset + alignedSize
            Wend
        End Sub

    End Class

End Namespace
