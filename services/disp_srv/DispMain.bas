' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: services/disp_srv/DispMain.bas
' Summary: Standalone Ring 3 Display Port Multiplexer daemon (srv.display).
'          Acts as unified port arbiter (Windows dxgkrnl / port driver model),
'          discovering and binding autonomous hardware driver daemons (drv.disp.*),
'          routing discrete damage flushes and cursor events via Synapse IPC.

Import "../../include/pros.bas"

Module DispServiceMain

    Private activeDrvNodeId As UInt64 = 0
    Private drvChan As UInt64 = 0
    Private activeCaps As DriverDispCaps
    Private hasDriver As Boolean = False

    ''
    ' @brief Probe for active display driver daemons on the Neural Bus.
    '        Prefers hardware accelerator (drv.disp.svga), falling back to LFB (drv.disp.lfb).
    ' @param srvNodeId Display port service node identifier.
    ' @return True if a driver was successfully bound.
    ''
    Private Unsafe Function BindActiveDriver(ByVal srvNodeId As UInt64) As Boolean
        activeDrvNodeId = 0
        drvChan = 0
        hasDriver = False

        ' 1. Probe for VMware SVGA-II hardware driver
        Dim svgaId As UInt64 = NodeLookup("drv.disp.svga")
        If svgaId <> 0 Then
            activeDrvNodeId = svgaId
            ConsolePrintWithUInt "[DISP_PORT] Binding Hardware Driver 'drv.disp.svga' -> Node #", svgaId, "\r\n"
        Else
            ' 2. Fallback to generic linear framebuffer driver
            Dim lfbId As UInt64 = NodeLookup("drv.disp.lfb")
            If lfbId <> 0 Then
                activeDrvNodeId = lfbId
                ConsolePrintWithUInt "[DISP_PORT] Binding Fallback Driver 'drv.disp.lfb' -> Node #", lfbId, "\r\n"
            End If
        End If

        If activeDrvNodeId = 0 Then
            BindActiveDriver = False
            Exit Function
        End If

        ' Establish Synapse IPC channel to active driver
        drvChan = SynapseConnect(srvNodeId, activeDrvNodeId, 7)
        If drvChan = 0 Then
            ConsoleWriteLine "[DISP_PORT] ERR: Failed to establish Synapse channel to driver!"
            BindActiveDriver = False
            Exit Function
        End If

        ' Query driver capabilities
        Dim qPkt As AxonPacket
        qPkt.Sequence = 1
        qPkt.PacketType = DRV_DISP_GET_CAPS
        qPkt.SourceNode = srvNodeId
        qPkt.TargetNode = activeDrvNodeId
        qPkt.PayloadLength = 0
        SynapsePush drvChan, qPkt

        Dim respPkt As AxonPacket
        Dim attempts As UInt32 = 0
        While attempts < 50
            If SynapsePop(srvNodeId, respPkt) Then
                If respPkt.PacketType = DRV_DISP_GET_CAPS And respPkt.PayloadLength >= 48 Then
                    Dim pCaps As Pointer To DriverDispCaps = CPtr(Pointer To DriverDispCaps, @respPkt.Payload(0))
                    activeCaps = pCaps(0)
                    ConsolePrintWithUInt "[DISP_PORT] Driver Caps Flags: 0x", UInt64(activeCaps.CapsFlags), "\r\n"
                    ConsoleWrite "[DISP_PORT] Driver Identity: "
                    ConsoleWriteLine CPtr(Pointer To Byte, @activeCaps.DriverName(0))
                    hasDriver = True
                    BindActiveDriver = True
                    Exit Function
                End If
            End If
            ProcessSleep 5
            attempts = attempts + 1
        Wend

        ' If caps query timed out, assume direct LFB as safe baseline
        activeCaps.CapsFlags = DISP_CAP_DIRECT_LFB
        activeCaps.MaxWidth = 1024
        activeCaps.MaxHeight = 768
        activeCaps.PreferredBpp = 32
        hasDriver = True
        BindActiveDriver = True
    End Function

    ''
    ' @brief Main application entry point for PROS Display Port Multiplexer.
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit code (0 for success).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DISP_PORT] ======================================================="
        ConsoleWriteLine "[DISP_PORT] PROS Display Port Multiplexer Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DISP_PORT] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.display' (Kind: Device = 2, Caps: RWN = 7)
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, "srv.display", 7)
        If srvNodeId = 0 Then
            ConsoleWriteLine "[DISP_PORT] ERR: Failed to register 'srv.display' node!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[DISP_PORT] Registered Node 'srv.display' -> Node #", srvNodeId, "\r\n"

        ' 3. Discover and bind active display driver daemon
        ConsoleWriteLine "[DISP_PORT] Probing for active driver daemons on Neural Bus..."
        While Not BindActiveDriver(srvNodeId)
            ProcessSleep 20
        Wend

        ' 4. Active multiplexer event loop
        ConsoleWriteLine "[DISP_PORT] Display Port Multiplexer online. Forwarding client requests..."
        Dim inPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim seq As UInt64 = 0

        Do
            If SynapsePop(srvNodeId, inPkt) Then
                If inPkt.PacketType = DRV_DISP_GET_CAPS Then
                    ' Return cached driver capabilities to requesting client
                    respPkt.Sequence = seq
                    seq = seq + 1
                    respPkt.PacketType = DRV_DISP_GET_CAPS
                    respPkt.SourceNode = srvNodeId
                    respPkt.TargetNode = inPkt.SourceNode
                    respPkt.PayloadLength = 48 ' sizeof(DriverDispCaps)

                    Dim pCapsByte As Pointer To Byte = CPtr(Pointer To Byte, @activeCaps)
                    Dim bi As UInt32 = 0
                    While bi < 48
                        respPkt.Payload(bi) = pCapsByte(bi)
                        bi = bi + 1
                    Wend

                    Dim replyChan As UInt64 = SynapseConnect(srvNodeId, inPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If

                ElseIf inPkt.PacketType = DRV_DISP_FLUSH_RECT Or inPkt.PacketType = DRV_DISP_SET_CURSOR Or inPkt.PacketType = DRV_DISP_SET_MODE Then
                    ' Forward presentation and cursor requests directly to active driver daemon
                    If hasDriver And drvChan <> 0 Then
                        inPkt.TargetNode = activeDrvNodeId
                        SynapsePush drvChan, inPkt
                    End If
                End If
            Else
                ProcessSleep 1
            End If
        Loop

        user_main = 0
    End Function

End Module
