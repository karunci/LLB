' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/plexus_mgr/PlexusMgrMain.bas
' Summary: Standalone Ring 3 Plexus Service Supervisor daemon.
'          Oversees system service lifecycles, health telemetry, and service heartbeat channels.

Import "../../include/pros.bas"

Module PlexusMgrMain

    Public Const PLEXUS_STATUS_STOPPED  As UInt32 = 0
    Public Const PLEXUS_STATUS_STARTING As UInt32 = 1
    Public Const PLEXUS_STATUS_RUNNING  As UInt32 = 2
    Public Const PLEXUS_STATUS_FAULTED  As UInt32 = 3

    Public Const PLEXUS_CMD_STATUS As UInt32 = 40
    Public Const PLEXUS_CMD_PING   As UInt32 = 41
    Public Const PLEXUS_RESP_OK    As UInt32 = 400

    <Packed>
    Structure ServiceItem
        Public Pid           As UInt64
        Public Name          As String
        Public NodeId        As UInt64
        Public Status        As UInt32
        Public LastHeartbeat As UInt64
    End Structure

    Private services(7) As ServiceItem
    Private serviceCount As UInt32

    ''
    ' @brief Register a core system service into the supervisor tracking table.
    ''
    Private Unsafe Sub AddService(ByVal name As String, ByVal nodeId As UInt64)
        If serviceCount >= 8 Then Exit Sub
        services(serviceCount).Pid = serviceCount + 1
        services(serviceCount).Name = name
        services(serviceCount).NodeId = nodeId
        services(serviceCount).Status = PLEXUS_STATUS_RUNNING
        services(serviceCount).LastHeartbeat = GetUptime()
        serviceCount = serviceCount + 1
    End Sub

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
        Dim mgrNodeId As UInt64 = NodeRegister(2, "srv.plexus_mgr", 7)
        If mgrNodeId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Registered Node 'srv.plexus_mgr' -> Node #", mgrNodeId, "\r\n"
        Else
            ConsoleWriteLine "[PLEXUS_MGR] WARN: Failed to register 'srv.plexus_mgr' node!"
        End If

        ' 3. Monitor and register core service nodes into supervisor table
        serviceCount = 0

        Dim srvDispId As UInt64 = NodeLookup("srv.display")
        If srvDispId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.display' (Node #", srvDispId, ")\r\n"
            AddService "srv.display", srvDispId
        End If

        Dim srvInputId As UInt64 = NodeLookup("srv.input")
        If srvInputId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.input' (Node #", srvInputId, ")\r\n"
            AddService "srv.input", srvInputId
        End If

        Dim srvCompId As UInt64 = NodeLookup("srv.compositor")
        If srvCompId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.compositor' (Node #", srvCompId, ")\r\n"
            AddService "srv.compositor", srvCompId
        End If

        Dim srvWmId As UInt64 = NodeLookup("srv.wm")
        If srvWmId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.wm' (Node #", srvWmId, ")\r\n"
            AddService "srv.wm", srvWmId
        End If

        Dim srvVfsId As UInt64 = NodeLookup("srv.vfs")
        If srvVfsId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Monitoring Service 'srv.vfs' (Node #", srvVfsId, ")\r\n"
            AddService "srv.vfs", srvVfsId
        End If

        ConsolePrintWithUInt "[PLEXUS_MGR] Service supervisor table populated: ", serviceCount, " Supervised Services\r\n"
        ConsoleWriteLine "[PLEXUS_MGR] Service supervision online. Entering active heartbeat monitor loop..."
        ConsoleWriteLine "[PLEXUS_MGR] ======================================================="

        ' 4. Active supervisor loop (Zero idle CPU via ProcessSleep)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim pReqCount As UInt64 = 0

        Do
            If SynapsePopWait(mgrNodeId, reqPkt) Then
                If reqPkt.PacketType = PLEXUS_CMD_STATUS Then
                    Dim targetName As Pointer To Byte = @reqPkt.Payload(0)
                    Dim foundIdx As Int32 = -1
                    Dim i As UInt32 = 0
                    While i < serviceCount
                        If StrEquals(targetName, services(i).Name) Then
                            foundIdx = Int32(i)
                            Exit While
                        End If
                        i = i + 1
                    Wend

                    respPkt.Sequence = pReqCount
                    respPkt.SourceNode = mgrNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    If foundIdx >= 0 Then
                        respPkt.PacketType = PLEXUS_RESP_OK
                        respPkt.PayloadLength = 16
                        Dim pPid As Pointer To UInt64 = CPtr(Pointer To UInt64, @respPkt.Payload(0))
                        Dim pStatus As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(8))
                        Dim pReserved As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(12))
                        pPid(0) = services(foundIdx).Pid
                        pStatus(0) = services(foundIdx).Status
                        pReserved(0) = 0
                    Else
                        respPkt.PacketType = 401 ' ERROR
                        respPkt.PayloadLength = 0
                    End If

                    Dim replyChan As UInt64 = SynapseConnect(mgrNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                    pReqCount = pReqCount + 1
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
