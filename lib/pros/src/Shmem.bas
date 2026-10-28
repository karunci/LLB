' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Shmem.bas
' Summary: Zero-Copy Shared Memory Client Library for Ring 3.

Import Pros.Sys.RawSyscall

Namespace Pros.Memory

    Public Module Shmem

        ''
        ' @brief Allocate a zero-copy shared memory object.
        ' @param sizeBytes Size in bytes (rounded up to 4KB page boundary).
        ' @param targetVaddr Optional virtual address, or 0 for kernel ASLR allocation.
        ' @return Assigned Shared Memory ID (SHMID), or 0 on failure.
        ''
        Public Unsafe Function Create(ByVal sizeBytes As UInt64, ByVal targetVaddr As UInt64) As UInt64
            Create = Pros.Sys.RawSyscall.Call2(Pros.Sys.SYS_SHMEM_CREATE, sizeBytes, targetVaddr)
        End Function

        ''
        ' @brief Attach an existing shared memory object to calling process address space.
        ' @param shmid Shared memory ID.
        ' @param targetVaddr Optional virtual address, or 0 for ASLR.
        ' @return Base virtual address where shared pages were mapped, or 0 on failure.
        ''
        Public Unsafe Function Attach(ByVal shmid As UInt64, ByVal targetVaddr As UInt64) As UInt64
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call2(Pros.Sys.SYS_SHMEM_ATTACH, shmid, targetVaddr)
            If res = targetVaddr Then
                Attach = targetVaddr
            Else
                Attach = 0
            End If
        End Function

        ''
        ' @brief Detach and unmap a shared memory object from calling process.
        ' @param shmid Shared memory ID.
        ' @return True if detached cleanly, False otherwise.
        ''
        Public Unsafe Function Detach(ByVal shmid As UInt64) As Boolean
            Dim ret As UInt64 = Pros.Sys.RawSyscall.Call1(Pros.Sys.SYS_SHMEM_DETACH, shmid)
            Detach = (ret = 1)
        End Function

    End Module

End Namespace
