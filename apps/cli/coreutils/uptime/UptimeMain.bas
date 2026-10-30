' Project Name: PROS CoreUtils - uptime
' Filename: apps/cli/coreutils/uptime/UptimeMain.bas
' Summary: Standalone Ring 3 system elapsed uptime utility.

Import "../../../../include/pros.bas"

Module UptimeMain

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        Dim uptimeMs As UInt64 = GetUptime()
        Dim totalSec As UInt64 = uptimeMs / 1000
        Dim hours As UInt64 = totalSec / 3600
        Dim remSec As UInt64 = totalSec Mod 3600
        Dim minutes As UInt64 = remSec / 60
        Dim seconds As UInt64 = remSec Mod 60

        Dim outBuf(128) As Byte
        SprintF @outBuf(0), 128, "System Uptime: %u hours, %u minutes, %u seconds (%u ms)", _
                hours, minutes, seconds, uptimeMs
        ConsoleWriteLine @outBuf(0)

        user_main = 0
    End Function

End Module
