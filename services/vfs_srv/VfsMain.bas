' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/vfs_srv/VfsMain.bas
' Summary: Standalone Ring 3 Storage and Virtual File System (VFS) daemon.
'          Provides hybrid mount tree hierarchy, internal TarFS root initrd driver,
'          dynamic Plexus mount registration, and Synapse IPC request servicing.

Import "../../include/pros.bas"
Use Storage.TarFS.TarFsDriver As TarFS

Module VfsMain

    Public Const VFS_KIND_FILE As UInt32 = 1
    Public Const VFS_KIND_DIR  As UInt32 = 2
    Public Const VFS_KIND_DEV  As UInt32 = 3

    Public Const FS_CMD_MOUNT   As UInt32 = 1
    Public Const VFS_CMD_LOOKUP As UInt32 = 10
    Public Const VFS_CMD_STAT   As UInt32 = 11
    Public Const VFS_CMD_LIST   As UInt32 = 12
    Public Const VFS_CMD_READ   As UInt32 = 13
    Public Const VFS_CMD_WRITE  As UInt32 = 14
    Public Const VFS_RESP_OK    As UInt32 = 100
    Public Const VFS_RESP_ERROR As UInt32 = 101

    Private Const MAX_MOUNTS As UInt32 = 16
    Private Const DRIVER_TARFS  As UInt32 = 1
    Private Const DRIVER_PLEXUS As UInt32 = 2

    <Packed>
    Structure MountEntry
        Public MountPoint(64) As Byte   ' e.g. "X:\" or "X:\Users"
        Public MountLen       As UInt32
        Public DriverKind     As UInt32 ' 1 = Internal TarFS, 2 = External Plexus
        Public PlexusNodeId   As UInt64
        Public InUse          As Boolean
    End Structure

    Private mountTable(16) As MountEntry
    Private mountCount     As UInt32

    Private Const MAX_SHM_SLOTS   As UInt32 = 16
    Private Const SHM_ARENA_BASE  As UInt64 = &H66000000
    Private Const SHM_SLOT_STRIDE As UInt64 = &H00100000

    <Packed>
    Structure ClientShmSlot
        Public ClientNodeId As UInt64
        Public ClientShmId  As UInt64
        Public VfsVaddr     As UInt64
        Public InUse        As Boolean
    End Structure

    Private shmSlots(16) As ClientShmSlot

    ''
    ' @brief Normalize path string supporting Windows X:\ and C:\ drive notation and backslashes.
    '        Resolves relative paths, collapses duplicate slashes, and formats canonical path with '\'.
    ' @param inPath Input path string pointer.
    ' @param outBuf Output normalized buffer (at least 128 bytes).
    ''
    Public Unsafe Sub NormalizePath(ByVal inPath As Pointer To Byte, ByVal outBuf As Pointer To Byte)
        If inPath = 0 Or outBuf = 0 Then Exit Sub

        Dim rIdx As UInt32 = 0
        Dim wIdx As UInt32 = 0

        ' Skip leading whitespace
        While inPath(rIdx) = 32
            rIdx = rIdx + 1
        Wend

        ' Detect and normalize drive letter (e.g., "X:" or "C:", default to "X:")
        Dim driveLetter As Byte = 88 ' Default 'X'
        If inPath(rIdx) <> 0 And inPath(rIdx + 1) = 58 Then ' ':'
            Dim dl As Byte = inPath(rIdx)
            If dl >= 97 And dl <= 122 Then dl = dl - 32 ' Uppercase
            driveLetter = dl
            rIdx = rIdx + 2
        End If

        ' Write drive prefix: e.g. "X:\"
        outBuf(0) = driveLetter
        outBuf(1) = 58 ' ':'
        outBuf(2) = 92 ' '\'
        wIdx = 3

        ' Skip leading slashes in path body
        While inPath(rIdx) = 47 Or inPath(rIdx) = 92
            rIdx = rIdx + 1
        Wend

        While inPath(rIdx) <> 0 And wIdx < 120
            Dim c As Byte = inPath(rIdx)
            ' Standardize forward slash '/' (47) to backslash '\' (92)
            If c = 47 Then c = 92

            ' Collapse duplicate backslashes
            If c = 92 And wIdx > 3 And outBuf(wIdx - 1) = 92 Then
                ' Skip duplicate
            Else
                outBuf(wIdx) = c
                wIdx = wIdx + 1
            End If
            rIdx = rIdx + 1
        Wend

        ' Strip trailing backslash if path is longer than "X:\"
        If wIdx > 3 And outBuf(wIdx - 1) = 92 Then
            wIdx = wIdx - 1
        End If

        outBuf(wIdx) = 0
    End Sub

    ''
    ' @brief Mount and populate default mount table with internal TarFS at root.
    ''
    Private Unsafe Sub InitMountTree()
        mountCount = 0

        ' 1. Mount Entry 0: Root "X:\" claimed by internal TarFS driver
        Dim rootM As Pointer To MountEntry = @mountTable(0)
        StrCopy @rootM.MountPoint(0), 64, "X:\\"
        rootM.MountLen = 3
        rootM.DriverKind = DRIVER_TARFS
        rootM.PlexusNodeId = 0
        rootM.InUse = True
        mountCount = 1

        ' 2. Discover and map boot initrd via microkernel syscalls
        Dim info As InitrdInfo
        If InitrdGetInfo(@info) Then
            ConsolePrintWithUInt "[VFS] Initrd physical base: 0x", info.PhysAddr, ""
            ConsolePrintWithUInt ", size: ", info.SizeBytes, " bytes\r\n"

            If InitrdMap(&H58000000) Then
                ConsoleWriteLine "[VFS] Mapped initrd to userland 0x58000000 successfully"
                If TarFS.Mount(&H58000000, info.SizeBytes) Then
                    ConsolePrintWithUInt "[VFS] TarFS mounted root 'X:\\' (", UInt64(TarFS.GetEntryCount()), " files indexed)\r\n"
                Else
                    ConsoleWriteLine "[VFS] WARN: TarFS failed to parse USTAR archive"
                End If
            Else
                ConsoleWriteLine "[VFS] WARN: InitrdMap failed to map virtual pages"
            End If
        Else
            ConsoleWriteLine "[VFS] WARN: InitrdGetInfo syscall failed"
        End If
    End Sub

    ''
    ' @brief Register a dynamic mount point claimed by an external filesystem Plexus.
    ''
    Public Unsafe Function RegisterMount(ByVal mountPath As String, ByVal plexusNodeId As UInt64) As Boolean
        If mountCount >= MAX_MOUNTS Or mountPath = 0 Then
            RegisterMount = False
            Exit Function
        End If

        Dim norm(64) As Byte
        NormalizePath Pointer To Byte(mountPath), @norm(0)

        Dim newIdx As UInt32 = mountCount
        Dim m As Pointer To MountEntry = @mountTable(newIdx)
        StrCopy @m.MountPoint(0), 64, @norm(0)
        m.MountLen = UInt32(StrLen(@norm(0)))
        m.DriverKind = DRIVER_PLEXUS
        m.PlexusNodeId = plexusNodeId
        m.InUse = True

        mountCount = mountCount + 1
        ConsolePrintWithUInt "[VFS] Registered dynamic mount point: ", newIdx, ""
        ConsolePrintWithUInt " -> Plexus Node #", plexusNodeId, "\r\n"
        RegisterMount = True
    End Function

    ''
    ' @brief Resolve a normalized path against the Mount Table using longest prefix match.
    ' @param normPath Input normalized path (e.g. "X:\Users\Default" or "X:\Apps\Terminal").
    ' @param outRelPath Buffer receiving the relative path for the target driver.
    ' @return Index into mountTable, or -1 if no mount matched.
    ''
    Private Unsafe Function ResolveMount(ByVal normPath As Pointer To Byte, ByVal outRelPath As Pointer To Byte) As Int32
        If normPath = 0 Or outRelPath = 0 Then
            ResolveMount = -1
            Exit Function
        End If

        Dim bestIdx As Int32 = -1
        Dim bestLen As UInt32 = 0

        Dim i As UInt32
        For i = 0 To MAX_MOUNTS - 1
            Dim m As Pointer To MountEntry = @mountTable(i)
            If m.InUse Then
                If StrStartsWith(normPath, @m.MountPoint(0)) Then
                    Dim mLen As UInt32 = m.MountLen
                    Dim nextChar As Byte = normPath(mLen)

                    ' Boundary verification: exact match, followed by '\', or root "X:\"
                    If nextChar = 0 Or nextChar = 92 Or StrEquals(@m.MountPoint(0), "X:\\") Then
                        If mLen >= bestLen Then
                            bestLen = mLen
                            bestIdx = Int32(i)
                        End If
                    End If
                End If
            End If
        Next

        If bestIdx >= 0 Then
            Dim rIdx As UInt32 = bestLen
            While normPath(rIdx) = 92 Or normPath(rIdx) = 47
                rIdx = rIdx + 1
            Wend
            Dim wIdx As UInt32 = 0
            While normPath(rIdx) <> 0 And wIdx + 1 < 128
                outRelPath(wIdx) = normPath(rIdx)
                wIdx = wIdx + 1
                rIdx = rIdx + 1
            Wend
            outRelPath(wIdx) = 0
        End If

        ResolveMount = bestIdx
    End Function

    ''
    ' @brief Attach or retrieve cached virtual address for a client's Shared Memory Data Plane.
    ' @param clientNodeId Requesting client node identifier.
    ' @param clientShmId Client shared memory handle.
    ' @return Mapped virtual address in VFS address space, or 0 on failure.
    ''
    Private Unsafe Function AttachClientShm(ByVal clientNodeId As UInt64, ByVal clientShmId As UInt64) As UInt64
        If clientShmId = 0 Then
            AttachClientShm = 0
            Exit Function
        End If

        Dim i As UInt32
        For i = 0 To MAX_SHM_SLOTS - 1
            Dim s As Pointer To ClientShmSlot = @shmSlots(i)
            If s.InUse And s.ClientNodeId = clientNodeId And s.ClientShmId = clientShmId Then
                AttachClientShm = s.VfsVaddr
                Exit Function
            End If
        Next i

        Dim targetSlot As Int32 = -1
        Dim j As UInt32 = 0
        While j < MAX_SHM_SLOTS And targetSlot < 0
            Dim sFree As Pointer To ClientShmSlot = @shmSlots(j)
            If Not sFree.InUse Then
                targetSlot = Int32(j)
            End If
            j = j + 1
        Wend

        If targetSlot < 0 Then
            targetSlot = 0
            Dim sOld As Pointer To ClientShmSlot = @shmSlots(0)
            If sOld.InUse And sOld.ClientShmId <> 0 Then
                ShmemDetach sOld.ClientShmId
                sOld.InUse = False
            End If
        End If

        Dim slotIdx As UInt32 = UInt32(targetSlot)
        Dim slotVaddr As UInt64 = SHM_ARENA_BASE + (UInt64(slotIdx) * SHM_SLOT_STRIDE)
        Dim attachedAddr As UInt64 = ShmemAttach(clientShmId, slotVaddr)
        If attachedAddr <> 0 Then
            Dim sNew As Pointer To ClientShmSlot = @shmSlots(slotIdx)
            sNew.ClientNodeId = clientNodeId
            sNew.ClientShmId = clientShmId
            sNew.VfsVaddr = attachedAddr
            sNew.InUse = True
            AttachClientShm = attachedAddr
        Else
            AttachClientShm = 0
        End If
    End Function

    ''
    ' @brief Application entry point for vfs daemon (Ring 3 CPL=3).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[VFS] ======================================================="
        ConsoleWriteLine "[VFS] PROS Storage & Virtual File System (VFS) Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[VFS] Active Service PID = ", myPid, "\r\n"

        ' 2. Register VFS Storage Node in the Neural Node Registry
        Dim vfsNodeId As UInt64 = NodeRegister(3, "srv.vfs", 7)
        If vfsNodeId <> 0 Then
            ConsolePrintWithUInt "[VFS] Registered Node 'srv.vfs' -> Node #", vfsNodeId, "\r\n"
        Else
            ConsoleWriteLine "[VFS] WARN: Failed to register 'srv.vfs' node!"
        End If

        ' 3. Connect to System Supervisor
        Dim plexusNodeId As UInt64 = NodeLookup("srv.plexus_mgr")
        Dim synPlexus As UInt64 = 0
        If plexusNodeId <> 0 Then
            synPlexus = SynapseConnect(vfsNodeId, plexusNodeId, 7)
            If synPlexus <> 0 Then
                ConsolePrintWithUInt "[VFS] Established Supervisor Synapse -> Channel #", synPlexus, "\r\n"
            End If
        End If

        ' 4. Initialize mount tree and TarFS root driver
        InitMountTree
        ConsoleWriteLine "[VFS] Storage Arbiter online. Entering file request service loop..."
        ConsoleWriteLine "[VFS] ======================================================="

        ' 5. Active file service loop (Zero idle CPU via SynapsePopWait)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim reqCount As UInt64 = 0

        Do
            If SynapsePopWait(vfsNodeId, reqPkt) Then
                respPkt.Sequence = reqPkt.Sequence
                respPkt.SourceNode = vfsNodeId
                respPkt.TargetNode = reqPkt.SourceNode
                reqCount = reqCount + 1

                Select Case reqPkt.PacketType
                    Case FS_CMD_MOUNT
                        ' External Plexus registering a mount point
                        RegisterMount @reqPkt.Payload(0), reqPkt.SourceNode
                        respPkt.PacketType = VFS_RESP_OK
                        respPkt.PayloadLength = 0

                    Case VFS_CMD_LOOKUP, VFS_CMD_STAT
                        Dim normPath(128) As Byte
                        NormalizePath @reqPkt.Payload(0), @normPath(0)

                        Dim relPath(128) As Byte
                        Dim mIdx As Int32 = ResolveMount(@normPath(0), @relPath(0))

                        If mIdx >= 0 Then
                            Dim mEntry As Pointer To MountEntry = @mountTable(mIdx)
                            If mEntry.DriverKind = DRIVER_TARFS Then
                                Dim tIdx As Int32 = TarFS.Lookup(@relPath(0))
                                If tIdx >= 0 Or tIdx = -2 Then
                                    Dim fKind As UInt32 = 0
                                    Dim fSize As UInt32 = 0
                                    Dim fPerm As UInt32 = 0
                                    TarFS.Stat tIdx, fKind, fSize, fPerm

                                    respPkt.PacketType = VFS_RESP_OK
                                    respPkt.PayloadLength = 16
                                    Dim pKind As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                                    Dim pSize As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(4))
                                    Dim pPerm As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(8))
                                    Dim pStat As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(12))
                                    pKind(0) = fKind
                                    pSize(0) = fSize
                                    pPerm(0) = fPerm
                                    pStat(0) = 1
                                Else
                                    respPkt.PacketType = VFS_RESP_ERROR
                                    respPkt.PayloadLength = 0
                                End If
                            Else
                                ' Forward to external filesystem Plexus on dedicated channel
                                Dim fwdChan As UInt64 = SynapseConnect(vfsNodeId, mEntry.PlexusNodeId, 7)
                                If fwdChan <> 0 Then
                                    Dim fwdPkt As AxonPacket = reqPkt
                                    fwdPkt.SourceNode = vfsNodeId
                                    fwdPkt.TargetNode = mEntry.PlexusNodeId
                                    StrCopy @fwdPkt.Payload(0), 128, @relPath(0)
                                    SynapsePush fwdChan, fwdPkt
                                    SynapsePopWait fwdChan, respPkt
                                    respPkt.Sequence = reqPkt.Sequence
                                    respPkt.TargetNode = reqPkt.SourceNode
                                Else
                                    respPkt.PacketType = VFS_RESP_ERROR
                                    respPkt.PayloadLength = 0
                                End If
                            End If
                        Else
                            respPkt.PacketType = VFS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case VFS_CMD_READ
                        Dim pShm As Pointer To UInt64 = Pointer To UInt64(@reqPkt.Payload(0))
                        Dim pOff As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(8))
                        Dim pMax As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(12))
                        Dim clientShmId As UInt64 = pShm(0)
                        Dim fileOffset As UInt32 = pOff(0)
                        Dim maxBytes As UInt32 = pMax(0)
                        If maxBytes > 65536 Then maxBytes = 65536
                        If maxBytes = 0 Then maxBytes = 65536

                        Dim rNorm(128) As Byte
                        NormalizePath @reqPkt.Payload(16), @rNorm(0)

                        Dim rRel(128) As Byte
                        Dim rmIdx As Int32 = ResolveMount(@rNorm(0), @rRel(0))

                        If rmIdx >= 0 And clientShmId <> 0 Then
                            Dim targetShmVaddr As UInt64 = AttachClientShm(reqPkt.SourceNode, clientShmId)
                            If targetShmVaddr <> 0 Then
                                Dim rmEntry As Pointer To MountEntry = @mountTable(rmIdx)
                                If rmEntry.DriverKind = DRIVER_TARFS Then
                                    Dim rtIdx As Int32 = TarFS.Lookup(@rRel(0))
                                    If rtIdx >= 0 Then
                                        Dim rfKind As UInt32 = 0
                                        Dim rfSize As UInt32 = 0
                                        Dim rfPerm As UInt32 = 0
                                        TarFS.Stat rtIdx, rfKind, rfSize, rfPerm

                                        Dim bytesRead As UInt32 = TarFS.Read(rtIdx, fileOffset, maxBytes, Pointer To Byte(targetShmVaddr))
                                        respPkt.PacketType = VFS_RESP_OK
                                        respPkt.PayloadLength = 16
                                        Dim pRespRead  As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                                        Dim pRespTotal As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(4))
                                        Dim pRespFlags As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(8))
                                        Dim pRespStat  As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(12))

                                        pRespRead(0) = bytesRead
                                        pRespTotal(0) = rfSize
                                        If (fileOffset + bytesRead) >= fSize Then
                                            pRespFlags(0) = 1 ' Bit 0: EOF
                                        Else
                                            pRespFlags(0) = 0
                                        End If
                                        pRespStat(0) = 100
                                    Else
                                        respPkt.PacketType = VFS_RESP_ERROR
                                        respPkt.PayloadLength = 0
                                    End If
                                Else
                                    respPkt.PacketType = VFS_RESP_ERROR
                                    respPkt.PayloadLength = 0
                                End If
                            Else
                                respPkt.PacketType = VFS_RESP_ERROR
                                respPkt.PayloadLength = 0
                            End If
                        Else
                            respPkt.PacketType = VFS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case VFS_CMD_LIST
                        Dim pShmList As Pointer To UInt64 = Pointer To UInt64(@reqPkt.Payload(0))
                        Dim pMaxList As Pointer To UInt32 = Pointer To UInt32(@reqPkt.Payload(8))
                        Dim clientShmIdList As UInt64 = pShmList(0)
                        Dim maxBytesList As UInt32 = pMaxList(0)
                        If maxBytesList > 65536 Then maxBytesList = 65536
                        If maxBytesList = 0 Then maxBytesList = 65536

                        Dim lNorm(128) As Byte
                        NormalizePath @reqPkt.Payload(12), @lNorm(0)

                        Dim lRel(128) As Byte
                        Dim lmIdx As Int32 = ResolveMount(@lNorm(0), @lRel(0))

                        If lmIdx >= 0 And clientShmIdList <> 0 Then
                            Dim targetShmVaddrList As UInt64 = AttachClientShm(reqPkt.SourceNode, clientShmIdList)
                            If targetShmVaddrList <> 0 Then
                                Dim lmEntry As Pointer To MountEntry = @mountTable(lmIdx)
                                If lmEntry.DriverKind = DRIVER_TARFS Then
                                    Dim listCount As UInt32 = TarFS.ListDirectory(@lRel(0), Pointer To Byte(targetShmVaddrList), maxBytesList)

                                    ' Compute total bytes of null-separated names in SHM
                                    Dim payloadBytes As UInt32 = 0
                                    Dim shmBytes As Pointer To Byte = Pointer To Byte(targetShmVaddrList)
                                    If listCount > 0 Then
                                        Dim entryIdx As UInt32 = 0
                                        While entryIdx < listCount And payloadBytes < maxBytesList
                                            While shmBytes(payloadBytes) <> 0 And payloadBytes < maxBytesList
                                                payloadBytes = payloadBytes + 1
                                            Wend
                                            If payloadBytes < maxBytesList Then
                                                payloadBytes = payloadBytes + 1 ' Include null terminator
                                            End If
                                            entryIdx = entryIdx + 1
                                        Wend
                                    End If

                                    respPkt.PacketType = VFS_RESP_OK
                                    respPkt.PayloadLength = 12
                                    Dim pRespCount   As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(0))
                                    Dim pRespPayload As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(4))
                                    Dim pRespStatus  As Pointer To UInt32 = Pointer To UInt32(@respPkt.Payload(8))
                                    pRespCount(0) = listCount
                                    pRespPayload(0) = payloadBytes
                                    pRespStatus(0) = 100
                                Else
                                    respPkt.PacketType = VFS_RESP_ERROR
                                    respPkt.PayloadLength = 0
                                End If
                            Else
                                respPkt.PacketType = VFS_RESP_ERROR
                                respPkt.PayloadLength = 0
                            End If
                        Else
                            respPkt.PacketType = VFS_RESP_ERROR
                            respPkt.PayloadLength = 0
                        End If

                    Case Else
                        respPkt.PacketType = VFS_RESP_ERROR
                        respPkt.PayloadLength = 0
                End Select

                Dim replyChan As UInt64 = SynapseConnect(vfsNodeId, reqPkt.SourceNode, 7)
                If replyChan <> 0 Then
                    SynapsePush replyChan, respPkt
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
