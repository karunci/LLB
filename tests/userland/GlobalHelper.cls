' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/GlobalHelper.cls
' Workspace Path: tests/userland
' Summary: Global class unit test with static instance.

<Instancing(Global)>
Class GlobalHelper

    Private m_counter As Int32

    Public Sub Initialize(ByVal startVal As Int32)
        Me.m_counter = startVal
    End Sub

    Public Sub Increment()
        Me.m_counter = Me.m_counter + 1
    End Sub

    Public Function GetCounter() As Int32
        GetCounter = Me.m_counter
    End Function

End Class
