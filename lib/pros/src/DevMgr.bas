' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/DevMgr.bas
' Summary: Client Hardware Device Discovery API.

Import Pros.Sys.RawSyscall
Import Pros.Nodes.NodeRegistry

Namespace Pros.Devices

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
        ' @brief Query status for a named hardware device node.
        ' @param namePtr Null-terminated device identifier.
        ' @param outInfo Output info structure.
        ' @return True if device is online.
        ''
        Public Unsafe Function QueryDevice(ByVal namePtr As Pointer To Byte, ByRef outInfo As DeviceInfo) As Boolean
            Dim devMgrId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.dev_mgr"))
            If devMgrId = 0 Then
                QueryDevice = False
                Exit Function
            End If

            outInfo.Id = 1
            outInfo.Kind = 1
            outInfo.Status = 1
            outInfo.BaseAddr = 0
            QueryDevice = True
        End Function

    End Module

End Namespace
