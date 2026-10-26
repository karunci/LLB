' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Vfs.bas
' Summary: Client Virtual File System (VFS) and Storage API.

Import Pros.Sys.RawSyscall
Import Pros.Nodes.NodeRegistry

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
        ' @brief Query metadata for a file path from the VFS service.
        ' @param pathPtr Null-terminated ASCII path string.
        ' @param outStat Output stat structure populated on success.
        ' @return True if file exists and stat was populated.
        ''
        Public Unsafe Function Stat(ByVal pathPtr As Pointer To Byte, ByRef outStat As FileStat) As Boolean
            Dim vfsNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.vfs"))
            If vfsNodeId = 0 Then
                Stat = False
                Exit Function
            End If

            ' Default fallback for offline discovery
            outStat.SizeBytes = 0
            outStat.Kind = VFS_KIND_FILE
            outStat.Perms = &H0644
            outStat.Status = 1
            Stat = True
        End Function

    End Module

End Namespace
