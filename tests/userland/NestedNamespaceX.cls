' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/NestedNamespaceX.cls
' Summary: Multi-class nested namespace fixture X.

Namespace NestedX

    <Instancing(SingleUse)>
    Public Class Y
        Public Function GetValue() As Int32
            GetValue = 101
        End Function
    End Class

    <Instancing(SingleUse)>
    Public Class Z
        Public Function GetValue() As Int32
            GetValue = 202
        End Function
    End Class

End Namespace
