' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/SingleUseHelper.cls
' Workspace Path: tests/userland
' Summary: SingleUse class unit test.

<Instancing(SingleUse)>
Class SingleUseHelper

    Private m_status As Int32

    Public Sub Initialize(ByVal st As Int32)
        Me.m_status = st
    End Sub

    Public Function GetStatus() As Int32
        GetStatus = Me.m_status
    End Function

    Public Sub SetStatus(ByVal st As Int32)
        Me.m_status = st
    End Sub

End Class
