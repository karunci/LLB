' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/ramfs_srv/RamfsMain.bas
' Summary: Autonomous Ring 3 Ramdisk Filesystem Plexus Service (fs.ramfs).
'          Provides dynamic in-memory writable files and directories for PROS userspace.

Import "../../include/pros.bas"

Module RamfsMain

    Public Const RAMFS_KIND_FILE As UInt32 = 1
    Public Const RAMFS_KIND_DIR  As UInt32 = 2

    Public Const FS_CMD_MOUNT    As UInt32 = 1
    Public Const FS_CMD_LOOKUP   As UInt32 = 10
    Public Const FS_CMD_STAT     As UInt32 = 11
    Public Const FS_CMD_LIST     As UInt32 = 12
    Public Const FS_CMD_READ     As UInt32 = 13
    Public Const FS_CMD_WRITE    As UInt32 = 14
    Public Const FS_CMD_CREATE   As UInt32 = 15
    Public Const FS_CMD_DELETE   As UInt32 = 16

    Public Const FS_RESP_OK      As UInt32 = 100
    Public Const FS_RESP_ERROR   As UInt32 = 101

    Private Const MAX_RAM_INODES As UInt32 = 64
    Private Const RAMFS_POOL_BASE As UInt64 = &H5A000000
    Private Const RAMFS_POOL_PAGES As UInt64 = 2048 ' 8 MB (2048 * 4KB)

    <Packed>
    Structure RamInode
        Public InodeId       As UInt32
        Public Kind          As UInt32    ' 1 = File, 2 = Directory
        Public SizeBytes     As UInt32
        Public CapacityBytes As UInt32
        Public DataPtr       As Pointer To Byte
        Public Path(128)     As Byte      ' Relative path e.g. "Default\Desktop"
        Public PathLen       As UInt32
        Public InUse         As Boolean
    End Structure

    Private inodes(64)   As RamInode
    Private inodeCount   As UInt32
    Private nextDataOff  As UInt32
    Private poolBasePtr  As Pointer To Byte

    ''
    ' @brief Normalize relative path for RamFS.
    ''
    Private Unsafe Function NormalizeRelative(ByVal src As Pointer To Byte, ByVal dst As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
        If src = 0 Or dst = 0 Or maxLen = 0 Then
            NormalizeRelative = 0
            Exit Function
        End If

        Dim rIdx As UInt32 = 0
        While src(rIdx) = 47 Or src(rIdx) = 92 ' Skip leading slashes
            rIdx = rIdx + 1
        Wend

        Dim wIdx As UInt32 = 0
        While src(rIdx) <> 0 And wIdx + 1 < maxLen
            Dim c As Byte = src(rIdx)
            If c = 47 Then c = 92
            dst(wIdx) = c
            wIdx = wIdx + 1
            rIdx = rIdx + 1
        Wend

        If wIdx > 0 And dst(wIdx - 1) = 92 Then
            wIdx = wIdx - 1
        End If

        dst(wIdx) = 0
        NormalizeRelative = wIdx
    End Function

    ''
    ' @brief Initialize RamFS memory pool and default directory hierarchy.
    ''
    Private Unsafe Sub InitRamFs()
        inodeCount = 0
        nextDataOff = 0
        poolBasePtr = Pointer To Byte(RAMFS_POOL_BASE)

        ' Map 8 MB userland buffer at 0x5A000000
        Dim allocRes As Pointer To UInt32 = AllocatePages(RAMFS_POOL_PAGES, RAMFS_POOL_BASE)
        If allocRes = Nothing Then
            ConsoleWriteLine "[RAMFS] WARN: AllocatePages failed, using identity buffer"
        Else
            ConsoleWriteLine "[RAMFS] Allocated 8 MB in-memory pool at 0x5A000000"
        End If

        ' Inode 0: Root of RamFS mount ("" / representing /Users)
        inodes(0).InodeId = 0
        inodes(0).Kind = RAMFS_KIND_DIR
        inodes(0).SizeBytes = 0
        inodes(0).CapacityBytes = 0
        inodes(0).DataPtr = poolBasePtr
        inodes(0).Path(0) = 0
        inodes(0).PathLen = 0
        inodes(0).InUse = True
        inodeCount = 1

        ' Create default user workspace directories: "Default", "Default\Desktop", "Default\Documents"
        CreateDirectory "Default"
        CreateDirectory "Default\Desktop"
        CreateDirectory "Default\Documents"
    End Sub

    ''
    ' @brief Look up an inode by relative path.
    ''
    Private Unsafe Function LookupInode(ByVal path As String) As Int32
        Dim norm(128) As Byte
        Dim nLen As UInt32 = NormalizeRelative(Pointer To Byte(path), @norm(0), 128)

        If nLen = 0 Then
            LookupInode = 0
            Exit Function
        End If

        Dim i As UInt32
        For i = 0 To inodeCount - 1
            Dim node As Pointer To RamInode = @inodes(i)
            If node.InUse And node.PathLen = nLen Then
                If StrEquals(@node.Path(0), @norm(0)) Then
                    LookupInode = Int32(i)
                    Exit Function
                End If
            End If
        Next i

        LookupInode = -1
    End Function

    ''
    ' @brief Create a new directory in RamFS.
    ''
    Public Unsafe Function CreateDirectory(ByVal path As String) As Int32
        If inodeCount >= MAX_RAM_INODES Or path = 0 Then
            CreateDirectory = -1
            Exit Function
        End If

        Dim existing As Int32 = LookupInode(path)
        If existing >= 0 Then
            CreateDirectory = existing
            Exit Function
        End If

        Dim newIdx As UInt32 = inodeCount
        Dim node As Pointer To RamInode = @inodes(newIdx)
        node.InodeId = newIdx
        node.Kind = RAMFS_KIND_DIR
        node.SizeBytes = 0
        node.CapacityBytes = 0
        node.DataPtr = poolBasePtr
        node.PathLen = NormalizeRelative(Pointer To Byte(path), @node.Path(0), 128)
        node.InUse = True

        inodeCount = inodeCount + 1
        CreateDirectory = Int32(newIdx)
    End Function

    ''
    ' @brief Create a new file in RamFS.
    ''
    Public Unsafe Function CreateFile(ByVal path As String, ByVal initialCapacity As UInt32) As Int32
        If inodeCount >= MAX_RAM_INODES Or path = 0 Then
            CreateFile = -1
            Exit Function
        End If

        Dim existing As Int32 = LookupInode(path)
        If existing >= 0 Then
            CreateFile = existing
            Exit Function
        End If

        Dim cap As UInt32 = initialCapacity
        If cap < 4096 Then cap = 4096 ' Default 4KB block

        Dim newIdx As UInt32 = inodeCount
        Dim node As Pointer To RamInode = @inodes(newIdx)
        node.InodeId = newIdx
        node.Kind = RAMFS_KIND_FILE
        node.SizeBytes = 0
        node.CapacityBytes = cap
        node.DataPtr = poolBasePtr + nextDataOff
        node.PathLen = NormalizeRelative(Pointer To Byte(path), @node.Path(0), 128)
        node.InUse = True

        nextDataOff = nextDataOff + cap
        inodeCount = inodeCount + 1
        CreateFile = Int32(newIdx)
    End Function

    ''
    ' @brief Write byte data to a RamFS file inode.
    ''
    Public Unsafe Function WriteFile(ByVal inodeIdx As Int32, ByVal offset As UInt32, ByVal inBuf As Pointer To Byte, ByVal count As UInt32) As UInt32
        If inodeIdx < 0 Or UInt32(inodeIdx) >= inodeCount Or inBuf = 0 Or count = 0 Then
            WriteFile = 0
            Exit Function
        End If

        Dim node As Pointer To RamInode = @inodes(inodeIdx)
        If node.Kind <> RAMFS_KIND_FILE Then
            WriteFile = 0
            Exit Function
        End If

        Dim writeEnd As UInt32 = offset + count
        If writeEnd > node.CapacityBytes Then
            count = node.CapacityBytes - offset
        End If

        Dim dst As Pointer To Byte = node.DataPtr + offset
        Dim i As UInt32
        For i = 0 To count - 1
            dst(i) = inBuf(i)
        Next i

        If writeEnd > node.SizeBytes Then
            node.SizeBytes = writeEnd
        End If

        WriteFile = count
    End Function

    ''
    ' @brief Read byte data from a RamFS file inode.
    ''
    Public Unsafe Function ReadFile(ByVal inodeIdx As Int32, ByVal offset As UInt32, ByVal outBuf As Pointer To Byte, ByVal count As UInt32) As UInt32
        If inodeIdx < 0 Or UInt32(inodeIdx) >= inodeCount Or outBuf = 0 Or count = 0 Then
            ReadFile = 0
            Exit Function
        End If

        Dim node As Pointer To RamInode = @inodes(inodeIdx)
        If node.Kind <> RAMFS_KIND_FILE Or offset >= node.SizeBytes Then
            ReadFile = 0
            Exit Function
        End If

        Dim avail As UInt32 = node.SizeBytes - offset
        Dim toRead As UInt32 = count
        If toRead > avail Then toRead = avail

        Dim src As Pointer To Byte = node.DataPtr + offset
        Dim i As UInt32
        For i = 0 To toRead - 1
            outBuf(i) = src(i)
        Next i

        ReadFile = toRead
    End Function

    ''
    ' @brief List direct child entries of a directory in RamFS.
    ''
    Public Unsafe Function ListRamDirectory(ByVal dirPath As String, ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
        If outBuf = 0 Or maxLen = 0 Then
            ListRamDirectory = 0
            Exit Function
        End If

        Dim normDir(128) As Byte
        Dim dirLen As UInt32 = 0
        If dirPath <> 0 Then
            dirLen = NormalizeRelative(Pointer To Byte(dirPath), @normDir(0), 128)
        End If

        Dim foundCount As UInt32 = 0
        Dim wIdx As UInt32 = 0

        Dim i As UInt32
        For i = 1 To inodeCount - 1
            Dim node As Pointer To RamInode = @inodes(i)
            If node.InUse Then
                Dim isMatched As Boolean = False
                Dim childStart As UInt32 = 0

                If dirLen = 0 Then
                    ' Root of mount
                    Dim hasSlash As Boolean = False
                    Dim j As UInt32 = 0
                    While node.Path(j) <> 0
                        If node.Path(j) = 92 Then hasSlash = True
                        j = j + 1
                    Wend
                    If Not hasSlash Then
                        isMatched = True
                        childStart = 0
                    End If
                Else
                    If node.PathLen > dirLen And node.Path(dirLen) = 92 Then
                        If StrStartsWith(@node.Path(0), @normDir(0)) Then
                            Dim k As UInt32 = dirLen + 1
                            Dim hasSubSlash As Boolean = False
                            While node.Path(k) <> 0
                                If node.Path(k) = 92 Then hasSubSlash = True
                                k = k + 1
                            Wend
                            If Not hasSubSlash Then
                                isMatched = True
                                childStart = dirLen + 1
                            End If
                        End If
                    End If
                End If

                If isMatched Then
                    Dim cIdx As UInt32 = childStart
                    While node.Path(cIdx) <> 0 And wIdx + 2 < maxLen
                        outBuf(wIdx) = node.Path(cIdx)
                        wIdx = wIdx + 1
                        cIdx = cIdx + 1
                    Wend
                    outBuf(wIdx) = 0
                    wIdx = wIdx + 1
                    foundCount = foundCount + 1
                End If
            End If
        Next

        If wIdx < maxLen Then outBuf(wIdx) = 0
        ListRamDirectory = foundCount
    End Function

    ''
    ' @brief Main entry point for standalone Ring 3 RamFS Plexus Service.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[RAMFS] ======================================================="
        ConsoleWriteLine "[RAMFS] PROS Ramdisk Filesystem Plexus Service (fs.ramfs) Online"

        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[RAMFS] Active Service PID = ", myPid, "\r\n"

        ' Register node in registry
        Dim ramfsNodeId As UInt64 = NodeRegister(3, "fs.ramfs", 7)
        If ramfsNodeId <> 0 Then
            ConsolePrintWithUInt "[RAMFS] Registered Node 'fs.ramfs' -> Node #", ramfsNodeId, "\r\n"
        Else
            ConsoleWriteLine "[RAMFS] WARN: Failed to register 'fs.ramfs' node!"
        End If

        ' Initialize memory pool and root tree
        InitRamFs
        ConsolePrintWithUInt "[RAMFS] Initialized Inode Table (", inodeCount, " nodes online)\r\n"

        ' Connect to srv.vfs and send Mount handshake claiming "/Users"
        Dim vfsNodeId As UInt64 = NodeLookup("srv.vfs")
        If vfsNodeId <> 0 Then
            Dim synVfs As UInt64 = SynapseConnect(ramfsNodeId, vfsNodeId, 7)
            If synVfs <> 0 Then
                Dim mountPkt As AxonPacket
                mountPkt.Sequence = 1
                mountPkt.PacketType = FS_CMD_MOUNT
                mountPkt.SourceNode = ramfsNodeId
                mountPkt.TargetNode = vfsNodeId

                ' Payload: mount point "/Users"
                StrCopy Pointer To Byte(@mountPkt.Payload(0)), 32, "/Users"
                mountPkt.PayloadLength = 7

                SynapsePush synVfs, mountPkt
                ConsoleWriteLine "[RAMFS] Dispatched FS_CMD_MOUNT ('/Users') to srv.vfs"
            End If
        End If

        ConsoleWriteLine "[RAMFS] Entering request service loop..."
        ConsoleWriteLine "[RAMFS] ======================================================="

        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim reqSeq As UInt64 = 0

        Do
            If SynapsePopWait(ramfsNodeId, reqPkt) Then
                respPkt.Sequence = reqPkt.Sequence
                respPkt.SourceNode = ramfsNodeId
                respPkt.TargetNode = reqPkt.SourceNode
                reqSeq = reqSeq + 1

                Select Case reqPkt.PacketType
                    Case FS_CMD_LOOKUP, FS_CMD_STAT
                        Dim inIdx As Int32 = LookupInode(@reqPkt.Payload(0))
                        If inIdx >= 0 Then
                            respPkt.PacketType = FS_RESP_OK
                            respPkt.PayloadLength = 16
                            Dim pKind As Pointer To UInt32 = *UInt32(@respPkt.Payload(0))
                            Dim pSize As Pointer To UInt32 = *UInt32(@respPkt.Payload(4))
                            Dim pPerm As Pointer To UInt32 = *UInt32(@respPkt.Payload(8))
                            Dim pStat As Pointer To UInt32 = *UInt32(@respPkt.Payload(12))
                            pKind(0) = inodes(inIdx).Kind
                            pSize(0) = inodes(inIdx).SizeBytes
                            pPerm(0) = &H0777
                            pStat(0) = 1
                        Else
                            respPkt.PacketType = FS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case FS_CMD_READ
                        Dim rIdx As Int32 = LookupInode(@reqPkt.Payload(0))
                        If rIdx >= 0 Then
                            Dim rCount As UInt32 = ReadFile(rIdx, 0, Pointer To Byte(@respPkt.Payload(4)), 48)
                            respPkt.PacketType = FS_RESP_OK
                            Dim pBytes As Pointer To UInt32 = *UInt32(@respPkt.Payload(0))
                            pBytes(0) = rCount
                            respPkt.PayloadLength = 4 + rCount
                        Else
                            respPkt.PacketType = FS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case FS_CMD_CREATE
                        Dim createdIdx As Int32 = CreateFile(@reqPkt.Payload(0), 4096)
                        If createdIdx >= 0 Then
                            respPkt.PacketType = FS_RESP_OK
                            respPkt.PayloadLength = 4
                            Dim pId As Pointer To UInt32 = *UInt32(@respPkt.Payload(0))
                            pId(0) = UInt32(createdIdx)
                        Else
                            respPkt.PacketType = FS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case Else
                        respPkt.PacketType = FS_RESP_ERROR
                        respPkt.PayloadLength = 0
                End Select

                Dim replySyn As UInt64 = SynapseConnect(ramfsNodeId, reqPkt.SourceNode, 7)
                If replySyn <> 0 Then
                    SynapsePush replySyn, respPkt
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
