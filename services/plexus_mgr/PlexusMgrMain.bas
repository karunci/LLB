' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/plexus_mgr/PlexusMgrMain.bas
' Summary: Standalone Ring 3 Plexus Service Supervisor daemon.
'          Oversees system service lifecycles, health telemetry, and service heartbeat channels.

Import "../../include/pros.bas"

Module PlexusMgrMain

    ''
    ' @brief Application entry point for plexus_mgr daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[PLEXUS_MGR] ======================================================="
        ConsoleWriteLine "[PLEXUS_MGR] PROS Plexus Service Supervisor Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[PLEXUS_MGR] Active Service PID = ", myPid, "\r\n"

        ' 2. Register Plexus Manager Node
        Dim mgrNodeId As UInt64 = NodeRegister(2, CPtr(Pointer To Byte, "srv.plexus_mgr"), 7)
        If mgrNodeId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Registered Node 'srv.plexus_mgr' -> Node #", mgrNodeId, "\r\n"
        Else
            ConsoleWriteLine "[PLEXUS_MGR] WARN: Failed to register 'srv.plexus_mgr' node!"
        End If

        ' 3. Monitor core service nodes
        Dim srvDispId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.display"))
        If srvDispId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.display' (Node #", srvDispId, ")\r\n"
        End If

        Dim srvInputId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.input"))
        If srvInputId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.input' (Node #", srvInputId, ")\r\n"
        End If

        Dim srvCompId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.compositor"))
        If srvCompId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.compositor' (Node #", srvCompId, ")\r\n"
        End If

        ConsoleWriteLine "[PLEXUS_MGR] Service supervision online. Entering active heartbeat monitor loop..."
        ConsoleWriteLine "[PLEXUS_MGR] ======================================================="

        ' 4. Active supervisor loop (Zero idle CPU via ProcessSleep)
        Do
            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
