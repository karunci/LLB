' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Plexus.bas
' Summary: Client Service Supervisor API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry

Namespace Pros.Services

    Public Const PLEXUS_CMD_STATUS As UInt32 = 40
    Public Const PLEXUS_CMD_PING   As UInt32 = 41
    Public Const PLEXUS_RESP_OK    As UInt32 = 400
    Public Const PLEXUS_RESP_ERROR As UInt32 = 401

    Public Module ServiceSupervisorClient

        ''
        ' @brief Verify whether a named system service is active and supervised via Synaptic IPC.
        ' @param serviceName Null-terminated service name.
        ' @return True if service is running and supervised.
        ''
        Public Unsafe Function IsServiceActive(ByVal serviceName As Pointer To Byte) As Boolean
            If serviceName = 0 Then
                IsServiceActive = False
                Exit Function
            End If

            Dim mgrNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.plexus_mgr"))
            If mgrNodeId = 0 Then
                IsServiceActive = False
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

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, mgrNodeId, 7)
            If synChan = 0 Then
                IsServiceActive = False
                Exit Function
            End If

            ' Prepare request packet
            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = PLEXUS_CMD_STATUS

            Dim pIdx As UInt32 = 0
            While pIdx < 31 And serviceName(pIdx) <> 0
                reqPkt.Payload(pIdx) = serviceName(pIdx)
                pIdx = pIdx + 1
            Wend
            reqPkt.Payload(pIdx) = 0
            reqPkt.PayloadLength = pIdx + 1

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                IsServiceActive = False
                Exit Function
            End If

            ' Await response from srv.plexus_mgr on client node
            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 10
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    If respPkt.PacketType = PLEXUS_RESP_OK Then
                        Dim pStatus As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(8))
                        IsServiceActive = (pStatus(0) = 2) ' PLEXUS_STATUS_RUNNING
                        Exit Function
                    Else
                        IsServiceActive = False
                        Exit Function
                    End If
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            IsServiceActive = False
        End Function

    End Module

End Namespace
