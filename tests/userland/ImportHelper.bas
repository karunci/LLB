' Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
' Filename: tests/userland/ImportHelper.bas
' Workspace Path: tests/userland
' Summary: Helper module defining exported functions, structures, and enums for Import testing.

Module ImportHelper

    Public Enum LogPriority
        LogLow = 10
        LogMedium = 20
        LogHigh = 30
    End Enum

    Public Structure Vector2D
        Public X As Int32
        Public Y As Int32
    End Structure

    Public Function CalculateArea(ByVal width As Int32, ByVal height As Int32) As Int32
        CalculateArea = width * height
    End Function

    Public Function GetPriorityScore(ByVal p As LogPriority) As Int32
        GetPriorityScore = CInt(p) * 2
    End Function

End Module
