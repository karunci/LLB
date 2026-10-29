' Project Name: LibLLB_Metal / Low-Level Basic
' Filename: lib/metal/src/Memory.bas
' Summary: Standard memory manipulation primitives (memset, memcpy, memmove, memcmp).

Module Std.Memory

    ''
    ' @brief Fills count bytes of memory starting at dest with value (memset equivalent).
    ' @param dest Pointer to destination memory buffer.
    ' @param val Byte value to set.
    ' @param count Number of bytes to fill.
    ''
    Public Unsafe Sub Fill(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
        Dim i As UInt64 = 0
        Do While i < count
            dest(i) = val
            i = i + 1
        Loop
    End Sub

    ''
    ' @brief Copies count bytes from src to dest (memcpy equivalent; non-overlapping).
    ' @param dest Pointer to destination memory buffer.
    ' @param src Pointer to source memory buffer.
    ' @param count Number of bytes to copy.
    ''
    Public Unsafe Sub Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
        Dim i As UInt64 = 0
        Do While i < count
            dest(i) = src(i)
            i = i + 1
        Loop
    End Sub

    ''
    ' @brief Copies count bytes from src to dest, correctly handling overlapping regions (memmove equivalent).
    ' @param dest Pointer to destination memory buffer.
    ' @param src Pointer to source memory buffer.
    ' @param count Number of bytes to copy.
    ''
    Public Unsafe Sub Move(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
        If count = 0 Or dest = src Then Exit Sub
        If dest < src Then
            Copy dest, src, count
        Else
            Dim i As Int64 = Int64(count) - 1
            Do While i >= 0
                dest(i) = src(i)
                i = i - 1
            Loop
        End If
    End Sub

    ''
    ' @brief Compares first count bytes of two memory buffers (memcmp equivalent).
    ' @param s1 Pointer to first memory buffer.
    ' @param s2 Pointer to second memory buffer.
    ' @param count Number of bytes to compare.
    ' @return 0 if equal, -1 if s1 less than s2, 1 if s1 greater than s2.
    ''
    Public Unsafe Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32
        Dim i As UInt64 = 0
        Do While i < count
            If s1(i) < s2(i) Then
                Compare = -1
                Exit Function
            ElseIf s1(i) > s2(i) Then
                Compare = 1
                Exit Function
            End If
            i = i + 1
        Loop
        Compare = 0
    End Function

    ''
    ' @brief Convenience alias for Fill (memset equivalent).
    ' @param dest Pointer to destination memory buffer.
    ' @param val Byte value to set.
    ' @param count Number of bytes to set.
    ''
    Public Unsafe Sub SetBytes(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
        Fill dest, val, count
    End Sub

    ''
    ' @brief Searches the first count bytes of memory for the specified byte (memchr equivalent).
    ' @param ptr Pointer to memory buffer to search.
    ' @param val Byte value to locate.
    ' @param count Maximum number of bytes to inspect.
    ' @return Pointer to first matching byte, or 0 if not found.
    ''
    Public Unsafe Function Search(ByVal ptr As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64) As Pointer To Byte
        If ptr = 0 Or count = 0 Then
            Search = 0
            Exit Function
        End If
        Dim i As UInt64 = 0
        Do While i < count
            If ptr(i) = val Then
                Search = ptr + i
                Exit Function
            End If
            i = i + 1
        Loop
        Search = 0
    End Function

    ''
    ' @brief Optimized 64-bit word chunk copy for aligned memory buffers.
    ' @param dest Pointer to destination memory buffer.
    ' @param src Pointer to source memory buffer.
    ' @param count Total number of bytes to copy.
    ''
    Public Unsafe Sub CopyFast(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
        If dest = 0 Or src = 0 Or count = 0 Or dest = src Then Exit Sub
        Dim words As UInt64 = count / 8
        Dim remainder As UInt64 = count Mod 8
        If words > 0 Then
            Dim d64 As Pointer To UInt64 = *UInt64(dest)
            Dim s64 As Pointer To UInt64 = *UInt64(src)
            Dim w As UInt64 = 0
            Do While w < words
                d64(w) = s64(w)
                w = w + 1
            Loop
        End If
        If remainder > 0 Then
            Dim offset As UInt64 = words * 8
            Dim b As UInt64 = 0
            Do While b < remainder
                dest(offset + b) = src(offset + b)
                b = b + 1
            Loop
        End If
    End Sub

End Module
