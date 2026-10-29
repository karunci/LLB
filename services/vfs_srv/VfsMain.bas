' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/vfs_srv/VfsMain.bas
' Summary: Standalone Ring 3 Storage and Virtual File System (VFS) daemon.
'          Provides hybrid Windows + Android directory tree hierarchy, file metadata,
'          and Synapse IPC request servicing for client applications.

Import "../../include/pros.bas"

Module VfsMain

    Public Const VFS_KIND_FILE As UInt32 = 1
    Public Const VFS_KIND_DIR  As UInt32 = 2
    Public Const VFS_KIND_DEV  As UInt32 = 3

    Public Const VFS_CMD_LOOKUP As UInt32 = 10
    Public Const VFS_CMD_STAT   As UInt32 = 11
    Public Const VFS_CMD_LIST   As UInt32 = 12
    Public Const VFS_RESP_OK    As UInt32 = 100
    Public Const VFS_RESP_ERROR As UInt32 = 101

    <Packed>
    Structure VfsEntry
        Public Path     As String
        Public SizeBytes As UInt32
        Public Kind     As UInt32
        Public Perms    As UInt32
    End Structure

    ' Maximum mounted system nodes in RAM VFS table
    Private vfsTable(64) As VfsEntry
    Private vfsCount As UInt32

    ''
    ' @brief Normalize path string supporting Windows C:\ drive notation and backslashes.
    ' @param inPath Input path string pointer.
    ' @param outBuf Output normalized buffer (at least 128 bytes).
    ''
    Public Unsafe Sub NormalizePath(ByVal inPath As Pointer To Byte, ByVal outBuf As Pointer To Byte)
        If inPath = 0 Or outBuf = 0 Then Exit Sub

        Dim rIdx As UInt32 = 0
        Dim wIdx As UInt32 = 0

        ' Skip leading spaces
        While inPath(rIdx) = 32
            rIdx = rIdx + 1
        Wend

        ' Strip Windows drive prefix (e.g. "C:" or "c:")
        If (inPath(rIdx) = 67 Or inPath(rIdx) = 99) And inPath(rIdx + 1) = 58 Then
            rIdx = rIdx + 2
        End If

        ' Ensure leading forward slash
        If inPath(rIdx) <> 47 And inPath(rIdx) <> 92 Then
            outBuf(wIdx) = 47 ' '/'
            wIdx = wIdx + 1
        End If

        While inPath(rIdx) <> 0 And wIdx < 126
            Dim c As Byte = inPath(rIdx)
            ' Convert backslash '\' (92) to forward slash '/' (47)
            If c = 92 Then
                c = 47
            End If

            ' Collapse duplicate slashes
            If c = 47 And wIdx > 0 And outBuf(wIdx - 1) = 47 Then
                ' skip duplicate slash
            Else
                outBuf(wIdx) = c
                wIdx = wIdx + 1
            End If
            rIdx = rIdx + 1
        Wend

        ' Strip trailing slash if path is longer than "/"
        If wIdx > 1 And outBuf(wIdx - 1) = 47 Then
            wIdx = wIdx - 1
        End If

        outBuf(wIdx) = 0
    End Sub

    ''
    ' @brief Mount and populate the initial hybrid Windows + Android filesystem hierarchy.
    ''
    Private Unsafe Sub InitMountTree()
        vfsCount = 0

        ' Root directory
        vfsTable(0).Path = "/"
        vfsTable(0).SizeBytes = 0
        vfsTable(0).Kind = VFS_KIND_DIR
        vfsTable(0).Perms = &H0755

        ' 1. /Apps - User installed apps, their libraries, data, configs
        vfsTable(1).Path = "/Apps"
        vfsTable(1).SizeBytes = 0
        vfsTable(1).Kind = VFS_KIND_DIR
        vfsTable(1).Perms = &H0777

        vfsTable(2).Path = "/Apps/Terminal"
        vfsTable(2).SizeBytes = 0
        vfsTable(2).Kind = VFS_KIND_DIR
        vfsTable(2).Perms = &H0777

        vfsTable(3).Path = "/Apps/Terminal/terminal.bax"
        vfsTable(3).SizeBytes = 16384
        vfsTable(3).Kind = VFS_KIND_FILE
        vfsTable(3).Perms = &H0755

        vfsTable(4).Path = "/Apps/Terminal/lib"
        vfsTable(4).SizeBytes = 0
        vfsTable(4).Kind = VFS_KIND_DIR
        vfsTable(4).Perms = &H0777

        vfsTable(5).Path = "/Apps/UserApp"
        vfsTable(5).SizeBytes = 0
        vfsTable(5).Kind = VFS_KIND_DIR
        vfsTable(5).Perms = &H0777

        vfsTable(6).Path = "/Apps/UserApp/user_app.bax"
        vfsTable(6).SizeBytes = 12288
        vfsTable(6).Kind = VFS_KIND_FILE
        vfsTable(6).Perms = &H0755

        ' 2. /Libraries - System-wide shared libraries
        vfsTable(7).Path = "/Libraries"
        vfsTable(7).SizeBytes = 0
        vfsTable(7).Kind = VFS_KIND_DIR
        vfsTable(7).Perms = &H0755

        ' 3. /System - System-related files (configs, system apps, libraries, drivers, servers)
        vfsTable(8).Path = "/System"
        vfsTable(8).SizeBytes = 0
        vfsTable(8).Kind = VFS_KIND_DIR
        vfsTable(8).Perms = &H0755

        vfsTable(9).Path = "/System/Apps"
        vfsTable(9).SizeBytes = 0
        vfsTable(9).Kind = VFS_KIND_DIR
        vfsTable(9).Perms = &H0755

        vfsTable(10).Path = "/System/Apps/Shell"
        vfsTable(10).SizeBytes = 0
        vfsTable(10).Kind = VFS_KIND_DIR
        vfsTable(10).Perms = &H0755

        vfsTable(11).Path = "/System/Apps/Shell/lib"
        vfsTable(11).SizeBytes = 0
        vfsTable(11).Kind = VFS_KIND_DIR
        vfsTable(11).Perms = &H0755

        vfsTable(12).Path = "/System/Libraries"
        vfsTable(12).SizeBytes = 0
        vfsTable(12).Kind = VFS_KIND_DIR
        vfsTable(12).Perms = &H0755

        vfsTable(13).Path = "/System/Libraries/libpros.a"
        vfsTable(13).SizeBytes = 65536
        vfsTable(13).Kind = VFS_KIND_FILE
        vfsTable(13).Perms = &H0644

        vfsTable(14).Path = "/System/Libraries/libllb.a"
        vfsTable(14).SizeBytes = 65536
        vfsTable(14).Kind = VFS_KIND_FILE
        vfsTable(14).Perms = &H0644

        vfsTable(15).Path = "/System/Configs"
        vfsTable(15).SizeBytes = 0
        vfsTable(15).Kind = VFS_KIND_DIR
        vfsTable(15).Perms = &H0755

        vfsTable(16).Path = "/System/Configs/system.cfg"
        vfsTable(16).SizeBytes = 1024
        vfsTable(16).Kind = VFS_KIND_FILE
        vfsTable(16).Perms = &H0644

        vfsTable(17).Path = "/System/Drivers"
        vfsTable(17).SizeBytes = 0
        vfsTable(17).Kind = VFS_KIND_DIR
        vfsTable(17).Perms = &H0755

        vfsTable(18).Path = "/System/Servers"
        vfsTable(18).SizeBytes = 0
        vfsTable(18).Kind = VFS_KIND_DIR
        vfsTable(18).Perms = &H0755

        vfsTable(19).Path = "/System/Servers/genesis.bax"
        vfsTable(19).SizeBytes = 12288
        vfsTable(19).Kind = VFS_KIND_FILE
        vfsTable(19).Perms = &H0755

        vfsTable(20).Path = "/System/Servers/disp_srv.bax"
        vfsTable(20).SizeBytes = 8192
        vfsTable(20).Kind = VFS_KIND_FILE
        vfsTable(20).Perms = &H0755

        vfsTable(21).Path = "/System/Servers/input_srv.bax"
        vfsTable(21).SizeBytes = 8192
        vfsTable(21).Kind = VFS_KIND_FILE
        vfsTable(21).Perms = &H0755

        vfsTable(22).Path = "/System/Servers/compositor.bax"
        vfsTable(22).SizeBytes = 16384
        vfsTable(22).Kind = VFS_KIND_FILE
        vfsTable(22).Perms = &H0755

        vfsTable(23).Path = "/System/Servers/dev_mgr.bax"
        vfsTable(23).SizeBytes = 8192
        vfsTable(23).Kind = VFS_KIND_FILE
        vfsTable(23).Perms = &H0755

        vfsTable(24).Path = "/System/Servers/plexus_mgr.bax"
        vfsTable(24).SizeBytes = 8192
        vfsTable(24).Kind = VFS_KIND_FILE
        vfsTable(24).Perms = &H0755

        vfsTable(25).Path = "/System/Servers/wm.bax"
        vfsTable(25).SizeBytes = 8192
        vfsTable(25).Kind = VFS_KIND_FILE
        vfsTable(25).Perms = &H0755

        vfsTable(26).Path = "/System/Servers/vfs_srv.bax"
        vfsTable(26).SizeBytes = 8192
        vfsTable(26).Kind = VFS_KIND_FILE
        vfsTable(26).Perms = &H0755

        ' 4. /Users - User accounts directory
        vfsTable(27).Path = "/Users"
        vfsTable(27).SizeBytes = 0
        vfsTable(27).Kind = VFS_KIND_DIR
        vfsTable(27).Perms = &H0755

        vfsTable(28).Path = "/Users/Default"
        vfsTable(28).SizeBytes = 0
        vfsTable(28).Kind = VFS_KIND_DIR
        vfsTable(28).Perms = &H0777

        vfsTable(29).Path = "/Users/Default/Desktop"
        vfsTable(29).SizeBytes = 0
        vfsTable(29).Kind = VFS_KIND_DIR
        vfsTable(29).Perms = &H0777

        vfsTable(30).Path = "/Users/Default/Documents"
        vfsTable(30).SizeBytes = 0
        vfsTable(30).Kind = VFS_KIND_DIR
        vfsTable(30).Perms = &H0777

        vfsCount = 31
    End Sub

    ''
    ' @brief Look up a mounted file or directory by full path.
    ' @param pathPtr Target path string.
    ' @return Index in vfsTable, or -1 if not found.
    ''
    Public Unsafe Function ResolvePath(ByVal pathPtr As Pointer To Byte) As Int32
        If pathPtr = 0 Then
            ResolvePath = -1
            Exit Function
        End If

        Dim norm(128) As Byte
        NormalizePath pathPtr, @norm(0)

        Dim i As UInt32 = 0
        While i < vfsCount
            If StrEquals(@norm(0), vfsTable(i).Path) Then
                ResolvePath = Int32(i)
                Exit Function
            End If
            i = i + 1
        Wend
        ResolvePath = -1
    End Function

    ''
    ' @brief Application entry point for vfs daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
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

        ' 4. Initialize hybrid Android + Windows directory hierarchy
        InitMountTree
        ConsolePrintWithUInt "[VFS] Mounted root filesystem: '/' (Windows+Android Hierarchy, ", vfsCount, " entries)\r\n"
        ConsoleWriteLine "[VFS] Paths: /Apps (Applications), /System (Servers, Drivers, Libraries, Configs), /Users (Profiles)"
        ConsoleWriteLine "[VFS] Windows C:\\ path aliases mapped to /"
        ConsoleWriteLine "[VFS] Storage Arbiter online. Entering file request service loop..."
        ConsoleWriteLine "[VFS] ======================================================="

        ' 5. Active file service loop (Zero idle CPU via ProcessSleep)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim reqCount As UInt64 = 0

        Do
            ' Block on incoming requests directed to srv.vfs node (Zero idle CPU)
            If SynapsePopWait(vfsNodeId, reqPkt) Then
                ConsolePrintWithUInt "[VFS] Received request type: ", reqPkt.PacketType, "\r\n"
                If reqPkt.PacketType = VFS_CMD_LOOKUP Or reqPkt.PacketType = VFS_CMD_STAT Then
                    Dim nodeIdx As Int32 = ResolvePath(@reqPkt.Payload(0))
                    respPkt.Sequence = reqCount
                    respPkt.SourceNode = vfsNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    If nodeIdx >= 0 Then
                        respPkt.PacketType = VFS_RESP_OK
                        respPkt.PayloadLength = 16
                        Dim pKind As Pointer To UInt32 = *UInt32(@respPkt.Payload(0))
                        Dim pSize As Pointer To UInt32 = *UInt32(@respPkt.Payload(4))
                        Dim pPerm As Pointer To UInt32 = *UInt32(@respPkt.Payload(8))
                        Dim pStat As Pointer To UInt32 = *UInt32(@respPkt.Payload(12))
                        pKind(0) = vfsTable(nodeIdx).Kind
                        pSize(0) = vfsTable(nodeIdx).SizeBytes
                        pPerm(0) = vfsTable(nodeIdx).Perms
                        pStat(0) = 1
                    Else
                        respPkt.PacketType = VFS_RESP_ERROR
                        respPkt.PayloadLength = 0
                    End If

                    Dim replyChan As UInt64 = SynapseConnect(vfsNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                    reqCount = reqCount + 1
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
