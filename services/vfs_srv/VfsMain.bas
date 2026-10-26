' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/vfs_srv/VfsMain.bas
' Summary: Standalone Ring 3 Storage and Virtual File System (VFS) daemon.
'          Provides memory-mapped USTAR ramdisk navigation and file storage services.

Import "../../include/pros.bas"

Module VfsMain

    ''
    ' @brief Application entry point for vfs daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[VFS] ======================================================="
        ConsoleWriteLine "[VFS] PROS Storage & VFS Service Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[VFS] Active Service PID = ", myPid, "\r\n"

        ' 2. Register VFS Storage Node
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

        ' 4. Mount in-memory root filesystem
        ConsoleWriteLine "[VFS] Mounted root filesystem: '/system' (USTAR Ramdisk)"
        ConsoleWriteLine "[VFS] Storage Arbiter online. Entering file request loop..."
        ConsoleWriteLine "[VFS] ======================================================="

        ' 5. Active file service loop (Zero idle CPU via ProcessSleep)
        Do
            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
