' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Wm.bas
' Summary: Client Window Management API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry

Namespace Pros.Gui

    Public Const WM_CMD_CREATE_WINDOW  As UInt32 = 20
    Public Const WM_CMD_DESTROY_WINDOW As UInt32 = 21
    Public Const WM_CMD_SET_FOCUS      As UInt32 = 22
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

    End Module

End Namespace
