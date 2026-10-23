' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/Strings.bas
' Summary: Low-level null-terminated ASCII string operations for hosted runtime.

Module Std.Strings

    ''
    ' @brief Computes length of null-terminated string (strlen equivalent).
    ' @param str Pointer to null-terminated string.
    ' @return Number of characters before null terminator.
    ''
    Public Unsafe Function Length(ByVal str As Pointer To Byte) As UInt64
        If str = 0 Then
            Length = 0
            Exit Function
        End If
        Dim lenVal As UInt64 = 0
        Do While str(lenVal) <> 0
            lenVal = lenVal + 1
        Loop
        Length = lenVal
    End Function

    ''
    ' @brief Lexicographically compares two null-terminated strings (strcmp equivalent).
    ' @param s1 Pointer to first string.
    ' @param s2 Pointer to second string.
    ' @return 0 if equal, -1 if s1 less than s2, 1 if s1 greater than s2.
    ''
    Public Unsafe Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
        If s1 = 0 And s2 = 0 Then
            Compare = 0
            Exit Function
        ElseIf s1 = 0 Then
            Compare = -1
            Exit Function
        ElseIf s2 = 0 Then
            Compare = 1
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While s1(i) <> 0 And s2(i) <> 0
            If s1(i) < s2(i) Then
                Compare = -1
                Exit Function
            ElseIf s1(i) > s2(i) Then
                Compare = 1
                Exit Function
            End If
            i = i + 1
        Loop

        If s1(i) = 0 And s2(i) = 0 Then
            Compare = 0
        ElseIf s1(i) = 0 Then
            Compare = -1
        Else
            Compare = 1
        End If
    End Function

    ''
    ' @brief Copies null-terminated string src into dest (strcpy equivalent).
    ' @param dest Pointer to destination buffer.
    ' @param src Pointer to source null-terminated string.
    ' @return Number of characters copied (excluding null terminator).
    ''
    Public Unsafe Function Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64
        If dest = 0 Or src = 0 Then
            Copy = 0
            Exit Function
        End If
        Dim i As UInt64 = 0
        Do While src(i) <> 0
            dest(i) = src(i)
            i = i + 1
        Loop
        dest(i) = 0
        Copy = i
    End Function

End Module
