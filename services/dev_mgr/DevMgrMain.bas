' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/dev_mgr/DevMgrMain.bas
' Summary: Standalone Ring 3 Device Manager and Hardware Arbiter Service daemon.
'          Maintains device registry, queries hardware topology, and manages driver nodes.

Import "../../include/pros.bas"

Module DevMgrMain

    ''
    ' @brief Application entry point for dev_mgr daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DEV_MGR] ======================================================="
        ConsoleWriteLine "[DEV_MGR] PROS Device Manager Service Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DEV_MGR] Active Service PID = ", myPid, "\r\n"

        ' 2. Register Device Manager Node in the Neural Node Registry
        Dim devNodeId As UInt64 = NodeRegister(2, CPtr(Pointer To Byte, "srv.dev_mgr"), 7)
        If devNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Registered Node 'srv.dev_mgr' -> Node #", devNodeId, "\r\n"
        Else
            ConsoleWriteLine "[DEV_MGR] WARN: Failed to register 'srv.dev_mgr' node!"
        End If

        ' 3. Discover Core Hardware Driver Nodes
        Dim dispNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.display"))
        If dispNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Display Adapter -> Node #", dispNodeId, "\r\n"
        End If

        Dim inputNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.input"))
        If inputNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Input Controller -> Node #", inputNodeId, "\r\n"
        End If

        Dim rawHwInputId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "hw.input.raw"))
        If rawHwInputId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Raw HID Hardware -> Node #", rawHwInputId, "\r\n"
        End If

        ConsoleWriteLine "[DEV_MGR] Hardware topology discovery completed."
        ConsoleWriteLine "[DEV_MGR] Entering active device arbitration loop..."
        ConsoleWriteLine "[DEV_MGR] ======================================================="

        ' 4. Active daemon event loop (Zero idle CPU via ProcessSleep)
        Do
            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
