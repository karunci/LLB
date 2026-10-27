' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Wm.bas
' Summary: Client Window Management API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry

Namespace Pros.Gui

    Public Const WM_CMD_CREATE_WINDOW  As UInt32 = 31
    Public Const WM_CMD_DESTROY_WINDOW As UInt32 = 32
    Public Const WM_CMD_SET_FOCUS      As UInt32 = 22
    Public Const WM_CMD_WINDOW_DIRTY   As UInt32 = 35
    Public Const WM_RESP_OK            As UInt32 = 200
    Public Const WM_RESP_ERROR         As UInt32 = 201

    Public Module WindowManagerClient

        ''
        ' @brief Request focus change for a specific window via Synaptic IPC.
        ' @param winId Target window identifier.
        ' @return True if focus was granted.
        ''
        Public Unsafe Function RequestFocus(ByVal winId As UInt32) As Boolean
            Dim wmNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.wm"))
            If wmNodeId = 0 Then
                RequestFocus = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(16) As Byte
            clientName(0) = 99  ' 'c'
            clientName(1) = 108 ' 'l'
            clientName(2) = 105 ' 'i'
            clientName(3) = 101 ' 'e'
            clientName(4) = 110 ' 'n'
            clientName(5) = 116 ' 't'
            clientName(6) = 46  ' '.'
            clientName(7) = CType(Byte, 48 + (myPid Mod 10))
            clientName(8) = 0

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
        Public Unsafe Function CreateWindow(ByVal w As Int32, ByVal h As Int32, ByVal shmId As UInt64, ByVal titlePtr As Pointer To Byte) As UInt32
            Dim wmNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.wm"))
            If wmNodeId = 0 Then
                CreateWindow = 0
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(16) As Byte
            clientName(0) = 99  ' 'c'
            clientName(1) = 108 ' 'l'
            clientName(2) = 105 ' 'i'
            clientName(3) = 101 ' 'e'
            clientName(4) = 110 ' 'n'
            clientName(5) = 116 ' 't'
            clientName(6) = 46  ' '.'
            clientName(7) = CType(Byte, 48 + (myPid Mod 10))
            clientName(8) = 0

            Dim clientNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If clientNodeId = 0 Then
                clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If

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
            While t < 31 And titlePtr <> 0 And titlePtr(t) <> 0
                reqPkt.Payload(16 + t) = titlePtr(t)
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
            While tries < 20
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    If respPkt.PacketType = WM_RESP_OK Then
                        Dim pResId As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                        CreateWindow = pResId(0)
                        Exit Function
                    End If
                    Exit While
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            CreateWindow = 0
        End Function

        ''
        ' @brief Request window destruction.
        ' @param winId Target window ID.
        ' @return True on success.
        ''
        Public Unsafe Function DestroyWindow(ByVal winId As UInt32) As Boolean
            Dim wmNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.wm"))
            If wmNodeId = 0 Then
                DestroyWindow = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(16) As Byte
            clientName(0) = 99: clientName(1) = 108: clientName(2) = 105: clientName(3) = 101
            clientName(4) = 110: clientName(5) = 116: clientName(6) = 46
            clientName(7) = CType(Byte, 48 + (myPid Mod 10))
            clientName(8) = 0

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
        ''
        Public Unsafe Function SignalDirty(ByVal winId As UInt32, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32) As Boolean
            Dim compNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.compositor"))
            If compNodeId = 0 Then
                SignalDirty = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(16) As Byte
            clientName(0) = 99: clientName(1) = 108: clientName(2) = 105: clientName(3) = 101
            clientName(4) = 110: clientName(5) = 116: clientName(6) = 46
            clientName(7) = CType(Byte, 48 + (myPid Mod 10))
            clientName(8) = 0

            Dim clientNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If clientNodeId = 0 Then
                clientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, compNodeId, 7)
            If synChan = 0 Then
                SignalDirty = False
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = WM_CMD_WINDOW_DIRTY
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = compNodeId
            Dim pPayload As Pointer To Int32 = CPtr(Pointer To Int32, @reqPkt.Payload(0))
            pPayload(0) = CType(Int32, winId)
            pPayload(1) = rx
            pPayload(2) = ry
            pPayload(3) = rw
            pPayload(4) = rh
            reqPkt.PayloadLength = 20

            SignalDirty = Pros.Nodes.NodeRegistry.Push(synChan, reqPkt)
        End Function

    End Module

End Namespace
