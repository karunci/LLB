' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

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
