' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/wm/WmMain.bas
' Summary: Standalone Ring 3 Window Manager Service daemon.
'          Manages window hierarchies, focus dispatch, window borders, and input routing.

Import "../../include/pros.bas"

Module WmMain

    Public Const WM_CMD_CREATE_WINDOW  As UInt32 = 20
    Public Const WM_CMD_DESTROY_WINDOW As UInt32 = 21
    Public Const WM_CMD_SET_FOCUS      As UInt32 = 22
    Public Const WM_CMD_MOVE_WINDOW    As UInt32 = 23
    Public Const WM_RESP_OK            As UInt32 = 200
    Public Const WM_RESP_ERROR         As UInt32 = 201

    <Packed>
    Structure WindowItem
        Public Id       As UInt32
        Public OwnerPid As UInt64
        Public X        As Int32
        Public Y        As Int32
        Public Width    As Int32
        Public Height   As Int32
        Public Focused  As Boolean
        Public Title    As Pointer To Byte
    End Structure

    Private windows(7) As WindowItem
    Private windowCount As UInt32

    ''
    ' @brief Initialize default system desktop windows.
    ''
    Private Unsafe Sub InitWindows()
        windowCount = 0

        ' Window 1: PROS System Monitor
        windows(0).Id = 1
        windows(0).OwnerPid = 1
        windows(0).X = 60
        windows(0).Y = 60
        windows(0).Width = 480
        windows(0).Height = 280
        windows(0).Focused = True
        windows(0).Title = CPtr(Pointer To Byte, "PROS System Monitor")

        ' Window 2: Desktop Console
        windows(1).Id = 2
        windows(1).OwnerPid = 2
        windows(1).X = 560
        windows(1).Y = 60
        windows(1).Width = 420
        windows(1).Height = 280
        windows(1).Focused = False
        windows(1).Title = CPtr(Pointer To Byte, "PROS Desktop Console")

        windowCount = 2
    End Sub

    ''
    ' @brief Set input focus to the specified window.
    ' @param winId Target window identifier.
    ' @return True if window was found and focused.
    ''
    Public Unsafe Function SetFocus(ByVal winId As UInt32) As Boolean
        Dim i As UInt32 = 0
        Dim found As Boolean = False
        While i < windowCount
            If windows(i).Id = winId Then
                windows(i).Focused = True
                found = True
            Else
                windows(i).Focused = False
            End If
            i = i + 1
        Wend
        SetFocus = found
    End Function

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

        ' 4. Initialize Desktop Window Tree
        InitWindows
        ConsolePrintWithUInt "[WM] Initialized Window Tree: ", CType(UInt64, windowCount), " Managed Windows\r\n"
        ConsoleWriteLine "[WM] Active Focused Window: #1 ('PROS System Monitor')"
        ConsoleWriteLine "[WM] Window arbitration active. Entering event loop..."
        ConsoleWriteLine "[WM] ======================================================="

        ' 5. Active event loop (Zero idle CPU via ProcessSleep)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim wmReqCount As UInt64 = 0

        Do
            ' Service incoming window manager requests from compositor / client applications
            If SynapsePop(wmNodeId, reqPkt) Then
                If reqPkt.PacketType = WM_CMD_SET_FOCUS Then
                    Dim pWinId As Pointer To UInt32 = CPtr(Pointer To UInt32, @reqPkt.Payload(0))
                    Dim ok As Boolean = SetFocus(pWinId(0))
                    respPkt.Sequence = wmReqCount
                    respPkt.SourceNode = wmNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    If ok Then
                        respPkt.PacketType = WM_RESP_OK
                    Else
                        respPkt.PacketType = WM_RESP_ERROR
                    End If
                    respPkt.PayloadLength = 0

                    Dim replyChan As UInt64 = SynapseConnect(wmNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                    wmReqCount = wmReqCount + 1
                End If
            End If

            ProcessSleep 50
        Loop

        user_main = 0
    End Function

End Module
