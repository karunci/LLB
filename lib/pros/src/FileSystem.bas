' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/FileSystem.bas
' Summary: High-level standard FileSystem client library (Pros.IO.FileSystem).
'          Provides client applications, utilities, and shells with a unified,
'          filesystem-agnostic API over Synaptic IPC.

Import Pros.Sys.RawSyscall
Import Pros.Sys.Process
Import Pros.Nodes.NodeRegistry
Import Pros.String.StringUtil
Import Pros.Memory.Shmem

Namespace Pros.IO

    Public Module FileSystem

        Private Const VFS_CMD_STAT As UInt32 = 11
        Private Const VFS_CMD_LIST As UInt32 = 12
        Private Const VFS_CMD_READ As UInt32 = 13
        Private Const VFS_RESP_OK  As UInt32 = 100

        Private g_transferShmId As UInt64 = 0
        Private g_transferVaddr As UInt64 = &H66000000
        Private g_clientSeq     As UInt64 = 1

        ''
        ' @brief Ensure 64KB Shared Memory transfer buffer is created for Data Plane.
        ''
        Private Unsafe Function EnsureTransferShm() As UInt64
            If g_transferShmId = 0 Then
                g_transferShmId = Pros.Memory.Shmem.Create(65536, g_transferVaddr)
            End If
            EnsureTransferShm = g_transferShmId
        End Function

        ''
        ' @brief Establish a Synapse channel from the calling task to srv.vfs.
        ''
        Private Unsafe Function ConnectToVfs(ByRef outClientNodeId As UInt64, ByRef outVfsNodeId As UInt64) As UInt64
            outVfsNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.vfs")
            If outVfsNodeId = 0 Then
                ConnectToVfs = 0
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim clientName(32) As Byte
            Dim cIdx As UInt32 = 0
            AppendStr "fsclient.", @clientName(0), cIdx
            AppendUInt myPid, @clientName(0), cIdx
            clientName(cIdx) = 0

            outClientNodeId = Pros.Nodes.NodeRegistry.Lookup(@clientName(0))
            If outClientNodeId = 0 Then
                outClientNodeId = Pros.Nodes.NodeRegistry.Register(1, @clientName(0), 7)
            End If

            ConnectToVfs = Pros.Nodes.NodeRegistry.Connect(outClientNodeId, outVfsNodeId, 7)
        End Function

        ''
        ' @brief Bounded synchronous wait for Synapse response packet with sequence validation.
        ' @param clientNodeId Inbound mailbox node ID.
        ' @param expectedSeq Expected transaction sequence number.
        ' @param outPkt AxonPacket receiving the response.
        ' @return True if expected response received, False on timeout (500ms).
        ''
        Private Unsafe Function SynapsePopResponse(ByVal clientNodeId As UInt64, ByVal expectedSeq As UInt64, ByRef outPkt As Pros.Nodes.AxonPacket) As Boolean
            Dim retries As UInt32 = 0
            While retries < 100 ' Bounded timeout up to 500ms
                While Pros.Nodes.NodeRegistry.Pop(clientNodeId, outPkt)
                    If outPkt.Sequence = expectedSeq Then
                        SynapsePopResponse = True
                        Exit Function
                    End If
                    ' Discard stale packets from prior aborted operations
                Wend
                Pros.Sys.Process.Sleep 5
                retries = retries + 1
            Wend
            SynapsePopResponse = False
        End Function

        ''
        ' @brief Checks if a file exists at the specified path.
        ' @param path Path to check.
        ' @return True if file exists and is not a directory.
        ''
        Public Unsafe Function FileExists(ByVal path As String) As Boolean
            If path = 0 Then
                FileExists = False
                Exit Function
            End If

            Dim clientNodeId As UInt64 = 0
            Dim vfsNodeId As UInt64 = 0
            Dim synChan As UInt64 = ConnectToVfs(clientNodeId, vfsNodeId)
            If synChan = 0 Then
                FileExists = False
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            reqPkt.PacketType = VFS_CMD_STAT
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = vfsNodeId
            StrCopy @reqPkt.Payload(0), 128, path
            reqPkt.PayloadLength = UInt32(StrLen(path) + 1)

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                FileExists = False
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            If SynapsePopResponse(clientNodeId, reqPkt.Sequence, respPkt) Then
                If respPkt.PacketType = VFS_RESP_OK Then
                    Dim pKind As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                    FileExists = (pKind(0) = 1) ' 1 = File
                Else
                    FileExists = False
                End If
            Else
                FileExists = False
            End If
        End Function

        ''
        ' @brief Checks if a directory exists at the specified path.
        ' @param path Path to check.
        ' @return True if directory exists.
        ''
        Public Unsafe Function DirectoryExists(ByVal path As String) As Boolean
            If path = 0 Then
                DirectoryExists = False
                Exit Function
            End If

            Dim clientNodeId As UInt64 = 0
            Dim vfsNodeId As UInt64 = 0
            Dim synChan As UInt64 = ConnectToVfs(clientNodeId, vfsNodeId)
            If synChan = 0 Then
                DirectoryExists = False
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            reqPkt.PacketType = VFS_CMD_STAT
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = vfsNodeId
            StrCopy @reqPkt.Payload(0), 128, path
            reqPkt.PayloadLength = UInt32(StrLen(path) + 1)

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                DirectoryExists = False
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            If SynapsePopResponse(clientNodeId, reqPkt.Sequence, respPkt) Then
                If respPkt.PacketType = VFS_RESP_OK Then
                    Dim pKind As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                    DirectoryExists = (pKind(0) = 2) ' 2 = Directory
                Else
                    DirectoryExists = False
                End If
            Else
                DirectoryExists = False
            End If
        End Function

        ''
        ' @brief Reads entire contents of a text file into memory via Data Plane Shared Memory.
        ' @param path Fully qualified or relative path.
        ' @param outBuf Destination buffer.
        ' @param maxLen Maximum byte size.
        ' @return Total bytes read.
        ''
        Public Unsafe Function ReadAllText(ByVal path As String, ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
            If path = 0 Or outBuf = 0 Or maxLen = 0 Then
                ReadAllText = 0
                Exit Function
            End If

            Dim shmId As UInt64 = EnsureTransferShm()
            If shmId = 0 Then
                ReadAllText = 0
                Exit Function
            End If

            Dim clientNodeId As UInt64 = 0
            Dim vfsNodeId As UInt64 = 0
            Dim synChan As UInt64 = ConnectToVfs(clientNodeId, vfsNodeId)
            If synChan = 0 Then
                ReadAllText = 0
                Exit Function
            End If

            Dim totalBytesRead As UInt32 = 0
            Dim fileOffset As UInt32 = 0
            Dim isEof As Boolean = False

            While Not isEof And totalBytesRead < maxLen
                Dim reqPkt As Pros.Nodes.AxonPacket
                reqPkt.Sequence = g_clientSeq
                g_clientSeq = g_clientSeq + 1
                reqPkt.PacketType = VFS_CMD_READ
                reqPkt.SourceNode = clientNodeId
                reqPkt.TargetNode = vfsNodeId

                ' Pack Control Plane Request
                Dim pShm As Pointer To UInt64 = Pointer To UInt64(@reqPkt.Payload(0))
                Dim pOff As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(8))
                Dim pMax As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(12))
                pShm(0) = shmId
                pOff(0) = fileOffset
                pMax(0) = 65536
                StrCopy @reqPkt.Payload(16), 128, path
                reqPkt.PayloadLength = 16 + UInt32(StrLen(path) + 1)

                If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then Exit While

                Dim respPkt As Pros.Nodes.AxonPacket
                If Not SynapsePopResponse(clientNodeId, reqPkt.Sequence, respPkt) Then Exit While

                If respPkt.PacketType = VFS_RESP_OK Then
                    Dim pReadBytes As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                    Dim pFlags     As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(8))
                    Dim bytesInChunk As UInt32 = pReadBytes(0)
                    If (pFlags(0) And 1) <> 0 Or bytesInChunk = 0 Then isEof = True

                    ' Copy from Shared Memory window directly to destination buffer
                    Dim toCopy As UInt32 = bytesInChunk
                    If totalBytesRead + toCopy > maxLen Then toCopy = maxLen - totalBytesRead

                    Dim shmPtr As Pointer To Byte = Pointer To Byte(g_transferVaddr)
                    Dim i As UInt32
                    For i = 0 To toCopy - 1
                        outBuf(totalBytesRead + i) = shmPtr(i)
                    Next i

                    totalBytesRead = totalBytesRead + toCopy
                    fileOffset = fileOffset + bytesInChunk
                    If bytesInChunk = 0 Then Exit While
                Else
                    Exit While
                End If
            Wend

            ReadAllText = totalBytesRead
        End Function

        ''
        ' @brief Lists direct child entries of a directory path via Data Plane Shared Memory.
        ' @param dirPath Fully qualified or relative path.
        ' @param outBuf Buffer receiving null-separated entry names.
        ' @param maxLen Maximum byte size.
        ' @return Number of entries found.
        ''
        Public Unsafe Function DirectoryList(ByVal dirPath As String, ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
            If outBuf = 0 Or maxLen = 0 Then
                DirectoryList = 0
                Exit Function
            End If

            Dim shmId As UInt64 = EnsureTransferShm()
            If shmId = 0 Then
                DirectoryList = 0
                Exit Function
            End If

            Dim clientNodeId As UInt64 = 0
            Dim vfsNodeId As UInt64 = 0
            Dim synChan As UInt64 = ConnectToVfs(clientNodeId, vfsNodeId)
            If synChan = 0 Then
                DirectoryList = 0
                Exit Function
            End If

            Dim reqPkt As Pros.Nodes.AxonPacket
            reqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            reqPkt.PacketType = VFS_CMD_LIST
            reqPkt.SourceNode = clientNodeId
            reqPkt.TargetNode = vfsNodeId

            Dim pShm As Pointer To UInt64 = Pointer To UInt64(@reqPkt.Payload(0))
            Dim pMax As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(8))
            pShm(0) = shmId
            pMax(0) = 65536

            If dirPath <> 0 Then
                StrCopy @reqPkt.Payload(12), 128, dirPath
                reqPkt.PayloadLength = 12 + UInt32(StrLen(dirPath) + 1)
            Else
                reqPkt.Payload(12) = 0
                reqPkt.PayloadLength = 13
            End If

            If Not Pros.Nodes.NodeRegistry.Push(synChan, reqPkt) Then
                DirectoryList = 0
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            If SynapsePopResponse(clientNodeId, reqPkt.Sequence, respPkt) Then
                If respPkt.PacketType = VFS_RESP_OK Then
                    Dim pEntries As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                    Dim pPayloadBytes As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(4))
                    Dim count As UInt32 = pEntries(0)
                    Dim bytesInShm As UInt32 = pPayloadBytes(0)

                    Dim toCopy As UInt32 = bytesInShm
                    If toCopy > maxLen Then toCopy = maxLen

                    Dim shmPtr As Pointer To Byte = Pointer To Byte(g_transferVaddr)
                    Dim i As UInt32
                    For i = 0 To toCopy - 1
                        outBuf(i) = shmPtr(i)
                    Next i
                    If toCopy < maxLen Then outBuf(toCopy) = 0
                    DirectoryList = count
                Else
                    DirectoryList = 0
                End If
            Else
                DirectoryList = 0
            End If
        End Function

    End Module

End Namespace
