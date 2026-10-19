' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module SharedLib

    Public Function AddNumbers(ByVal a As Int32, ByVal b As Int32) As Int32
        AddNumbers = a + b
    End Function

    Public Function GetGreeting(ByVal name As String) As String
        Dim greeting As String
        greeting = "Hello, " & name & "! Welcome to LLB Shared Library."
        GetGreeting = greeting
    End Function

End Module
