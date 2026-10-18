' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/StaticMath.bas
' Workspace Path: tests/userland/StaticMath.bas
' Summary: Reusable math utility module compiled into a static library archive (.a).

Module StaticMath

    Public Function StaticMultiply(ByVal a As Int32, ByVal b As Int32) As Int32
        StaticMultiply = a * b
    End Function

    Public Function StaticPower(ByVal baseVal As Int32, ByVal expVal As Int32) As Int32
        Dim result As Int32
        result = 1
        Dim i As Int32
        For i = 1 To expVal
            result = result * baseVal
        Next i
        StaticPower = result
    End Function

End Module
