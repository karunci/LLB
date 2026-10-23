' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/mem/VirtualMemoryManager.cls
' Summary: 4-level x86_64 Virtual Memory Manager (PML4, PDPT, PD, PT) with 4KB page granularity.

Import Sync
Import Arch.X86_64.PortIO
Use Mem.BuddyAllocator
Use Drivers.SerialUart

Namespace Mem

    ' 4-Level x86_64 Paging Table Constants and Attributes
    Public Module VmmFlags
        Public Const PTE_PRESENT As UInt64        = &H0000000000000001
        Public Const PTE_WRITABLE As UInt64       = &H0000000000000002
        Public Const PTE_USER As UInt64           = &H0000000000000004
        Public Const PTE_WRITE_THROUGH As UInt64  = &H0000000000000008
        Public Const PTE_CACHE_DISABLE As UInt64  = &H0000000000000010
        Public Const PTE_ACCESSED As UInt64       = &H0000000000000020
        Public Const PTE_DIRTY As UInt64          = &H0000000000000040
        Public Const PTE_HUGE As UInt64           = &H0000000000000080
        Public Const PTE_GLOBAL As UInt64         = &H0000000000000100
        Public Const PTE_NO_EXECUTE As UInt64     = &H8000000000000000
        Public Const PTE_FRAME_MASK As UInt64     = &H000FFFFFFFFFF000
    End Module

    <Instancing(SingleUse)>
    Public Class VirtualMemoryManager

        Private kernelPml4Phys As UInt64
        Private vmmLock As Sync.Spinlock

        Public Sub Initialize()
            Sync.SpinlockOps.Init vmmLock
            ' Fetch current active PML4 pointer from hardware CR3
            kernelPml4Phys = Arch.X86_64.PortIO.ReadCr3()
        End Sub

        ' Return physical base of active kernel PML4 table
        Public Function GetKernelPml4() As UInt64
            GetKernelPml4 = kernelPml4Phys
        End Function

        ' Extract PML4 index (bits 39..47)
        Public Function Pml4Index(ByVal virtAddr As UInt64) As UInt32
            Pml4Index = CType(UInt32, (virtAddr RShift 39) And &H1FF)
        End Function

        ' Extract PDPT index (bits 30..38)
        Public Function PdptIndex(ByVal virtAddr As UInt64) As UInt32
            PdptIndex = CType(UInt32, (virtAddr RShift 30) And &H1FF)
        End Function

        ' Extract Page Directory index (bits 21..29)
        Public Function PdIndex(ByVal virtAddr As UInt64) As UInt32
            PdIndex = CType(UInt32, (virtAddr RShift 21) And &H1FF)
        End Function

        ' Extract Page Table index (bits 12..20)
        Public Function PtIndex(ByVal virtAddr As UInt64) As UInt32
            PtIndex = CType(UInt32, (virtAddr RShift 12) And &H1FF)
        End Function

        ' Helper to allocate and clear a 4KB page table frame using BuddyAllocator (Order 0)
        Private Unsafe Function AllocTableFrame() As UInt64
            Dim framePhys As UInt64 = Mem.BuddyAllocator.AllocPages(0)
            If framePhys <> 0 Then
                ' Clear all 512 64-bit entries (4096 bytes)
                Dim tablePtr As Volatile Pointer To UInt64
                tablePtr = CPtr(Volatile Pointer To UInt64, framePhys)
                Dim i As UInt32
                For i = 0 To 511
                    tablePtr(i) = 0
                Next i
            End If
            AllocTableFrame = framePhys
        End Function

        ' Map a single 4KB virtual page to physical frame with specified flags
        Public Unsafe Function MapPage(ByVal pml4Phys As UInt64, ByVal virtAddr As UInt64, ByVal physAddr As UInt64, ByVal flags As UInt64) As Boolean
            If pml4Phys = 0 Then
                MapPage = False
                Exit Function
            End If

            Dim l4Idx As UInt32 = Me.Pml4Index(virtAddr)
            Dim l3Idx As UInt32 = Me.PdptIndex(virtAddr)
            Dim l2Idx As UInt32 = Me.PdIndex(virtAddr)
            Dim l1Idx As UInt32 = Me.PtIndex(virtAddr)

            Dim pml4Table As Volatile Pointer To UInt64
            pml4Table = CPtr(Volatile Pointer To UInt64, pml4Phys)

            ' 1. Walk or Allocate PDPT (Level 3)
            Dim pdptPhys As UInt64 = 0
            If (pml4Table(l4Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                pdptPhys = Me.AllocTableFrame()
                If pdptPhys = 0 Then
                    MapPage = False
                    Exit Function
                End If
                pml4Table(l4Idx) = pdptPhys Or VmmFlags.PTE_PRESENT Or VmmFlags.PTE_WRITABLE Or (flags And VmmFlags.PTE_USER)
            Else
                pdptPhys = pml4Table(l4Idx) And VmmFlags.PTE_FRAME_MASK
            End If

            ' 2. Walk or Allocate Page Directory (Level 2)
            Dim pdptTable As Volatile Pointer To UInt64
            pdptTable = CPtr(Volatile Pointer To UInt64, pdptPhys)

            Dim pdPhys As UInt64 = 0
            If (pdptTable(l3Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                pdPhys = Me.AllocTableFrame()
                If pdPhys = 0 Then
                    MapPage = False
                    Exit Function
                End If
                pdptTable(l3Idx) = pdPhys Or VmmFlags.PTE_PRESENT Or VmmFlags.PTE_WRITABLE Or (flags And VmmFlags.PTE_USER)
            Else
                pdPhys = pdptTable(l3Idx) And VmmFlags.PTE_FRAME_MASK
            End If

            ' 3. Walk or Allocate Page Table (Level 1)
            Dim pdTable As Volatile Pointer To UInt64
            pdTable = CPtr(Volatile Pointer To UInt64, pdPhys)

            Dim ptPhys As UInt64 = 0
            If (pdTable(l2Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                ptPhys = Me.AllocTableFrame()
                If ptPhys = 0 Then
                    MapPage = False
                    Exit Function
                End If
                pdTable(l2Idx) = ptPhys Or VmmFlags.PTE_PRESENT Or VmmFlags.PTE_WRITABLE Or (flags And VmmFlags.PTE_USER)
            Else
                ptPhys = pdTable(l2Idx) And VmmFlags.PTE_FRAME_MASK
            End If

            ' 4. Set leaf PTE entry in Level 1 Page Table
            Dim ptTable As Volatile Pointer To UInt64
            ptTable = CPtr(Volatile Pointer To UInt64, ptPhys)

            ptTable(l1Idx) = (physAddr And VmmFlags.PTE_FRAME_MASK) Or flags Or VmmFlags.PTE_PRESENT

            ' Invalidate TLB entry
            Arch.X86_64.PortIO.Invlpg virtAddr

            MapPage = True
        End Function

        ' Translate virtual address to physical address, returning 0 if unmapped
        Public Unsafe Function VirtToPhys(ByVal pml4Phys As UInt64, ByVal virtAddr As UInt64) As UInt64
            If pml4Phys = 0 Then
                VirtToPhys = 0
                Exit Function
            End If

            Dim l4Idx As UInt32 = Me.Pml4Index(virtAddr)
            Dim l3Idx As UInt32 = Me.PdptIndex(virtAddr)
            Dim l2Idx As UInt32 = Me.PdIndex(virtAddr)
            Dim l1Idx As UInt32 = Me.PtIndex(virtAddr)

            Dim pml4Table As Volatile Pointer To UInt64
            pml4Table = CPtr(Volatile Pointer To UInt64, pml4Phys)
            If (pml4Table(l4Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                VirtToPhys = 0
                Exit Function
            End If

            Dim pdptTable As Volatile Pointer To UInt64
            pdptTable = CPtr(Volatile Pointer To UInt64, pml4Table(l4Idx) And VmmFlags.PTE_FRAME_MASK)
            If (pdptTable(l3Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                VirtToPhys = 0
                Exit Function
            End If

            Dim pdTable As Volatile Pointer To UInt64
            pdTable = CPtr(Volatile Pointer To UInt64, pdptTable(l3Idx) And VmmFlags.PTE_FRAME_MASK)
            If (pdTable(l2Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                VirtToPhys = 0
                Exit Function
            End If

            ' If 2MB huge page entry
            If (pdTable(l2Idx) And VmmFlags.PTE_HUGE) <> 0 Then
                Dim hugeBase As UInt64 = pdTable(l2Idx) And &H000FFFFFFFE00000
                VirtToPhys = hugeBase Or (virtAddr And &H1FFFFF)
                Exit Function
            End If

            Dim ptTable As Volatile Pointer To UInt64
            ptTable = CPtr(Volatile Pointer To UInt64, pdTable(l2Idx) And VmmFlags.PTE_FRAME_MASK)
            If (ptTable(l1Idx) And VmmFlags.PTE_PRESENT) = 0 Then
                VirtToPhys = 0
                Exit Function
            End If

            Dim frameBase As UInt64 = ptTable(l1Idx) And VmmFlags.PTE_FRAME_MASK
            VirtToPhys = frameBase Or (virtAddr And &HFFF)
        End Function

        ' Unmap a single 4KB virtual page
        Public Unsafe Sub UnmapPage(ByVal pml4Phys As UInt64, ByVal virtAddr As UInt64)
            If pml4Phys = 0 Then
                Exit Sub
            End If

            Dim l4Idx As UInt32 = Me.Pml4Index(virtAddr)
            Dim l3Idx As UInt32 = Me.PdptIndex(virtAddr)
            Dim l2Idx As UInt32 = Me.PdIndex(virtAddr)
            Dim l1Idx As UInt32 = Me.PtIndex(virtAddr)

            Dim pml4Table As Volatile Pointer To UInt64
            pml4Table = CPtr(Volatile Pointer To UInt64, pml4Phys)
            If (pml4Table(l4Idx) And VmmFlags.PTE_PRESENT) = 0 Then Exit Sub

            Dim pdptTable As Volatile Pointer To UInt64
            pdptTable = CPtr(Volatile Pointer To UInt64, pml4Table(l4Idx) And VmmFlags.PTE_FRAME_MASK)
            If (pdptTable(l3Idx) And VmmFlags.PTE_PRESENT) = 0 Then Exit Sub

            Dim pdTable As Volatile Pointer To UInt64
            pdTable = CPtr(Volatile Pointer To UInt64, pdptTable(l3Idx) And VmmFlags.PTE_FRAME_MASK)
            If (pdTable(l2Idx) And VmmFlags.PTE_PRESENT) = 0 Then Exit Sub

            Dim ptTable As Volatile Pointer To UInt64
            ptTable = CPtr(Volatile Pointer To UInt64, pdTable(l2Idx) And VmmFlags.PTE_FRAME_MASK)
            ptTable(l1Idx) = 0

            Arch.X86_64.PortIO.Invlpg virtAddr
        End Sub

        ' Map contiguous physical range to contiguous virtual range
        Public Unsafe Function MapRange(ByVal pml4Phys As UInt64, ByVal virtStart As UInt64, ByVal physStart As UInt64, ByVal sizeBytes As UInt64, ByVal flags As UInt64) As Boolean
            Dim currVirt As UInt64 = virtStart
            Dim currPhys As UInt64 = physStart
            Dim endVirt As UInt64 = virtStart + sizeBytes

            While currVirt < endVirt
                If Not Me.MapPage(pml4Phys, currVirt, currPhys, flags) Then
                    MapRange = False
                    Exit Function
                End If
                currVirt = currVirt + 4096
                currPhys = currPhys + 4096
            Wend

            MapRange = True
        End Function

    End Class

End Namespace
