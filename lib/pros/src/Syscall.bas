' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Syscall.bas
' Summary: Low-Level Basic system call primitives for Ring 3 applications and drivers.

Namespace Pros.Sys

    Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
    Public Const SYS_PROCESS_YIELD   As UInt64 = 2
    Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
    Public Const SYS_PROCESS_GETPID  As UInt64 = 6
    Public Const SYS_PROCESS_EXIT    As UInt64 = 16
    Public Const SYS_GET_MOUSE       As UInt64 = 19
    Public Const SYS_GET_KEY         As UInt64 = 20
    Public Const SYS_MEM_ALLOC_PAGES As UInt64 = 26
    Public Const SYS_TIME_UPTIME     As UInt64 = 28
    Public Const SYS_SMP_CORE_COUNT  As UInt64 = 34

    Public Const SYS_NODE_REGISTER   As UInt64 = 50
    Public Const SYS_SYNAPSE_CONNECT As UInt64 = 51
    Public Const SYS_SYNAPSE_PUSH    As UInt64 = 52
    Public Const SYS_SYNAPSE_POP     As UInt64 = 53
    Public Const SYS_NODE_LOOKUP     As UInt64 = 55

    Public Const SYS_SHMEM_CREATE    As UInt64 = 60
    Public Const SYS_SHMEM_ATTACH    As UInt64 = 61
    Public Const SYS_SHMEM_DETACH    As UInt64 = 62

    Public Const SYS_FB_GET_INFO     As UInt64 = 70
    Public Const SYS_FB_MAP          As UInt64 = 71

    Public Const SYS_INITRD_GET_INFO As UInt64 = 80
    Public Const SYS_INITRD_MAP      As UInt64 = 81

    <Packed>
    Public Structure InitrdInfo
        Public PhysAddr  As UInt64
        Public SizeBytes As UInt64
    End Structure

    Public Module RawSyscall

        ''
        ' @brief Invoke x86_64 syscall instruction with 0 arguments.
        ''
        Public Unsafe Function Call0(ByVal id As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "syscall" : "=a"(ret) : "a"(id) : "rcx", "r11", "memory"
            Call0 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 1 argument.
        ''
        Public Unsafe Function Call1(ByVal id As UInt64, ByVal a1 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1) : "rcx", "r11", "memory"
            Call1 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 2 arguments.
        ''
        Public Unsafe Function Call2(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2) : "rcx", "r11", "memory"
            Call2 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 3 arguments.
        ''
        Public Unsafe Function Call3(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64, ByVal a3 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory"
            Call3 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 4 arguments.
        ''
        Public Unsafe Function Call4(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64, ByVal a3 As UInt64, ByVal a4 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "movq %4, %%r10\n\tsyscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3), "r"(a4) : "rcx", "r11", "r10", "memory"
            Call4 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 5 arguments.
        ''
        Public Unsafe Function Call5(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64, ByVal a3 As UInt64, ByVal a4 As UInt64, ByVal a5 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "movq %4, %%r10\n\tmovq %5, %%r8\n\tsyscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3), "r"(a4), "r"(a5) : "rcx", "r11", "r10", "r8", "memory"
            Call5 = ret
        End Function

    End Module

End Namespace
