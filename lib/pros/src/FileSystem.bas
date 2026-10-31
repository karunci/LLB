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

        Private g_transferShmId  As UInt64 = 0
        Private g_transferVaddr  As UInt64 = &H5C000000
        Private g_clientSeq      As UInt64 = 1
        Private g_fsClientNodeId As UInt64 = 0
        Private g_fsVfsNodeId    As UInt64 = 0
        Private g_fsSynChan      As UInt64 = 0
        Private g_fsReqPkt       As Pros.Nodes.AxonPacket
        Private g_fsRespPkt      As Pros.Nodes.AxonPacket

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
            If g_fsSynChan <> 0 Then
                outClientNodeId = g_fsClientNodeId
                outVfsNodeId = g_fsVfsNodeId
                ConnectToVfs = g_fsSynChan
                Exit Function
            End If

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

            g_fsSynChan = Pros.Nodes.NodeRegistry.Connect(outClientNodeId, outVfsNodeId, 7)
            g_fsClientNodeId = outClientNodeId
            g_fsVfsNodeId = outVfsNodeId
            ConnectToVfs = g_fsSynChan
        End Function

        ''
        ' @brief Bounded synchronous wait for Synapse response packet with sequence validation.
        ' @param clientNodeId Inbound mailbox node ID.
        ' @param expectedSeq Expected transaction sequence number.
        ' @return True if expected response received, False on timeout (500ms).
        ''
        Private Unsafe Function SynapsePopResponse(ByVal clientNodeId As UInt64, ByVal expectedSeq As UInt64) As Boolean
            Dim retries As UInt32 = 0
            While retries < 100 ' Bounded timeout up to 500ms
                While Pros.Nodes.NodeRegistry.Pop(clientNodeId, g_fsRespPkt)
                    If g_fsRespPkt.Sequence = expectedSeq Then
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

            g_fsReqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            g_fsReqPkt.PacketType = VFS_CMD_STAT
            g_fsReqPkt.SourceNode = clientNodeId
            g_fsReqPkt.TargetNode = vfsNodeId
            StrCopy @g_fsReqPkt.Payload(0), 128, path
            g_fsReqPkt.PayloadLength = UInt32(StrLen(path) + 1)

            If Not Pros.Nodes.NodeRegistry.Push(synChan, g_fsReqPkt) Then
                FileExists = False
                Exit Function
            End If

            If SynapsePopResponse(clientNodeId, g_fsReqPkt.Sequence) Then
                If g_fsRespPkt.PacketType = VFS_RESP_OK Then
                    Dim pKind As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(0))
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

            g_fsReqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            g_fsReqPkt.PacketType = VFS_CMD_STAT
            g_fsReqPkt.SourceNode = clientNodeId
            g_fsReqPkt.TargetNode = vfsNodeId
            StrCopy @g_fsReqPkt.Payload(0), 128, path
            g_fsReqPkt.PayloadLength = UInt32(StrLen(path) + 1)

            If Not Pros.Nodes.NodeRegistry.Push(synChan, g_fsReqPkt) Then
                DirectoryExists = False
                Exit Function
            End If

            If SynapsePopResponse(clientNodeId, g_fsReqPkt.Sequence) Then
                If g_fsRespPkt.PacketType = VFS_RESP_OK Then
                    Dim pKind As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(0))
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
                g_fsReqPkt.Sequence = g_clientSeq
                g_clientSeq = g_clientSeq + 1
                g_fsReqPkt.PacketType = VFS_CMD_READ
                g_fsReqPkt.SourceNode = clientNodeId
                g_fsReqPkt.TargetNode = vfsNodeId

                ' Pack Control Plane Request
                Dim pShm As Pointer To UInt64 = Pointer To UInt64(@g_fsReqPkt.Payload(0))
                Dim pOff As Pointer To UInt32 = Pointer To UInt32(@g_fsReqPkt.Payload(8))
                Dim pMax As Pointer To UInt32 = Pointer To UInt32(@g_fsReqPkt.Payload(12))
                pShm(0) = shmId
                pOff(0) = fileOffset
                pMax(0) = 65536
                StrCopy @g_fsReqPkt.Payload(16), 128, path
                g_fsReqPkt.PayloadLength = 16 + UInt32(StrLen(path) + 1)

                If Not Pros.Nodes.NodeRegistry.Push(synChan, g_fsReqPkt) Then Exit While

                If Not SynapsePopResponse(clientNodeId, g_fsReqPkt.Sequence) Then Exit While

                If g_fsRespPkt.PacketType = VFS_RESP_OK Then
                    Dim pReadBytes As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(0))
                    Dim pFlags     As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(8))
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

            g_fsReqPkt.Sequence = g_clientSeq
            g_clientSeq = g_clientSeq + 1
            g_fsReqPkt.PacketType = VFS_CMD_LIST
            g_fsReqPkt.SourceNode = clientNodeId
            g_fsReqPkt.TargetNode = vfsNodeId

            Dim pShm As Pointer To UInt64 = Pointer To UInt64(@g_fsReqPkt.Payload(0))
            Dim pMax As Pointer To UInt32 = Pointer To UInt32(@g_fsReqPkt.Payload(8))
            pShm(0) = shmId
            pMax(0) = 65536

            If dirPath <> 0 Then
                StrCopy @g_fsReqPkt.Payload(12), 128, dirPath
                g_fsReqPkt.PayloadLength = 12 + UInt32(StrLen(dirPath) + 1)
            Else
                g_fsReqPkt.Payload(12) = 0
                g_fsReqPkt.PayloadLength = 13
            End If

            If Not Pros.Nodes.NodeRegistry.Push(synChan, g_fsReqPkt) Then
                DirectoryList = 0
                Exit Function
            End If

            If SynapsePopResponse(clientNodeId, g_fsReqPkt.Sequence) Then
                If g_fsRespPkt.PacketType = VFS_RESP_OK Then
                    Dim pEntries As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(0))
                    Dim pPayloadBytes As Pointer To UInt32 = Pointer To UInt32(@g_fsRespPkt.Payload(4))
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
