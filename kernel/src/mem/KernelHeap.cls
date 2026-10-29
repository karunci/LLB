' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/mem/KernelHeap.cls
' Summary: 16-byte aligned kernel dynamic heap allocator (kmalloc/kfree).
'          Ports PRK kernel/heap.c with intrusive doubly-linked boundary tags.

Import Sync
Use Drivers.SerialUart As Serial
Use Mem.PhysicalMemoryManager As PMM
Use Mem.VirtualMemoryManager As VMM

Namespace Mem

' Doubly-linked block header (32 bytes = 16-byte aligned)
<Packed>
Public Structure KBlockHeader
    Public Size As UInt32              ' Payload size in bytes
    Public IsFree As UInt32            ' 1 = Free, 0 = Allocated
    Public Magic As UInt64             ' Magic safety verification
    Public NextHeader As UInt64        ' Pointer To KBlockHeader (physical or identity virtual)
    Public PrevHeader As UInt64        ' Pointer To KBlockHeader (physical or identity virtual)
End Structure

#Assert SizeOf(KBlockHeader) = 32, "KBlockHeader must be exactly 32 bytes"

<Instancing(SingleUse)>
Public Class KernelHeap

    Public Const KMETA_SIZE As UInt64 = 32
    Public Const KMAGIC_NUM As UInt64 = &H87654321ABCDEF00
    Public Const HEAP_BASE_ADDR As UInt64 = &H81000000    ' Distinct virtual address space above 1GB identity map
    Public Const HEAP_INITIAL_PAGES As UInt32 = 2048      ' 8MB initial dynamic heap pool (2048 * 4KB)

    Private heapBasePhys As UInt64
    Private heapLock As Sync.Spinlock
    Private totalHeapBytes As UInt64
    Private allocatedBytes As UInt64

    ''
    ' @brief Initialize the kernel heap by allocating physical frames from PMM and mapping them.
    '        Mirrors PRK heap_init().
    ''
    Public Unsafe Sub Initialize()
        Sync.SpinlockOps.Init heapLock
        Serial.PrintF "[HEAP] Initializing 16-Byte Aligned Kernel Dynamic Heap Allocator...\r\n"

        ' Pre-allocate and map contiguous 4MB (1024 pages) for the initial heap arena
        Dim pml4Root As UInt64 = VMM.GetKernelPml4()
        Dim p As UInt32
        For p = 0 To HEAP_INITIAL_PAGES - 1
            Dim physPage As UInt64 = PMM.AllocPage()
            If physPage = 0 Then
                Serial.PrintF "[HEAP] Fatal: Out of physical memory during heap initialization!\r\n"
                Exit Sub
            End If

            Dim virtTarget As UInt64 = HEAP_BASE_ADDR + (CType(UInt64, p) * 4096)
            Dim flags As UInt64 = &H03
            VMM.MapPage pml4Root, virtTarget, physPage, flags
        Next p

        totalHeapBytes = CType(UInt64, HEAP_INITIAL_PAGES) * 4096
        allocatedBytes = 0
        heapBasePhys = HEAP_BASE_ADDR

        ' Initialize the initial free block header covering the full heap space
        Dim rootHeader As Volatile Pointer To KBlockHeader
        rootHeader = CPtr(Volatile Pointer To KBlockHeader, heapBasePhys)
        rootHeader.Size = CType(UInt32, totalHeapBytes - KMETA_SIZE)
        rootHeader.IsFree = 1
        rootHeader.Magic = KMAGIC_NUM
        rootHeader.NextHeader = 0
        rootHeader.PrevHeader = 0

        Serial.PrintF "[HEAP] Kernel Dynamic Heap Online: 0x%x - 0x%x (%u MB)\r\n", _
            heapBasePhys, heapBasePhys + totalHeapBytes, CType(UInt32, totalHeapBytes RShift 20)
    End Sub

    ''
    ' @brief Allocate dynamic kernel memory with 16-byte alignment.
    '        Mirrors PRK kmalloc().
    ' @param reqSize Number of payload bytes requested.
    ' @return Pointer to allocated memory, or 0 if out of memory.
    ''
    Public Unsafe Function KMalloc(ByVal reqSize As UInt32) As UInt64
        If reqSize = 0 Then
            KMalloc = 0
            Exit Function
        End If

        ' Enforce 16-byte alignment on allocation request
        Dim alignSize As UInt32 = (reqSize + 15) And (Not CType(UInt32, 15))

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(heapLock)

        Dim currAddr As UInt64 = heapBasePhys
        While currAddr <> 0
            Dim curr As Volatile Pointer To KBlockHeader
            curr = CPtr(Volatile Pointer To KBlockHeader, currAddr)

            If curr.Magic <> KMAGIC_NUM Then
                Sync.SpinlockOps.ReleaseIrqRestore heapLock, flags
                Serial.PrintF "[HEAP] Fatal: Corrupt heap magic at 0x%x! Magic=0x%x%08x Size=%u Free=%u\r\n", currAddr, CType(UInt32, curr.Magic RShift 32), CType(UInt32, curr.Magic And &HFFFFFFFF), curr.Size, curr.IsFree
                KMalloc = 0
                Exit Function
            End If

            If curr.IsFree = 1 And curr.Size >= alignSize Then
                ' Split block if enough room remains for new block header + minimum 16 payload bytes
                If curr.Size >= (alignSize + CType(UInt32, KMETA_SIZE) + 16) Then
                    Dim newAddr As UInt64 = currAddr + KMETA_SIZE + CType(UInt64, alignSize)
                    Dim newBlock As Volatile Pointer To KBlockHeader
                    newBlock = CPtr(Volatile Pointer To KBlockHeader, newAddr)

                    newBlock.Size = curr.Size - alignSize - CType(UInt32, KMETA_SIZE)
                    newBlock.IsFree = 1
                    newBlock.Magic = KMAGIC_NUM
                    newBlock.NextHeader = curr.NextHeader
                    newBlock.PrevHeader = currAddr

                    If curr.NextHeader <> 0 Then
                        Dim nextBlock As Volatile Pointer To KBlockHeader
                        nextBlock = CPtr(Volatile Pointer To KBlockHeader, curr.NextHeader)
                        nextBlock.PrevHeader = newAddr
                    End If

                    curr.Size = alignSize
                    curr.NextHeader = newAddr
                End If

                curr.IsFree = 0
                allocatedBytes = allocatedBytes + CType(UInt64, curr.Size)
                Sync.SpinlockOps.ReleaseIrqRestore heapLock, flags

                KMalloc = currAddr + KMETA_SIZE
                Exit Function
            End If

            currAddr = curr.NextHeader
        Wend

        Sync.SpinlockOps.ReleaseIrqRestore heapLock, flags
        Serial.PrintF "[HEAP] Error: Out of kernel heap space for allocation (%u bytes)!\r\n", reqSize
        KMalloc = 0
    End Function

    ''
    ' @brief Free dynamic memory and coalesce adjacent free blocks.
    '        Mirrors PRK kfree().
    ' @param ptr Pointer previously returned by KMalloc.
    ''
    Public Unsafe Sub KFree(ByVal ptr As UInt64)
        If ptr = 0 Then Exit Sub

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(heapLock)

        Dim headerAddr As UInt64 = ptr - KMETA_SIZE
        Dim header As Volatile Pointer To KBlockHeader
        header = CPtr(Volatile Pointer To KBlockHeader, headerAddr)

        If header.Magic <> KMAGIC_NUM Then
            Sync.SpinlockOps.ReleaseIrqRestore heapLock, flags
            Serial.PrintF "[HEAP] Warning: Invalid magic number or double free at 0x%x!\r\n", ptr
            Exit Sub
        End If

        header.IsFree = 1
        allocatedBytes = allocatedBytes - CType(UInt64, header.Size)

        ' Coalesce with Next block if free
        If header.NextHeader <> 0 Then
            Dim nextBlock As Volatile Pointer To KBlockHeader
            nextBlock = CPtr(Volatile Pointer To KBlockHeader, header.NextHeader)
            If nextBlock.IsFree = 1 Then
                header.Size = header.Size + CType(UInt32, KMETA_SIZE) + nextBlock.Size
                header.NextHeader = nextBlock.NextHeader
                If nextBlock.NextHeader <> 0 Then
                    Dim nextNextBlock As Volatile Pointer To KBlockHeader
                    nextNextBlock = CPtr(Volatile Pointer To KBlockHeader, nextBlock.NextHeader)
                    nextNextBlock.PrevHeader = headerAddr
                End If
            End If
        End If

        ' Coalesce with Prev block if free
        If header.PrevHeader <> 0 Then
            Dim prevBlock As Volatile Pointer To KBlockHeader
            prevBlock = CPtr(Volatile Pointer To KBlockHeader, header.PrevHeader)
            If prevBlock.IsFree = 1 Then
                prevBlock.Size = prevBlock.Size + CType(UInt32, KMETA_SIZE) + header.Size
                prevBlock.NextHeader = header.NextHeader
                If header.NextHeader <> 0 Then
                    Dim succBlock As Volatile Pointer To KBlockHeader
                    succBlock = CPtr(Volatile Pointer To KBlockHeader, header.NextHeader)
                    succBlock.PrevHeader = header.PrevHeader
                End If
            End If
        End If

        Sync.SpinlockOps.ReleaseIrqRestore heapLock, flags
    End Sub

End Class

End Namespace
