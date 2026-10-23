' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/Conv.bas
' Summary: String to numeric parsing and conversion routines for hosted runtime.

Import Ascii

Module Conv

    ''
    ' @brief Parses an unsigned 64-bit integer from a base-10 ASCII string.
    ' @param str Pointer to null-terminated string.
    ' @return Parsed unsigned 64-bit integer.
    ''
    Public Unsafe Function ParseUInt(ByVal str As Pointer To Byte) As UInt64
        If str = 0 Then
            ParseUInt = 0
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While Ascii.IsWhitespace(str(i))
            i = i + 1
        Loop

        Dim result As UInt64 = 0
        Do While Ascii.IsDigit(str(i))
            Dim digitVal As UInt64 = CType(UInt64, str(i) - 48)
            result = result * CType(UInt64, 10) + digitVal
            i = i + 1
        Loop
        ParseUInt = result
    End Function

    ''
    ' @brief Parses a signed 64-bit integer from an ASCII string.
    ' @param str Pointer to null-terminated string.
    ' @return Parsed signed 64-bit integer.
    ''
    Public Unsafe Function ParseInt(ByVal str As Pointer To Byte) As Int64
        If str = 0 Then
            ParseInt = 0
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While Ascii.IsWhitespace(str(i))
            i = i + 1
        Loop

        Dim negative As Boolean = False
        If str(i) = 45 Then ' '-'
            negative = True
            i = i + 1
        ElseIf str(i) = 43 Then ' '+'
            i = i + 1
        End If

        Dim ures As UInt64 = ParseUInt(str + i)
        If negative Then
            ParseInt = 0 - CType(Int64, ures)
        Else
            ParseInt = CType(Int64, ures)
        End If
    End Function

    ''
    ' @brief Parses an unsigned 64-bit integer from a hexadecimal string (with optional "0x" prefix).
    ' @param str Pointer to null-terminated hexadecimal string.
    ' @return Parsed unsigned 64-bit value.
    ''
    Public Unsafe Function ParseHex(ByVal str As Pointer To Byte) As UInt64
        If str = 0 Then
            ParseHex = 0
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While Ascii.IsWhitespace(str(i))
            i = i + 1
        Loop

        If str(i) = 48 And (str(i + 1) = 120 Or str(i + 1) = 88) Then ' "0x" / "0X"
            i = i + 2
        End If

        Dim result As UInt64 = 0
        Do While Ascii.IsHexDigit(str(i))
            Dim b As Byte = str(i)
            Dim digitVal As UInt64 = 0
            If b >= 48 And b <= 57 Then
                digitVal = CType(UInt64, b - 48)
            ElseIf b >= 65 And b <= 70 Then
                digitVal = CType(UInt64, b - 55)
            ElseIf b >= 97 And b <= 102 Then
                digitVal = CType(UInt64, b - 87)
            End If
            result = (result LShift 4) Or digitVal
            i = i + 1
        Loop
        ParseHex = result
    End Function

End Module
