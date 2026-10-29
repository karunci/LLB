' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Vfs.bas
' Summary: Client Virtual File System (VFS) and Storage API.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry
Import Pros.String.StringUtil

Namespace Pros.Storage

    Public Const VFS_KIND_FILE As UInt32 = 1
    Public Const VFS_KIND_DIR  As UInt32 = 2
    Public Const VFS_KIND_DEV  As UInt32 = 3

    Public Const VFS_CMD_LOOKUP As UInt32 = 10
    Public Const VFS_CMD_STAT   As UInt32 = 11
    Public Const VFS_CMD_LIST   As UInt32 = 12
    Public Const VFS_RESP_OK    As UInt32 = 100
    Public Const VFS_RESP_ERROR As UInt32 = 101

    <Packed>
    Public Structure FileStat
        Public SizeBytes As UInt32
        Public Kind      As UInt32
        Public Perms     As UInt32
        Public Status    As UInt32
    End Structure

    Public Module VfsClient

        ''
        ' @brief Query metadata for a file path from the VFS service via Synaptic IPC.
        ' @param pathPtr Null-terminated ASCII path string.
        ' @param outStat Output stat structure populated on success.
        ' @return True if file exists and stat was populated.
        ''
        Public Unsafe Function Stat(ByVal pathPtr As Pointer To Byte, ByRef outStat As FileStat) As Boolean
            If pathPtr = 0 Then
                Stat = False
                Exit Function
            End If

            Dim vfsNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup("srv.vfs")
            If vfsNodeId = 0 Then
                Stat = False
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

            Dim synChan As UInt64 = Pros.Nodes.NodeRegistry.Connect(clientNodeId, vfsNodeId, 7)
            If synChan = 0 Then
                Stat = False
                Exit Function
            End If

            ' Build request packet
            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = 1
            reqPkt.PacketType = VFS_CMD_STAT
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = vfsNodeId

            Dim pIdx As UInt32 = 0
            While pIdx < 31 And pathPtr(pIdx) <> 0
                reqPkt.Payload(pIdx) = pathPtr(pIdx)
                pIdx = pIdx + 1
            Wend
            reqPkt.Payload(pIdx) = 0
            reqPkt.PayloadLength = pIdx + 1

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                Stat = False
                Exit Function
            End If

            ' Await response from srv.vfs on client node
            Dim respPkt As Pros.Nodes.AxonPacket
            Dim tries As UInt32 = 0
            While tries < 10
                If Pros.Nodes.NodeRegistry.Pop(clientNodeId, respPkt) Then
                    If respPkt.PacketType = VFS_RESP_OK Then
                        Dim pKind As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                        Dim pSize As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(4))
                        Dim pPerm As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(8))
                        Dim pStat As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(12))
                        outStat.Kind = pKind(0)
                        outStat.SizeBytes = pSize(0)
                        outStat.Perms = pPerm(0)
                        outStat.Status = pStat(0)
                        Stat = True
                        Exit Function
                    Else
                        Stat = False
                        Exit Function
                    End If
                End If
                Pros.Sys.Process.Sleep 10
                tries = tries + 1
            Wend

            Stat = False
        End Function

    End Module

End Namespace
