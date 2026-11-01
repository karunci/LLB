' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Process.bas
' Summary: High-level Process management procedures for PROS applications.

Import "Syscall.bas"
Import Pros.Sys.RawSyscall
Import Pros.Memory.Shmem
Import Pros.IO.FileSystem

Namespace Pros.Sys

    Public Module Process

        ''
        ' @brief Voluntarily yield remaining processor time slice to next runnable thread.
        ''
        Public Unsafe Sub Yield()
            Pros.Sys.RawSyscall.Call0 SYS_PROCESS_YIELD
        End Sub

        ''
        ' @brief Put calling process to sleep for a specified duration in milliseconds.
        ' @param ms Duration in milliseconds.
        ''
        Public Unsafe Sub Sleep(ByVal ms As UInt64)
            Pros.Sys.RawSyscall.Call1 SYS_PROCESS_SLEEP, ms
        End Sub

        ''
        ' @brief Get the unique process identifier (PID) of calling task.
        ' @return Process ID.
        ''
        Public Unsafe Function GetPid() As UInt64
            GetPid = Pros.Sys.RawSyscall.Call0(SYS_PROCESS_GETPID)
        End Function

        ''
        ' @brief Read decoded ASCII key from keyboard ring buffer.
        ' @return Decoded ASCII character byte, or 0 if no key is pending.
        ''
        Public Unsafe Function GetKey() As Byte
            GetKey = Byte(Pros.Sys.RawSyscall.Call0(SYS_GET_KEY))
        End Function

        ''
        ' @brief Terminate calling process and return exit code to microkernel.
        ' @param exitCode Integer status code.
        ''
        Public Unsafe Sub ExitProcess(ByVal exitCode As UInt64)
            Pros.Sys.RawSyscall.Call1 SYS_PROCESS_EXIT, exitCode
            Do
                Asm "pause" : : : "memory"
            Loop
        End Sub

        ''
        ' @brief Get total number of active SMP CPU cores detected by ACPI MADT.
        ' @return Online core count.
        ''
        Public Unsafe Function GetCoreCount() As UInt64
            GetCoreCount = Pros.Sys.RawSyscall.Call0(SYS_SMP_CORE_COUNT)
        End Function

        ''
        ' @brief Get system uptime in milliseconds from kernel timer.
        ' @return Uptime in milliseconds.
        ''
        Public Unsafe Function GetUptime() As UInt64
            GetUptime = Pros.Sys.RawSyscall.Call0(SYS_TIME_UPTIME)
        End Function

        ''
        ' @brief Query the CMOS hardware Real-Time Clock (Year, Month, Day, Hour, Min, Sec).
        ' @param outRtc ByRef variable receiving the live RtcTime data.
        ' @return True on success, False on error.
        ''
        Public Unsafe Function GetRealTime(ByRef outRtc As RtcTime) As Boolean
            GetRealTime = (Pros.Sys.RawSyscall.Call1(SYS_TIME_GET_RTC, UInt64(AddressOf outRtc)) <> 0)
        End Function

        ''
        ' @brief Read high-resolution CPU Time-Stamp Counter (RDTSC).
        ' @return 64-bit cycle count since CPU reset.
        ''
        Public Unsafe Function GetTicks() As UInt64
            GetTicks = Pros.Sys.RawSyscall.Call0(SYS_TIME_GET_TICKS)
        End Function

        ''
        ' @brief Allocate anonymous physical RAM pages and map them into user space.
        ' @param pageCount Number of 4KB pages to allocate.
        ' @param targetVaddr Base virtual address to map to (must be page aligned).
        ' @return Pointer to mapped memory, or 0 on failure.
        ''
        Public Unsafe Function AllocatePages(ByVal pageCount As UInt64, ByVal targetVaddr As UInt64) As Pointer To UInt32
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call2(SYS_MEM_ALLOC_PAGES, pageCount, targetVaddr)
            If res <> 0 Then
                AllocatePages = *UInt32(res)
            Else
                AllocatePages = Nothing
            End If
        End Function

        ''
        ' @brief Query the physical address and byte size of the boot initrd ramdisk.
        ' @param outInfo Pointer to InitrdInfo receiving physical base address and size.
        ' @return True on success, False on error.
        ''
        Public Unsafe Function InitrdGetInfo(ByVal outInfo As Pointer To InitrdInfo) As Boolean
            InitrdGetInfo = (Pros.Sys.RawSyscall.Call1(SYS_INITRD_GET_INFO, UInt64(outInfo)) <> 0)
        End Function

        ''
        ' @brief Map boot initrd ramdisk frames read-only into caller's address space.
        ' @param targetVaddr Base virtual address to map to.
        ' @return True on success, False on error.
        ''
        Public Unsafe Function InitrdMap(ByVal targetVaddr As UInt64) As Boolean
            InitrdMap = (Pros.Sys.RawSyscall.Call1(SYS_INITRD_MAP, targetVaddr) <> 0)
        End Function

        ''
        ' @brief Spawn a new child process from an executable binary (.bax) on the filesystem.
        ' @param path Fully qualified or relative path to the binary image.
        ' @param args Command-line arguments string passed to the child process.
        ' @param inSyn Optional inbound synapse channel ID.
        ' @param outSyn Optional outbound synapse channel ID.
        ' @param errSyn Optional error synapse channel ID.
        ' @return Process ID (>0) on success, or 0 on error.
        ''
        Public Unsafe Function Spawn(ByVal path As String, ByVal args As String, _
                                     Optional ByVal inSyn As UInt64 = 0, _
                                     Optional ByVal outSyn As UInt64 = 0, _
                                     Optional ByVal errSyn As UInt64 = 0) As UInt64
            If path = 0 Then
                Spawn = 0
                Exit Function
            End If

            ' 1. Allocate 64KB Shared Memory transfer window at 0x67000000
            Dim spawnShmVaddr As UInt64 = &H67000000
            Dim shmId As UInt64 = Pros.Memory.Shmem.Create(65536, spawnShmVaddr)
            If shmId = 0 Then
                Spawn = 0
                Exit Function
            End If

            ' 2. Stream binary from VFS into Shared Memory window
            Dim bytesRead As UInt32 = Pros.IO.FileSystem.ReadAllText(path, Pointer To Byte(spawnShmVaddr), 65536)
            If bytesRead = 0 Then
                Pros.Memory.Shmem.Detach shmId
                Spawn = 0
                Exit Function
            End If

            Dim argPtr As UInt64 = 0
            If args <> 0 Then
                argPtr = UInt64(Pointer To Byte(args))
            End If

            ' 3. Invoke microkernel Syscall 10 (SYS_PROCESS_SPAWN)
            ' %rdi=path, %rsi=shmId, %rdx=argc(0), %r10=argv(args), %r8=priority(1)
            Dim childPid As UInt64 = Pros.Sys.RawSyscall.Call5(SYS_PROCESS_SPAWN, _
                                                              UInt64(Pointer To Byte(path)), _
                                                              shmId, _
                                                              0, _
                                                              argPtr, _
                                                              1)

            ' 4. Detach caller's mapping to the shared memory buffer
            Pros.Memory.Shmem.Detach shmId

            Spawn = childPid
        End Function

        ''
        ' @brief Spawn a new child process directly from a Shared Memory buffer containing a BAX image.
        ' @param name Identifier string.
        ' @param shmId Shared memory segment handle containing the binary.
        ' @param args Optional command line arguments.
        ' @return Process ID (>0) on success, or 0 on error.
        ''
        Public Unsafe Function SpawnBax(ByVal name As String, ByVal shmId As UInt64, Optional ByVal args As String = 0) As UInt64
            Dim argPtr As UInt64 = 0
            If args <> 0 Then
                argPtr = UInt64(Pointer To Byte(args))
            End If
            SpawnBax = Pros.Sys.RawSyscall.Call5(SYS_PROCESS_SPAWN, UInt64(Pointer To Byte(name)), shmId, 0, argPtr, 1)
        End Function

        ''
        ' @brief Non-blocking adoption/reaping of any terminated child/zombie process.
        ' @param outExitCode ByRef variable receiving the terminated process exit code.
        ' @return PID of reaped process if reaped, 0 if no zombies pending.
        ''
        Public Unsafe Function ReapZombie(ByRef outExitCode As UInt32) As UInt64
            ReapZombie = Pros.Sys.RawSyscall.Call3(SYS_PROCESS_WAIT, 0, UInt64(@outExitCode), 1)
        End Function

        ''
        ' @brief Synchronously wait for a child process to terminate and retrieve its exit code.
        ' @param pid Target Process ID.
        ' @param outExitCode ByRef variable receiving the child process exit code.
        ' @return True if process exited cleanly, False on invalid PID or error.
        ''
        Public Unsafe Function WaitForExit(ByVal pid As UInt64, ByRef outExitCode As UInt32) As Boolean
            WaitForExit = (Pros.Sys.RawSyscall.Call3(SYS_PROCESS_WAIT, pid, UInt64(@outExitCode), 0) = 0)
        End Function

        ''
        ' @brief Non-blocking poll of a child process exit status.
        ' @param pid Target Process ID.
        ' @param outExitCode ByRef variable receiving the exit code if terminated.
        ' @return 0 if child exited, 1 if still running, -1 on error.
        ''
        Public Unsafe Function PollExit(ByVal pid As UInt64, ByRef outExitCode As UInt32) As Int32
            PollExit = Int32(Pros.Sys.RawSyscall.Call3(SYS_PROCESS_WAIT, pid, UInt64(@outExitCode), 1))
        End Function

        ''
        ' @brief Query comprehensive live system hardware and scheduling metrics.
        ' @param outMetrics ByRef variable receiving the live SystemMetrics data.
        ' @return True on success, False on error.
        ''
        Public Unsafe Function GetSystemMetrics(ByRef outMetrics As SystemMetrics) As Boolean
            GetSystemMetrics = (Pros.Sys.RawSyscall.Call1(SYS_GET_SYSTEM_METRICS, UInt64(AddressOf outMetrics)) <> 0)
        End Function

    End Module

End Namespace
