' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/mem/SharedMemoryManager.cls
' Summary: Zero-copy shared memory manager providing cross-process memory gradients.
'          Ports PRK kernel/shmem.c.

Import Sync
Import Mem
Use Drivers.SerialUart As Serial
Use Mem.BuddyAllocator As Buddy
Use Mem.VirtualMemoryManager As VMM

Namespace Mem

    Public Module ShmemConstants
        Public Const MAX_SHMEM_OBJECTS As UInt32 = 64
        Public Const MAX_SHMEM_PAGES   As UInt32 = 1024 ' 1024 pages = 4MB
    End Module

    <Packed>
    Public Structure ShmemObject
        Public Active     As Boolean
        Public Id         As UInt64
        Public NumPages   As UInt32
        Public OwnerPid   As UInt64
        Public RefCount   As UInt32
        Public PhysFrames(1023) As UInt64
        Public Lock       As Sync.Spinlock
    End Structure

    <Instancing(SingleUse)>
    Public Class SharedMemoryManager

        Private registry(64) As ShmemObject
        Private registryLock As Sync.Spinlock
        Private nextShmId    As UInt64

        ''
        ' @brief Initialize the Zero-Copy Shared Memory Subsystem.
        ''
        Public Sub Initialize()
            Sync.SpinlockOps.Init registryLock
            nextShmId = 1

            Dim i As UInt32 = 0
            While i < ShmemConstants.MAX_SHMEM_OBJECTS
                registry(i).Active = False
                registry(i).Id = 0
                registry(i).NumPages = 0
                registry(i).OwnerPid = 0
                registry(i).RefCount = 0
                Sync.SpinlockOps.Init registry(i).Lock
                i = i + 1
            Wend

            Serial.PrintF "[SHMEM] Zero-Copy Shared Memory Subsystem Initialized (Max: %u Objects, %u MB/Obj).\r\n", _
                          ShmemConstants.MAX_SHMEM_OBJECTS, (ShmemConstants.MAX_SHMEM_PAGES * 4096) RShift 20
        End Sub

        ''
        ' @brief Creates a shared memory block and maps it to the creator's virtual address.
        ' @param sizeBytes Size in bytes requested.
        ' @param targetVaddr User virtual address where memory should be mapped.
        ' @param pml4Phys Physical address of the creator's User PML4 table.
        ' @param callerPid Process ID of the creator.
        ' @return Globally unique SHMID (>0) or negative error code.
        ''
        Public Unsafe Function CreateShmem(ByVal sizeBytes As UInt64, ByVal targetVaddr As UInt64, ByVal pml4Phys As UInt64, ByVal callerPid As UInt64) As Int64
            If sizeBytes = 0 Or sizeBytes > (CType(UInt64, ShmemConstants.MAX_SHMEM_PAGES) * 4096) Then
                CreateShmem = -1
                Exit Function
            End If

            If targetVaddr = 0 Or pml4Phys = 0 Then
                CreateShmem = -1
                Exit Function
            End If

            Dim pagesNeeded As UInt32 = CType(UInt32, (sizeBytes + 4095) / 4096)

            Dim regFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim slot As Int32 = -1
            Dim i As UInt32 = 0
            While i < ShmemConstants.MAX_SHMEM_OBJECTS
                If Not registry(i).Active Then
                    slot = CType(Int32, i)
                    Exit While
                End If
                i = i + 1
            Wend

            If slot = -1 Then
                Sync.SpinlockOps.ReleaseIrqRestore registryLock, regFlags
                CreateShmem = -2
                Exit Function
            End If

            Dim uSlot As UInt32 = CType(UInt32, slot)
            Dim objFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registry(uSlot).Lock)

            Dim assignedId As UInt64 = nextShmId
            nextShmId = nextShmId + 1

            registry(uSlot).Active = True
            registry(uSlot).Id = assignedId
            registry(uSlot).NumPages = pagesNeeded
            registry(uSlot).RefCount = 1
            registry(uSlot).OwnerPid = callerPid

            Sync.SpinlockOps.ReleaseIrqRestore registryLock, regFlags

            ' Allocate physical frames and map them into caller's User PML4
            Dim allocatedCount As UInt32 = 0
            Dim pi As UInt32 = 0
            While pi < pagesNeeded
                Dim phys As UInt64 = Buddy.AllocPages(0)
                If phys = 0 Then
                    ' Roll back previously allocated pages
                    Dim r As UInt32 = 0
                    While r < allocatedCount
                        Buddy.FreePages registry(uSlot).PhysFrames(r), 0
                        r = r + 1
                    Wend
                    registry(uSlot).Active = False
                    registry(uSlot).Id = 0
                    registry(uSlot).NumPages = 0
                    registry(uSlot).RefCount = 0
                    registry(uSlot).OwnerPid = 0
                    Sync.SpinlockOps.ReleaseIrqRestore registry(uSlot).Lock, objFlags
                    CreateShmem = -3
                    Exit Function
                End If

                ' Zero the newly allocated page
                Dim vPtr As Volatile Pointer To UInt64 = CPtr(Volatile Pointer To UInt64, phys)
                Dim k As UInt32 = 0
                While k < 512
                    vPtr(k) = 0
                    k = k + 1
                Wend

                registry(uSlot).PhysFrames(pi) = phys
                allocatedCount = allocatedCount + 1

                ' Map page with Present, Writable, User flags
                VMM.MapPage pml4Phys, targetVaddr + (CType(UInt64, pi) * 4096), phys, &H07

                pi = pi + 1
            Wend

            Sync.SpinlockOps.ReleaseIrqRestore registry(uSlot).Lock, objFlags
            Serial.PrintF "[SHMEM] Created SHMID %u (%u pages, %u KB) for PID %u @ vaddr 0x%lx\r\n", _
                          CType(UInt32, assignedId), pagesNeeded, pagesNeeded * 4, CType(UInt32, callerPid), targetVaddr
            CreateShmem = CType(Int64, assignedId)
        End Function

        ''
        ' @brief Attaches an existing SHMID to another process's virtual address space.
        ' @param shmid Target shared memory ID.
        ' @param targetVaddr Destination virtual address in attacher's space.
        ' @param pml4Phys Physical address of the attacher's User PML4 table.
        ' @return 0 on success, negative error code otherwise.
        ''
        Public Unsafe Function AttachShmem(ByVal shmid As Int64, ByVal targetVaddr As UInt64, ByVal pml4Phys As UInt64) As Int64
            If shmid <= 0 Or targetVaddr = 0 Or pml4Phys = 0 Then
                AttachShmem = -1
                Exit Function
            End If

            Dim regFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim slot As Int32 = -1
            Dim i As UInt32 = 0
            While i < ShmemConstants.MAX_SHMEM_OBJECTS
                If registry(i).Active And registry(i).Id = CType(UInt64, shmid) Then
                    slot = CType(Int32, i)
                    Exit While
                End If
                i = i + 1
            Wend
            Sync.SpinlockOps.ReleaseIrqRestore registryLock, regFlags

            If slot = -1 Then
                AttachShmem = -1
                Exit Function
            End If

            Dim uSlot As UInt32 = CType(UInt32, slot)
            Dim objFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registry(uSlot).Lock)

            If Not registry(uSlot).Active Or registry(uSlot).Id <> CType(UInt64, shmid) Then
                Sync.SpinlockOps.ReleaseIrqRestore registry(uSlot).Lock, objFlags
                AttachShmem = -1
                Exit Function
            End If

            ' Increment active reference count
            registry(uSlot).RefCount = registry(uSlot).RefCount + 1

            ' Map all physical frames into attacher's PML4
            Dim pi As UInt32 = 0
            While pi < registry(uSlot).NumPages
                VMM.MapPage pml4Phys, targetVaddr + (CType(UInt64, pi) * 4096), registry(uSlot).PhysFrames(pi), &H07
                pi = pi + 1
            Wend

            Sync.SpinlockOps.ReleaseIrqRestore registry(uSlot).Lock, objFlags
            Serial.PrintF "[SHMEM] Attached SHMID %u to PML4 0x%lx @ vaddr 0x%lx (Refs: %u)\r\n", _
                          CType(UInt32, shmid), pml4Phys, targetVaddr, registry(uSlot).RefCount
            AttachShmem = 0
        End Function

        ''
        ' @brief Detach and decrement reference count of a shared memory block.
        ' @param shmid Target shared memory ID.
        ' @return 0 on success, negative error code otherwise.
        ''
        Public Unsafe Function DetachShmem(ByVal shmid As Int64) As Int64
            If shmid <= 0 Then
                DetachShmem = -1
                Exit Function
            End If

            Dim regFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim slot As Int32 = -1
            Dim i As UInt32 = 0
            While i < ShmemConstants.MAX_SHMEM_OBJECTS
                If registry(i).Active And registry(i).Id = CType(UInt64, shmid) Then
                    slot = CType(Int32, i)
                    Exit While
                End If
                i = i + 1
            Wend
            Sync.SpinlockOps.ReleaseIrqRestore registryLock, regFlags

            If slot = -1 Then
                DetachShmem = -1
                Exit Function
            End If

            Dim uSlot As UInt32 = CType(UInt32, slot)
            Dim objFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registry(uSlot).Lock)

            If registry(uSlot).RefCount > 0 Then
                registry(uSlot).RefCount = registry(uSlot).RefCount - 1
            End If

            ' If all references are gone, reclaim the physical frames
            If registry(uSlot).RefCount = 0 Then
                Dim pagesRecovered As UInt32 = registry(uSlot).NumPages
                Dim j As UInt32 = 0
                While j < pagesRecovered
                    Buddy.FreePages registry(uSlot).PhysFrames(j), 0
                    j = j + 1
                Wend
                registry(uSlot).Active = False
                registry(uSlot).Id = 0
                registry(uSlot).NumPages = 0
                registry(uSlot).OwnerPid = 0
                Serial.PrintF "[SHMEM] Fully reclaimed %u pages for SHMID %u (0 references remaining)\r\n", _
                              pagesRecovered, CType(UInt32, shmid)
            Else
                Serial.PrintF "[SHMEM] SHMID %u detached (Remaining refs: %u)\r\n", _
                              CType(UInt32, shmid), registry(uSlot).RefCount
            End If

            Sync.SpinlockOps.ReleaseIrqRestore registry(uSlot).Lock, objFlags
            DetachShmem = 0
        End Function

        ''
        ' @brief Scrub orphaned references on process termination.
        ' @param pid Dead process ID.
        ''
        Public Unsafe Sub CleanupPid(ByVal pid As UInt64)
            If pid = 0 Then Exit Sub

            Dim regFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim i As UInt32 = 0
            While i < ShmemConstants.MAX_SHMEM_OBJECTS
                If registry(i).Active And registry(i).OwnerPid = pid Then
                    Dim objFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registry(i).Lock)
                    registry(i).OwnerPid = 0

                    If registry(i).RefCount > 0 Then
                        registry(i).RefCount = registry(i).RefCount - 1
                    End If

                    If registry(i).RefCount = 0 Then
                        Dim pagesRecovered As UInt32 = registry(i).NumPages
                        Dim j As UInt32 = 0
                        While j < pagesRecovered
                            Buddy.FreePages registry(i).PhysFrames(j), 0
                            j = j + 1
                        Wend
                        registry(i).Active = False
                        registry(i).Id = 0
                        registry(i).NumPages = 0
                        Serial.PrintF "[SHMEM] Reclaimed %u pages for dead PID %u (No active references)\r\n", _
                                      pagesRecovered, CType(UInt32, pid)
                    Else
                        Serial.PrintF "[SHMEM] App reference dropped for dead PID %u (Preserved for active peers: %u refs left)\r\n", _
                                      CType(UInt32, pid), registry(i).RefCount
                    End If

                    Sync.SpinlockOps.ReleaseIrqRestore registry(i).Lock, objFlags
                End If
                i = i + 1
            Wend
            Sync.SpinlockOps.ReleaseIrqRestore registryLock, regFlags
        End Sub

    End Class

End Namespace
