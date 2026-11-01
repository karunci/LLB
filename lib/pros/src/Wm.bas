' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Wm.bas
' Summary: Client Window Management API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry
Import Pros.String.StringUtil

Namespace Pros.Gui

    Public Const WM_CMD_CREATE_WINDOW  As UInt32 = 31
    Public Const WM_CMD_DESTROY_WINDOW As UInt32 = 32
    Public Const WM_CMD_SET_FOCUS      As UInt32 = 22
    Public Const WM_CMD_WINDOW_DIRTY   As UInt32 = 35
    Public Const WM_RESP_OK            As UInt32 = 200
    Public Const WM_RESP_ERROR         As UInt32 = 201

    <Packed>
    Public Structure WindowDescriptor
        Public WinId         As UInt32
        Public OwnerPid      As UInt64
        Public X             As Int32
        Public Y             As Int32
        Public Width         As Int32
        Public Height        As Int32
        Public SurfaceWidth  As Int32
        Public SurfaceHeight As Int32
        Public State         As Int32
        Public Focused       As Boolean
        Public ShmId         As UInt64
        Public ClientVaddr   As UInt64
        Public Title(32)     As Byte
    End Structure

    <Packed>
    Public Structure WindowTable
        Public Revision    As UInt32
        Public Count       As Int32
        Public Windows(16) As WindowDescriptor
    End Structure

    Public Module WindowManagerClient

        ' Cached compositor channel for SignalDirty — resolved once per process lifetime
        Private g_compNodeId  As UInt64 = 0
        Private g_compSynChan As UInt64 = 0
        Private g_clientNodeId As UInt64 = 0
        Private g_pWindowTable As Pointer To WindowTable = 0

        ''
        ' @brief Resolve and cache the compositor synapse channel for dirty-rect signaling.
        '        Called automatically by SignalDirty on first use; safe to call repeatedly.
        ' @return True if channel is ready.
        ''
        Private Unsafe Function EnsureCompChannel() As Boolean
            If g_compSynChan <> 0 Then
                EnsureCompChannel = True
                Exit Function
            End If

            Dim compName(16) As Byte
            Dim cnIdx As UInt32 = 0
            AppendStr "srv.compositor", @compName(0), cnIdx
            compName(cnIdx) = 0

            Dim tries As UInt32 = 0
            While tries < 50 And g_compNodeId = 0
                g_compNodeId = Pros.Nodes.NodeRegistry.Lookup(@compName(0))
                If g_compNodeId = 0 Then
                    Pros.Sys.Process.Sleep 20
                    tries = tries + 1
                End If
            Wend

            If g_compNodeId = 0 Then
                EnsureCompChannel = False
                Exit Function
            End If

            If g_clientNodeId = 0 Then
                Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
                Dim clientName(32) As Byte
                Dim cIdx As UInt32 = 0
                AppendStr "client.", @clientName(0), cIdx
                AppendUInt myPid, @clientName(0), cIdx
                clientName(cIdx) = 0
                g_clientNodeId = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
                If g_clientNodeId = 0 Then
                    g_clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
                End If
            End If

            If g_clientNodeId = 0 Then
                EnsureCompChannel = False
                Exit Function
            End If

            g_compSynChan = Pros.Nodes.NodeRegistry.Connect(g_clientNodeId, g_compNodeId, 7)
            EnsureCompChannel = (g_compSynChan <> 0)
        End Function

        ''
        ' @brief Request focus change for a specific window via Synaptic IPC.
        ' @param winId Target window identifier.
        ' @return True if focus was granted.
        ''
        Public Unsafe Function RequestFocus(ByVal winId As UInt32) As Boolean
            Dim wmNodeId As UInt64 = 0
            Dim lookupTries As UInt32 = 0
            While lookupTries < 50 And wmNodeId = 0
                wmNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.wm")
                If wmNodeId = 0 Then
                    Pros.Sys.Process.Sleep 20
                    lookupTries = lookupTries + 1
                End If
            Wend
            If wmNodeId = 0 Then
                RequestFocus = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(32) As Byte
            Dim cIdx As UInt32 = 0
            AppendStr "client.", @clientName(0), cIdx
            AppendUInt myPid, @clientName(0), cIdx
            clientName(cIdx) = 0

            Dim clientNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If clientNodeId = 0 Then
                clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, wmNodeId, 7)
            If synChan = 0 Then
                RequestFocus = False
                Exit Function
            End If

            ' Prepare request packet
            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = WM_CMD_SET_FOCUS
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = wmNodeId
            Dim pWinId As Pointer To UInt32 = CPtr(Pointer To UInt32, @reqPkt.Payload(0))
            pWinId(0) = winId
            reqPkt.PayloadLength = 4

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                RequestFocus = False
                Exit Function
            End If

            ' Await response from srv.wm on client node
            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 10
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    RequestFocus = (respPkt.PacketType = WM_RESP_OK)
                    Exit Function
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            RequestFocus = False
        End Function

        ''
        ' @brief Request creation of a managed desktop window.
        ' @param w Window width in pixels.
        ' @param h Window height in pixels.
        ' @param shmId Shared memory segment ID holding the client surface.
        ' @param titlePtr Pointer to null-terminated title string.
        ' @return Assigned Window ID, or 0 on error.
        ''
        Public Unsafe Function CreateWindow(ByVal w As Int32, ByVal h As Int32, ByVal shmId As UInt64, ByVal title As String) As UInt32
            Dim wmNodeId As UInt64 = 0
            Dim lookupTries As UInt32 = 0
            While lookupTries < 100 And wmNodeId = 0
                wmNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.wm")
                If wmNodeId = 0 Then
                    Pros.Sys.Process.Sleep 25
                    lookupTries = lookupTries + 1
                End If
            Wend
            If wmNodeId = 0 Then
                CreateWindow = 0
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(32) As Byte
            Dim cIdx As UInt32 = 0
            AppendStr "client.", @clientName(0), cIdx
            AppendUInt myPid, @clientName(0), cIdx
            clientName(cIdx) = 0

            Dim clientNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If clientNodeId = 0 Then
                clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If
            g_clientNodeId = clientNodeId

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, wmNodeId, 7)
            If synChan = 0 Then
                CreateWindow = 0
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = WM_CMD_CREATE_WINDOW
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = wmNodeId

            Dim pW As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(0))
            Dim pH As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(4))
            Dim pShm As Pointer To UInt64 = CPtr(Pointer To UInt64, @reqPkt.Payload(8))
            pW(0) = w
            pH(0) = h
            pShm(0) = shmId

            Dim t As UInt32 = 0
            While t < 31 And title <> 0 And title(t) <> 0
                reqPkt.Payload(16 + t) = title(t)
                t = t + 1
            Wend
            reqPkt.Payload(16 + t) = 0
            reqPkt.PayloadLength = 48

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                CreateWindow = 0
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 100
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    If respPkt.PacketType = WM_RESP_OK Then
                        Dim pResId As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                        Dim pTableShm As Pointer To UInt64 = CPtr(Pointer To UInt64, @respPkt.Payload(8))
                        CreateWindow = pResId(0)
                        If g_pWindowTable = 0 And pTableShm(0) <> 0 Then
                            Dim tableVaddr As UInt64 = &H6A000000
                            If Pros.Sys.RawSyscall.Call2(61, pTableShm(0), tableVaddr) <> 0 Then
                                g_pWindowTable = Pointer To WindowTable(tableVaddr)
                            End If
                        End If
                        Exit Function
                    ElseIf respPkt.PacketType = WM_RESP_ERROR Then
                        CreateWindow = 0
                        Exit Function
                    End If
                End If
                Pros.Sys.Process.Sleep 25
                tries = tries + 1
            Wend

            CreateWindow = 0
        End Function

        ''
        ' @brief Check whether the specified window currently holds input focus.
        ' @param winId Target window identifier.
        ' @return True if window is active / focused.
        ''
        Public Unsafe Function IsFocused(ByVal winId As UInt32) As Boolean
            If g_pWindowTable = 0 Then
                IsFocused = True
                Exit Function
            End If
            Dim i As Int32 = 0
            While i < g_pWindowTable.Count
                If g_pWindowTable.Windows(i).WinId = winId Then
                    IsFocused = g_pWindowTable.Windows(i).Focused
                    Exit Function
                End If
                i = i + 1
            Wend
            IsFocused = False
        End Function

        ''
        ' @brief Request window destruction.
        ' @param winId Target window ID.
        ' @return True on success.
        ''
        Public Unsafe Function DestroyWindow(ByVal winId As UInt32) As Boolean
            Dim wmNodeId As UInt64 = 0
            Dim lookupTries As UInt32 = 0
            While lookupTries < 50 And wmNodeId = 0
                wmNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.wm")
                If wmNodeId = 0 Then
                    Pros.Sys.Process.Sleep 20
                    lookupTries = lookupTries + 1
                End If
            Wend
            If wmNodeId = 0 Then
                DestroyWindow = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(32) As Byte
            Dim cIdx As UInt32 = 0
            AppendStr "client.", @clientName(0), cIdx
            AppendUInt myPid, @clientName(0), cIdx
            clientName(cIdx) = 0

            Dim clientNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If clientNodeId = 0 Then
                clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, wmNodeId, 7)
            If synChan = 0 Then
                DestroyWindow = False
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = WM_CMD_DESTROY_WINDOW
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = wmNodeId
            Dim pWinId As Pointer To UInt32 = CPtr(Pointer To UInt32, @reqPkt.Payload(0))
            pWinId(0) = winId
            reqPkt.PayloadLength = 4

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                DestroyWindow = False
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 10
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    DestroyWindow = (respPkt.PacketType = WM_RESP_OK)
                    Exit Function
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            DestroyWindow = False
        End Function

        ''
        ' @brief Signal dirty client region for compositor blitting.
        '        Uses a cached synapse channel (resolved once per process lifetime) to avoid
        '        per-call Lookup+Connect syscall overhead that caused <10 FPS on bare metal.
        ''
        Public Unsafe Function SignalDirty(ByVal winId As UInt32, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32) As Boolean
            If Not EnsureCompChannel() Then
                SignalDirty = False
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = WM_CMD_WINDOW_DIRTY
            reqPkt.SourceNode = g_clientNodeId
            reqPkt.TargetNode = g_compNodeId
            Dim pPayload As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(0))
            pPayload(0) = Int32(winId)
            pPayload(1) = rx
            pPayload(2) = ry
            pPayload(3) = rw
            pPayload(4) = rh
            reqPkt.PayloadLength = 20

            SignalDirty = Pros.Nodes.NodeRegistry.Push(g_compSynChan, reqPkt)
        End Function

    End Module

End Namespace
