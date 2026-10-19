' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

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
