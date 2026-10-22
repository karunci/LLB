' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/NestedNamespaceY.cls
' Summary: Multi-class nested namespace fixture Y.

Namespace NestedY

    <Instancing(SingleUse)>
    Public Class Z
        Public Function GetValue() As Int32
            GetValue = 303
        End Function
    End Class

End Namespace
