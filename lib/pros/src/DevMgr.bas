' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/DevMgr.bas
' Summary: Client Hardware Device Discovery API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry
Import Pros.String.StringUtil

Namespace Pros.Devices

    Public Const DEV_CMD_GET_TREE As UInt32 = 30
    Public Const DEV_CMD_QUERY    As UInt32 = 31
    Public Const DEV_RESP_OK      As UInt32 = 300
    Public Const DEV_RESP_ERROR   As UInt32 = 301

    <Packed>
    Public Structure DeviceInfo
        Public Id        As UInt32
        Public Kind      As UInt32
        Public Status    As UInt32
        Public Reserved  As UInt32
        Public BaseAddr  As UInt64
    End Structure

    Public Module DeviceClient

        ''
        ' @brief Query status for a named hardware device node via Synaptic IPC.
        ' @param namePtr Null-terminated device identifier.
        ' @param outInfo Output info structure.
        ' @return True if device is online.
        ''
        Public Unsafe Function QueryDevice(ByVal namePtr As Pointer To Byte, ByRef outInfo As DeviceInfo) As Boolean
            If namePtr = 0 Then
                QueryDevice = False
                Exit Function
            End If

            Dim devMgrId As UInt64 = Pros.Nodes.NodeRegistry.Lookup("srv.dev_mgr")
            If devMgrId = 0 Then
                QueryDevice = False
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

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, devMgrId, 7)
            If synChan = 0 Then
                QueryDevice = False
                Exit Function
            End If

            ' Prepare request packet
            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = DEV_CMD_QUERY
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = devMgrId

            Dim pIdx As UInt32 = 0
            While pIdx < 31 And namePtr(pIdx) <> 0
                reqPkt.Payload(pIdx) = namePtr(pIdx)
                pIdx = pIdx + 1
            Wend
            reqPkt.Payload(pIdx) = 0
            reqPkt.PayloadLength = pIdx + 1

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                QueryDevice = False
                Exit Function
            End If

            ' Await response from srv.dev_mgr on client node
            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 10
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    If respPkt.PacketType = DEV_RESP_OK Then
                        Dim pId As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                        Dim pKind As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(4))
                        Dim pStatus As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(8))
                        Dim pReserved As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(12))
                        Dim pBase As Pointer To UInt64 = CPtr(Pointer To UInt64, @respPkt.Payload(16))
                        outInfo.Id = pId(0)
                        outInfo.Kind = pKind(0)
                        outInfo.Status = pStatus(0)
                        outInfo.Reserved = pReserved(0)
                        outInfo.BaseAddr = pBase(0)
                        QueryDevice = True
                        Exit Function
                    Else
                        QueryDevice = False
                        Exit Function
                    End If
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            QueryDevice = False
        End Function

    End Module

End Namespace
