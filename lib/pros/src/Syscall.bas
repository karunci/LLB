' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Syscall.bas
' Summary: Low-Level Basic system call primitives for Ring 3 applications and drivers.

Namespace Pros.Sys

    Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
    Public Const SYS_PROCESS_YIELD   As UInt64 = 2
    Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
    Public Const SYS_PROCESS_GETPID  As UInt64 = 6
    Public Const SYS_PROCESS_SPAWN   As UInt64 = 10
    Public Const SYS_PROCESS_WAIT    As UInt64 = 11
    Public Const SYS_PROCESS_EXIT    As UInt64 = 16
    Public Const SYS_GET_MOUSE       As UInt64 = 19
    Public Const SYS_GET_KEY         As UInt64 = 20
    Public Const SYS_MEM_ALLOC_PAGES As UInt64 = 26
    Public Const SYS_TIME_UPTIME     As UInt64 = 28
    Public Const SYS_TIME_GET_RTC    As UInt64 = 29
    Public Const SYS_TIME_GET_TICKS  As UInt64 = 30
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

    Public Const SYS_PCI_GET_DEVICE_COUNT As UInt64 = 72
    Public Const SYS_PCI_GET_DEVICE       As UInt64 = 73
    Public Const SYS_PCI_MAP_BAR          As UInt64 = 74
    Public Const SYS_PORT_IN              As UInt64 = 75
    Public Const SYS_PORT_OUT             As UInt64 = 76
    Public Const SYS_GET_SYSTEM_METRICS   As UInt64 = 77

    Public Const SYS_INITRD_GET_INFO As UInt64 = 80
    Public Const SYS_INITRD_MAP      As UInt64 = 81

    <Packed>
    Public Structure InitrdInfo
        Public PhysAddr  As UInt64
        Public SizeBytes As UInt64
    End Structure

    <Packed>
    Public Structure CpuCoreMetric
        Public ActiveTicks As UInt64
        Public IdleTicks   As UInt64
        Public TotalTicks  As UInt64
        Public LoadPercent As UInt32
        Public Reserved    As UInt32
    End Structure

    <Packed>
    Public Structure SystemMetrics
        Public CpuCount        As UInt32
        Public Reserved0       As UInt32
        Public SchedUptimeMs   As UInt64
        Public Cores(15)       As CpuCoreMetric

        ' RAM
        Public TotalRamBytes   As UInt64
        Public FreeRamBytes    As UInt64
        Public UsedRamBytes    As UInt64
        Public BuddyPoolBytes  As UInt64
        Public HeapAllocBytes  As UInt64

        ' VRAM & Display
        Public DisplayWidth    As UInt32
        Public DisplayHeight   As UInt32
        Public DisplayPitch    As UInt32
        Public DisplayBpp      As UInt32
        Public VramTotalBytes  As UInt64
        Public VramUsedBytes   As UInt64

        ' GPU
        Public GpuVendorId     As UInt16
        Public GpuDeviceId     As UInt16
        Public GpuSubsystemId  As UInt16
        Public GpuBar0IoPort   As UInt16
        Public GpuBar1FbPhys   As UInt64
        Public GpuBar2FifoPhys As UInt64
        Public GpuDriverType   As UInt32 ' 0 = GOP/VESA LFB, 1 = VMware SVGA-II, 2 = VirtIO-GPU
    End Structure

    <Packed>
    Public Structure RtcTime
        Public Year          As UInt16
        Public Month         As Byte
        Public Day           As Byte
        Public Hour          As Byte
        Public Minute        As Byte
        Public Second        As Byte
        Public Pad           As Byte
        Public UnixTimestamp As UInt64
    End Structure

    Public Module RawSyscall

        ''
        ' @brief Query CMOS Real-Time Clock hardware registers.
        ' @param rtc Destination RtcTime structure.
        ' @return True if read succeeded.
        ''
        Public Unsafe Function GetRealTime(ByRef rtc As RtcTime) As Boolean
            GetRealTime = (Call1(SYS_TIME_GET_RTC, UInt64(AddressOf rtc)) <> 0)
        End Function

        ''
        ' @brief Read high-resolution CPU Time-Stamp Counter (ticks).
        ' @return 64-bit cycle count since CPU reset.
        ''
        Public Unsafe Function GetTicks() As UInt64
            GetTicks = Call0(SYS_TIME_GET_TICKS)
        End Function

        ''
        ' @brief Query kernel monotonic uptime in milliseconds.
        ''
        Public Unsafe Function GetUptime() As UInt64
            GetUptime = Call0(SYS_TIME_UPTIME)
        End Function

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
            Asm "movq %5, %%r10\n\tsyscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3), "r"(a4) : "rcx", "r11", "r10", "memory"
            Call4 = ret
        End Function

        ''
        ' @brief Invoke x86_64 syscall instruction with 5 arguments.
        ''
        Public Unsafe Function Call5(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64, ByVal a3 As UInt64, ByVal a4 As UInt64, ByVal a5 As UInt64) As UInt64
            Dim ret As UInt64 = 0
            Asm "movq %5, %%r10\n\tmovq %6, %%r8\n\tsyscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3), "r"(a4), "r"(a5) : "rcx", "r11", "r10", "r8", "memory"
            Call5 = ret
        End Function

    End Module

End Namespace
