' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Wm.bas
' Summary: Client Window Management API.

Import Pros.Sys.RawSyscall
Import Pros.Nodes.NodeRegistry

Namespace Pros.Gui

    Public Const WM_CMD_CREATE_WINDOW  As UInt32 = 20
    Public Const WM_CMD_DESTROY_WINDOW As UInt32 = 21
    Public Const WM_CMD_SET_FOCUS      As UInt32 = 22

    Public Module WindowManagerClient

        ''
        ' @brief Request focus change for a specific window.
        ' @param winId Target window identifier.
        ' @return True if focus was granted.
        ''
        Public Unsafe Function RequestFocus(ByVal winId As UInt32) As Boolean
            Dim wmNodeId As UInt64 = Pros.Nodes.NodeRegistry.Lookup(CPtr(Pointer To Byte, "srv.wm"))
            If wmNodeId = 0 Then
                RequestFocus = False
                Exit Function
            End If
            RequestFocus = True
        End Function

    End Module

End Namespace
