' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/mem/BuddyAllocator.cls
' Summary: Multi-order binary buddy page frame allocator (Order 0: 4KB to Order 10: 4MB).

Import Sync
Use Drivers.SerialUart

Namespace Mem

    ' Intrusive free block node embedded at the start of each free block
    <Packed>
    Public Structure BuddyBlockNode
        Public NextPhys As UInt64
    End Structure

    <Instancing(SingleUse)>
    Public Class BuddyAllocator

        ' Maximum Order: Order 0 (4KB) to Order 10 (4MB = 1024 pages)
        Public Const MAX_ORDER As UInt32 = 10
        Public Const PAGE_SIZE As UInt64 = 4096

        ' Managed physical memory window bounds
        Private poolBasePhys As UInt64
        Private poolSizePhys As UInt64
        Private totalPages As UInt64

        ' Heads of free lists for each order (0 .. 10)
        ' Stored as array of physical 64-bit addresses
        Private freeLists(11) As UInt64

        ' Count of free blocks per order
        Private freeCount(11) As UInt64

        ' SMP spinlock protecting allocator operations
        Private allocLock As Sync.Spinlock

        Public Sub Initialize(ByVal basePhys As UInt64, ByVal sizeBytes As UInt64)
            Sync.SpinlockOps.Init allocLock

            ' Align base address up to 4MB boundary for Order 10 alignment
            Dim alignMask As UInt64 = (CPtr(UInt64, 1) LShift 22) - 1
            Dim alignedBase As UInt64 = (basePhys + alignMask) And (Not alignMask)

            If sizeBytes > (alignedBase - basePhys) Then
                sizeBytes = sizeBytes - (alignedBase - basePhys)
            Else
                sizeBytes = 0
            End If

            ' Align size down to 4MB boundary
            sizeBytes = sizeBytes And (Not alignMask)

            poolBasePhys = alignedBase
            poolSizePhys = sizeBytes
            totalPages = poolSizePhys RShift 12

            ' Initialize free lists
            Dim o As UInt32
            For o = 0 To MAX_ORDER
                freeLists(o) = 0
                freeCount(o) = 0
            Next o

            ' Populate initial memory into largest possible chunks (Order 10 = 4MB)
            If poolSizePhys > 0 Then
                Dim maxBlockSize As UInt64 = PAGE_SIZE LShift MAX_ORDER ' 4MB
                Dim currAddr As UInt64 = poolBasePhys
                Dim endAddr As UInt64 = poolBasePhys + poolSizePhys

                While (currAddr + maxBlockSize) <= endAddr
                    Me.AddFreeBlock MAX_ORDER, currAddr
                    currAddr = currAddr + maxBlockSize
                Wend
            End If
        End Sub

        ' Add a block to the free list of the given order
        Private Unsafe Sub AddFreeBlock(ByVal order As UInt32, ByVal blockPhys As UInt64)
            Dim node As Volatile Pointer To UInt64
            node = CPtr(Volatile Pointer To UInt64, blockPhys)
            node(0) = freeLists(order)
            freeLists(order) = blockPhys
            freeCount(order) = freeCount(order) + 1
        End Sub

        ' Remove a block from the free list of the given order
        Private Unsafe Function RemoveFreeBlock(ByVal order As UInt32) As UInt64
            If freeLists(order) = 0 Then
                RemoveFreeBlock = 0
                Exit Function
            End If

            Dim blockPhys As UInt64 = freeLists(order)
            Dim node As Volatile Pointer To UInt64
            node = CPtr(Volatile Pointer To UInt64, blockPhys)
            freeLists(order) = node(0)
            freeCount(order) = freeCount(order) - 1

            RemoveFreeBlock = blockPhys
        End Function

        ' Remove a specific block from the free list of the given order (used during buddy merge)
        Private Unsafe Function RemoveSpecificBlock(ByVal order As UInt32, ByVal targetPhys As UInt64) As Boolean
            Dim curr As UInt64 = freeLists(order)
            Dim prev As UInt64 = 0

            While curr <> 0
                If curr = targetPhys Then
                    Dim node As Volatile Pointer To UInt64
                    node = CPtr(Volatile Pointer To UInt64, curr)

                    If prev = 0 Then
                        freeLists(order) = node(0)
                    Else
                        Dim prevNode As Volatile Pointer To UInt64
                        prevNode = CPtr(Volatile Pointer To UInt64, prev)
                        prevNode(0) = node(0)
                    End If

                    freeCount(order) = freeCount(order) - 1
                    RemoveSpecificBlock = True
                    Exit Function
                End If

                prev = curr
                Dim currNode As Volatile Pointer To UInt64
                currNode = CPtr(Volatile Pointer To UInt64, curr)
                curr = currNode(0)
            Wend

            RemoveSpecificBlock = False
        End Function

        ' Allocate 2^order contiguous physical pages
        Public Unsafe Function AllocPages(ByVal order As UInt32) As UInt64
            If order > MAX_ORDER Then
                AllocPages = 0
                Exit Function
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(allocLock)

            ' Find smallest available order >= requested order
            Dim currOrder As UInt32 = order
            While currOrder <= MAX_ORDER And freeLists(currOrder) = 0
                currOrder = currOrder + 1
            Wend

            ' Out of memory for this order
            If currOrder > MAX_ORDER Then
                Sync.SpinlockOps.ReleaseIrqRestore allocLock, flags
                AllocPages = 0
                Exit Function
            End If

            ' Pop block from the higher order
            Dim blockPhys As UInt64 = Me.RemoveFreeBlock(currOrder)

            ' Split downward until target order is reached
            While currOrder > order
                currOrder = currOrder - 1
                Dim halfSize As UInt64 = PAGE_SIZE LShift currOrder
                Dim buddyPhys As UInt64 = blockPhys + halfSize
                Me.AddFreeBlock currOrder, buddyPhys
            Wend

            Sync.SpinlockOps.ReleaseIrqRestore allocLock, flags
            AllocPages = blockPhys
        End Function

        ' Free 2^order contiguous physical pages and merge with buddies recursively
        Public Unsafe Sub FreePages(ByVal blockPhys As UInt64, ByVal order As UInt32)
            If blockPhys < poolBasePhys Or blockPhys >= (poolBasePhys + poolSizePhys) Then
                Exit Sub
            End If

            If order > MAX_ORDER Then
                Exit Sub
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(allocLock)

            Dim currOrder As UInt32 = order
            Dim currBlock As UInt64 = blockPhys

            ' Recursively merge with buddy if available in free list
            While currOrder < MAX_ORDER
                ' Calculate buddy physical address
                Dim blockIdx As UInt64 = (currBlock - poolBasePhys) RShift 12
                Dim buddyIdx As UInt64 = blockIdx Xor (CPtr(UInt64, 1) LShift currOrder)
                Dim buddyPhys As UInt64 = poolBasePhys + (buddyIdx LShift 12)

                ' Check if buddy is beyond managed pool bounds
                If buddyPhys < poolBasePhys Or buddyPhys >= (poolBasePhys + poolSizePhys) Then
                    Exit While
                End If

                ' Attempt to remove buddy from the current order free list
                If Me.RemoveSpecificBlock(currOrder, buddyPhys) Then
                    ' Merged block takes the lower base address
                    If buddyPhys < currBlock Then
                        currBlock = buddyPhys
                    End If
                    currOrder = currOrder + 1
                Else
                    ' Buddy is currently allocated or split; cannot merge further
                    Exit While
                End If
            Wend

            ' Add final coalesced block to the free list
            Me.AddFreeBlock currOrder, currBlock

            Sync.SpinlockOps.ReleaseIrqRestore allocLock, flags
        End Sub

        ' Return number of free blocks in a given order
        Public Function GetFreeBlockCount(ByVal order As UInt32) As UInt64
            If order <= MAX_ORDER Then
                GetFreeBlockCount = freeCount(order)
            Else
                GetFreeBlockCount = 0
            End If
        End Function

        ' Return managed pool physical base address
        Public Function GetPoolBase() As UInt64
            GetPoolBase = poolBasePhys
        End Function

        ' Return managed pool size in bytes
        Public Function GetPoolSize() As UInt64
            GetPoolSize = poolSizePhys
        End Function

        ' Print status of buddy orders to serial console
        Public Unsafe Sub DumpStats()
            Drivers.SerialUart.PrintF "[BUDDY] Managed Pool: 0x%x - 0x%x (%u MB)\r\n", poolBasePhys, poolBasePhys + poolSizePhys, CType(UInt32, poolSizePhys RShift 20)
            Dim o As UInt32
            For o = 0 To MAX_ORDER
                Dim blkSizeKb As UInt32 = CType(UInt32, (PAGE_SIZE LShift o) RShift 10)
                Drivers.SerialUart.PrintF "  [Order %u] Size: %u KB | Free: %u blocks\r\n", o, blkSizeKb, CType(UInt32, freeCount(o))
            Next o
        End Sub

    End Class

End Namespace
