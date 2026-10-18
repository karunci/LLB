' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/SharedLib.bas
' Workspace Path: tests/userland
' Summary: Shared library demonstration providing exported procedures.

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
