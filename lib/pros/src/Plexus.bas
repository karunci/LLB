' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Plexus.bas
' Summary: Client Service Supervisor API.

Import Pros.Sys.RawSyscall
Import Pros.Nodes.NodeRegistry

Namespace Pros.Services

    Public Module ServiceSupervisorClient

        ''
        ' @brief Verify whether a named system service is active and supervised.
        ' @param serviceName Null-terminated service name.
        ' @return True if service node is active.
        ''
        Public Unsafe Function IsServiceActive(ByVal serviceName As Pointer To Byte) As Boolean
            Dim srvNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(serviceName)
            IsServiceActive = (srvNodeId <> 0)
        End Function

    End Module

End Namespace
