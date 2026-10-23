' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/Memory.bas
' Summary: Standard memory manipulation primitives for hosted runtime.

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
            Dim i As Int64 = CType(Int64, count) - 1
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

End Module
