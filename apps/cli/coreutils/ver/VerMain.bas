' Project Name: PROS CoreUtils - ver
' Filename: apps/cli/coreutils/ver/VerMain.bas
' Summary: Standalone Ring 3 system version utility.

Import "../../../../include/pros.bas"
Import "../../../../include/Version.bas"

Module VerMain

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "Personal Research Operating System [PRK-OS / PROS]"
        ConsoleWriteLine "Architecture: x86_64 Long Mode (SMP)"
        ConsoleWriteLine Sys.Version.SYSTEM_VERSION_TAG

        Dim coreCount As UInt64 = GetCoreCount()
        Dim outBuf(64) As Byte
        SprintF @outBuf(0), 64, "SMP Active Cores Online: %u", coreCount
        ConsoleWriteLine @outBuf(0)

        user_main = 0
    End Function

End Module
