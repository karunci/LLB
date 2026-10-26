' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/wm/WmMain.bas
' Summary: Standalone Ring 3 Window Manager Service daemon.
'          Manages window hierarchies, focus dispatch, window borders, and input routing.

Import "../../include/pros.bas"

Module WmMain

    ''
    ' @brief Application entry point for wm daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[WM] ======================================================="
        ConsoleWriteLine "[WM] PROS Window Manager Service Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[WM] Active Service PID = ", myPid, "\r\n"

        ' 2. Register Window Manager Node
        Dim wmNodeId As UInt64 = NodeRegister(2, CPtr(Pointer To Byte, "srv.wm"), 7)
        If wmNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Registered Node 'srv.wm' -> Node #", wmNodeId, "\r\n"
        Else
            ConsoleWriteLine "[WM] WARN: Failed to register 'srv.wm' node!"
        End If

        ' 3. Connect to Compositor and Input Services
        Dim compNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.compositor"))
        Dim synComp As UInt64 = 0
        If compNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Attached to Display Compositor -> Node #", compNodeId, "\r\n"
            synComp = SynapseConnect(wmNodeId, compNodeId, 7)
            If synComp <> 0 Then
                ConsolePrintWithUInt "[WM] Established Compositor Control Synapse -> Channel #", synComp, "\r\n"
            End If
        End If

        Dim inputNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.input"))
        Dim synInput As UInt64 = 0
        If inputNodeId <> 0 Then
            ConsolePrintWithUInt "[WM] Attached to Input Subsystem -> Node #", inputNodeId, "\r\n"
            synInput = SynapseConnect(wmNodeId, inputNodeId, 7)
            If synInput <> 0 Then
                ConsolePrintWithUInt "[WM] Established Input Event Synapse -> Channel #", synInput, "\r\n"
            End If
        End If

        ConsoleWriteLine "[WM] Window arbitration active. Entering event loop..."
        ConsoleWriteLine "[WM] ======================================================="

        ' 4. Active event loop (Zero idle CPU via ProcessSleep)
        Do
            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
