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
        Public Path     As Pointer To Byte
        Public SizeBytes As UInt32
        Public Kind     As UInt32
        Public Perms    As UInt32
    End Structure

    ' Maximum mounted system nodes in RAM VFS table
    Private vfsTable(24) As VfsEntry
    Private vfsCount As UInt32

    ''
    ' @brief String equality comparison helper for ASCII null-terminated paths.
    ' @param s1 First string pointer.
    ' @param s2 Second string pointer.
    ' @return True if strings match character for character.
    ''
    Private Unsafe Function StrEquals(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Boolean
        If s1 = CPtr(Pointer To Byte, 0) Or s2 = CPtr(Pointer To Byte, 0) Then
            StrEquals = False
            Exit Function
        End If
        Dim idx As UInt32 = 0
        While s1(idx) <> 0 And s2(idx) <> 0
            If s1(idx) <> s2(idx) Then
                StrEquals = False
                Exit Function
            End If
            idx = idx + 1
        Wend
        StrEquals = (s1(idx) = 0 And s2(idx) = 0)
    End Function

    ''
    ' @brief Mount and populate the initial hybrid Windows + Android filesystem hierarchy.
    ''
    Private Unsafe Sub InitMountTree()
        vfsCount = 0

        ' 1. Root & System OS directories (Android / Unix system hierarchy)
        vfsTable(0).Path = CPtr(Pointer To Byte, "/")
        vfsTable(0).SizeBytes = 0
        vfsTable(0).Kind = VFS_KIND_DIR
        vfsTable(0).Perms = &H0755

        vfsTable(1).Path = CPtr(Pointer To Byte, "/system")
        vfsTable(1).SizeBytes = 0
        vfsTable(1).Kind = VFS_KIND_DIR
        vfsTable(1).Perms = &H0755

        vfsTable(2).Path = CPtr(Pointer To Byte, "/system/bin")
        vfsTable(2).SizeBytes = 0
        vfsTable(2).Kind = VFS_KIND_DIR
        vfsTable(2).Perms = &H0755

        ' 2. Core Service Executables (/system/bin)
        vfsTable(3).Path = CPtr(Pointer To Byte, "/system/bin/genesis.bax")
        vfsTable(3).SizeBytes = 12288
        vfsTable(3).Kind = VFS_KIND_FILE
        vfsTable(3).Perms = &H0755

        vfsTable(4).Path = CPtr(Pointer To Byte, "/system/bin/disp_srv.bax")
        vfsTable(4).SizeBytes = 8192
        vfsTable(4).Kind = VFS_KIND_FILE
        vfsTable(4).Perms = &H0755

        vfsTable(5).Path = CPtr(Pointer To Byte, "/system/bin/input_srv.bax")
        vfsTable(5).SizeBytes = 8192
        vfsTable(5).Kind = VFS_KIND_FILE
        vfsTable(5).Perms = &H0755

        vfsTable(6).Path = CPtr(Pointer To Byte, "/system/bin/compositor.bax")
        vfsTable(6).SizeBytes = 16384
        vfsTable(6).Kind = VFS_KIND_FILE
        vfsTable(6).Perms = &H0755

        vfsTable(7).Path = CPtr(Pointer To Byte, "/system/bin/dev_mgr.bax")
        vfsTable(7).SizeBytes = 8192
        vfsTable(7).Kind = VFS_KIND_FILE
        vfsTable(7).Perms = &H0755

        vfsTable(8).Path = CPtr(Pointer To Byte, "/system/bin/plexus_mgr.bax")
        vfsTable(8).SizeBytes = 8192
        vfsTable(8).Kind = VFS_KIND_FILE
        vfsTable(8).Perms = &H0755

        vfsTable(9).Path = CPtr(Pointer To Byte, "/system/bin/wm.bax")
        vfsTable(9).SizeBytes = 8192
        vfsTable(9).Kind = VFS_KIND_FILE
        vfsTable(9).Perms = &H0755

        vfsTable(10).Path = CPtr(Pointer To Byte, "/system/bin/vfs_srv.bax")
        vfsTable(10).SizeBytes = 8192
        vfsTable(10).Kind = VFS_KIND_FILE
        vfsTable(10).Perms = &H0755

        ' 3. System Libraries & Manifest
        vfsTable(11).Path = CPtr(Pointer To Byte, "/system/lib")
        vfsTable(11).SizeBytes = 0
        vfsTable(11).Kind = VFS_KIND_DIR
        vfsTable(11).Perms = &H0755

        vfsTable(12).Path = CPtr(Pointer To Byte, "/system/lib/libpros.a")
        vfsTable(12).SizeBytes = 65536
        vfsTable(12).Kind = VFS_KIND_FILE
        vfsTable(12).Perms = &H0644

        vfsTable(13).Path = CPtr(Pointer To Byte, "/system/manifest.json")
        vfsTable(13).SizeBytes = 512
        vfsTable(13).Kind = VFS_KIND_FILE
        vfsTable(13).Perms = &H0644

        ' 4. User Application and Persistent Data (/data)
        vfsTable(14).Path = CPtr(Pointer To Byte, "/data")
        vfsTable(14).SizeBytes = 0
        vfsTable(14).Kind = VFS_KIND_DIR
        vfsTable(14).Perms = &H0777

        vfsTable(15).Path = CPtr(Pointer To Byte, "/data/app")
        vfsTable(15).SizeBytes = 0
        vfsTable(15).Kind = VFS_KIND_DIR
        vfsTable(15).Perms = &H0777

        vfsTable(16).Path = CPtr(Pointer To Byte, "/data/user")
        vfsTable(16).SizeBytes = 0
        vfsTable(16).Kind = VFS_KIND_DIR
        vfsTable(16).Perms = &H0777

        ' 5. Virtual Device Mountpoints (/dev)
        vfsTable(17).Path = CPtr(Pointer To Byte, "/dev")
        vfsTable(17).SizeBytes = 0
        vfsTable(17).Kind = VFS_KIND_DIR
        vfsTable(17).Perms = &H0755

        vfsTable(18).Path = CPtr(Pointer To Byte, "/dev/disp")
        vfsTable(18).SizeBytes = 0
        vfsTable(18).Kind = VFS_KIND_DEV
        vfsTable(18).Perms = &H0666

        vfsTable(19).Path = CPtr(Pointer To Byte, "/dev/input")
        vfsTable(19).SizeBytes = 0
        vfsTable(19).Kind = VFS_KIND_DEV
        vfsTable(19).Perms = &H0666

        vfsTable(20).Path = CPtr(Pointer To Byte, "/dev/fb0")
        vfsTable(20).SizeBytes = 0
        vfsTable(20).Kind = VFS_KIND_DEV
        vfsTable(20).Perms = &H0666

        vfsCount = 21
    End Sub

    ''
    ' @brief Look up a mounted file or directory by full path.
    ' @param pathPtr Target path string.
    ' @return Index in vfsTable, or -1 if not found.
    ''
    Public Unsafe Function ResolvePath(ByVal pathPtr As Pointer To Byte) As Int32
        Dim i As UInt32 = 0
        While i < vfsCount
            If StrEquals(pathPtr, vfsTable(i).Path) Then
                ResolvePath = CType(Int32, i)
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
        Dim vfsNodeId As UInt64 = NodeRegister(3, CPtr(Pointer To Byte, "srv.vfs"), 7)
        If vfsNodeId <> 0 Then
            ConsolePrintWithUInt "[VFS] Registered Node 'srv.vfs' -> Node #", vfsNodeId, "\r\n"
        Else
            ConsoleWriteLine "[VFS] WARN: Failed to register 'srv.vfs' node!"
        End If

        ' 3. Connect to System Supervisor
        Dim plexusNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.plexus_mgr"))
        Dim synPlexus As UInt64 = 0
        If plexusNodeId <> 0 Then
            synPlexus = SynapseConnect(vfsNodeId, plexusNodeId, 7)
            If synPlexus <> 0 Then
                ConsolePrintWithUInt "[VFS] Established Supervisor Synapse -> Channel #", synPlexus, "\r\n"
            End If
        End If

        ' 4. Initialize hybrid Android + Windows directory hierarchy
        InitMountTree
        ConsolePrintWithUInt "[VFS] Mounted root filesystem: '/system' (USTAR Hierarchy, ", CType(UInt64, vfsCount), " entries)\r\n"
        ConsoleWriteLine "[VFS] Paths: /system/bin (Executables), /system/lib (Libraries), /data (User), /dev (Devices)"
        ConsoleWriteLine "[VFS] Storage Arbiter online. Entering file request service loop..."
        ConsoleWriteLine "[VFS] ======================================================="

        ' 5. Active file service loop (Zero idle CPU via ProcessSleep)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim reqCount As UInt64 = 0

        Do
            ' Poll for incoming file service requests over control synapse
            If synPlexus <> 0 And SynapsePop(synPlexus, reqPkt) Then
                If reqPkt.PacketType = VFS_CMD_LOOKUP Then
                    Dim nodeIdx As Int32 = ResolvePath(@reqPkt.Payload(0))
                    respPkt.Sequence = reqCount
                    respPkt.Timestamp = GetUptime()
                    If nodeIdx >= 0 Then
                        respPkt.PacketType = VFS_RESP_OK
                        respPkt.Length = 12
                        ' Payload: [Kind: UInt32, Size: UInt32, Perms: UInt32]
                        Dim pKind As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                        Dim pSize As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(4))
                        Dim pPerm As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(8))
                        pKind(0) = vfsTable(nodeIdx).Kind
                        pSize(0) = vfsTable(nodeIdx).SizeBytes
                        pPerm(0) = vfsTable(nodeIdx).Perms
                    Else
                        respPkt.PacketType = VFS_RESP_ERROR
                        respPkt.Length = 0
                    End If
                    SynapsePush synPlexus, respPkt
                    reqCount = reqCount + 1
                End If
            End If

            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module
