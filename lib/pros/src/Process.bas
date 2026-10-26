' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Process.bas
' Summary: High-level Process management procedures for PROS applications.

Import Pros.Sys.RawSyscall

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

    End Module

End Namespace
