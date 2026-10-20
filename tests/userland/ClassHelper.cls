' Project: Low-Level Basic Compiler (llbc)
' File: tests/userland/ClassHelper.cls
' Summary: MultiUse helper class for OOP unit testing.

<Instancing(MultiUse)>
Class ClassHelper

    Private m_val As Int32
    Private m_tag As Int32

    Public Sub Initialize(ByVal v As Int32)
        Me.m_val = v
        Me.m_tag = 100
    End Sub

    Public Sub SetValue(ByVal v As Int32)
        Me.m_val = v
    End Sub

    Public Function GetValue() As Int32
        GetValue = Me.m_val
    End Function

    Public Function ComputeSum(ByVal extra As Int32) As Int32
        ComputeSum = Me.m_val + Me.m_tag + extra
    End Function

End Class
