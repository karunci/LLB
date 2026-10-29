' Project Name: LibLLB_Metal / Low-Level Basic
' Filename: lib/metal/src/Strings.bas
' Summary: Low-level null-terminated ASCII string operations (strlen, strcmp, strcpy, strcat).

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

    ''
    ' @brief Lexicographically compares at most n characters of two strings (strncmp equivalent).
    ' @param s1 Pointer to first string.
    ' @param s2 Pointer to second string.
    ' @param n Maximum number of characters to compare.
    ' @return 0 if equal, -1 if s1 < s2, 1 if s1 > s2.
    ''
    Public Unsafe Function CompareN(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal n As UInt64) As Int32
        If n = 0 Then
            CompareN = 0
            Exit Function
        End If
        If s1 = 0 And s2 = 0 Then
            CompareN = 0
            Exit Function
        ElseIf s1 = 0 Then
            CompareN = -1
            Exit Function
        ElseIf s2 = 0 Then
            CompareN = 1
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While i < n And s1(i) <> 0 And s2(i) <> 0
            If s1(i) < s2(i) Then
                CompareN = -1
                Exit Function
            ElseIf s1(i) > s2(i) Then
                CompareN = 1
                Exit Function
            End If
            i = i + 1
        Loop

        If i = n Then
            CompareN = 0
        ElseIf s1(i) = 0 And s2(i) = 0 Then
            CompareN = 0
        ElseIf s1(i) = 0 Then
            CompareN = -1
        Else
            CompareN = 1
        End If
    End Function

    ''
    ' @brief Copies at most n characters from src to dest (strncpy equivalent).
    ' @param dest Pointer to destination buffer.
    ' @param src Pointer to source string.
    ' @param n Maximum number of bytes to copy.
    ' @return Number of characters copied.
    ''
    Public Unsafe Function CopyN(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal n As UInt64) As UInt64
        If dest = 0 Or src = 0 Or n = 0 Then
            CopyN = 0
            Exit Function
        End If
        Dim i As UInt64 = 0
        Do While i < n And src(i) <> 0
            dest(i) = src(i)
            i = i + 1
        Loop
        Dim copied As UInt64 = i
        Do While i < n
            dest(i) = 0
            i = i + 1
        Loop
        CopyN = copied
    End Function

    ''
    ' @brief Finds the first occurrence of a character in a string (strchr equivalent).
    ' @param str Pointer to null-terminated string.
    ' @param c Character to find.
    ' @return Pointer to the matched character, or 0 if not found.
    ''
    Public Unsafe Function Find(ByVal str As Pointer To Byte, ByVal c As Byte) As Pointer To Byte
        If str = 0 Then
            Find = 0
            Exit Function
        End If
        Dim i As UInt64 = 0
        Do While str(i) <> 0
            If str(i) = c Then
                Find = str + i
                Exit Function
            End If
            i = i + 1
        Loop
        If c = 0 Then
            Find = str + i
        Else
            Find = 0
        End If
    End Function

    ''
    ' @brief Appends src string to the end of dest buffer (strcat equivalent).
    ' @param dest Pointer to null-terminated destination string buffer.
    ' @param src Pointer to null-terminated source string to append.
    ' @return Length of resulting concatenated string.
    ''
    Public Unsafe Function Concat(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64
        If dest = 0 Then
            Concat = 0
            Exit Function
        End If
        If src = 0 Then
            Concat = Length(dest)
            Exit Function
        End If
        Dim destLen As UInt64 = Length(dest)
        Dim i As UInt64 = 0
        Do While src(i) <> 0
            dest(destLen + i) = src(i)
            i = i + 1
        Loop
        dest(destLen + i) = 0
        Concat = destLen + i
    End Function

    ''
    ' @brief Extracts a substring starting at 0-based offset into outBuf (Mid equivalent).
    ' @param src Pointer to source string.
    ' @param start 0-based character index to begin extraction.
    ' @param count Maximum number of characters to copy.
    ' @param outBuf Pointer to buffer receiving extracted substring.
    ' @return Number of characters written.
    ''
    Public Unsafe Function SubString(ByVal src As Pointer To Byte, ByVal start As UInt64, ByVal count As UInt64, ByVal outBuf As Pointer To Byte) As UInt64
        If src = 0 Or outBuf = 0 Or count = 0 Then
            If outBuf <> 0 Then outBuf(0) = 0
            SubString = 0
            Exit Function
        End If
        Dim srcLen As UInt64 = Length(src)
        If start >= srcLen Then
            outBuf(0) = 0
            SubString = 0
            Exit Function
        End If
        Dim i As UInt64 = 0
        Do While i < count And src(start + i) <> 0
            outBuf(i) = src(start + i)
            i = i + 1
        Loop
        outBuf(i) = 0
        SubString = i
    End Function

    ''
    ' @brief Compares two strings case-insensitively (strcasecmp equivalent).
    ' @param s1 Pointer to first string.
    ' @param s2 Pointer to second string.
    ' @return 0 if equal, -1 if s1 < s2, 1 if s1 > s2.
    ''
    Public Unsafe Function CompareI(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
        If s1 = 0 And s2 = 0 Then
            CompareI = 0
            Exit Function
        ElseIf s1 = 0 Then
            CompareI = -1
            Exit Function
        ElseIf s2 = 0 Then
            CompareI = 1
            Exit Function
        End If

        Dim i As UInt64 = 0
        Do While s1(i) <> 0 And s2(i) <> 0
            Dim c1 As Byte = s1(i)
            Dim c2 As Byte = s2(i)
            If c1 >= 65 And c1 <= 90 Then c1 = c1 + 32
            If c2 >= 65 And c2 <= 90 Then c2 = c2 + 32
            If c1 < c2 Then
                CompareI = -1
                Exit Function
            ElseIf c1 > c2 Then
                CompareI = 1
                Exit Function
            End If
            i = i + 1
        Loop

        If s1(i) = 0 And s2(i) = 0 Then
            CompareI = 0
        ElseIf s1(i) = 0 Then
            CompareI = -1
        Else
            CompareI = 1
        End If
    End Function

End Module
