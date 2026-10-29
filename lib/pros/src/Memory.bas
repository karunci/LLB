' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Memory.bas
' Summary: Pure Low-Level Basic memory manipulation primitives wrapping freestanding runtime mem operations.

Namespace Pros.Memory

    Public Module MemUtil

        ' Freestanding runtime assembly primitives from lib/runtime/mem.S
        Public Declare Function memcpy Lib "c" Alias "memcpy" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64) As Pointer To Byte
        Public Declare Function memmove Lib "c" Alias "memmove" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64) As Pointer To Byte
        Public Declare Function memset Lib "c" Alias "memset" (ByVal dest As Pointer To Byte, ByVal val As Int32, ByVal count As UInt64) As Pointer To Byte
        Public Declare Function memcmp Lib "c" Alias "memcmp" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32

        ''
        ' @brief Copies count bytes from non-overlapping src buffer to dest buffer.
        ' @param dest Pointer to destination memory buffer.
        ' @param src Pointer to source memory buffer.
        ' @param count Number of bytes to copy.
        ''
        Public Unsafe Sub Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
            If dest = 0 Or src = 0 Or count = 0 Or dest = src Then Exit Sub
            memcpy dest, src, count
        End Sub

        ''
        ' @brief Copies count bytes from src buffer to dest buffer, safely handling overlapping memory regions.
        ' @param dest Pointer to destination memory buffer.
        ' @param src Pointer to source memory buffer.
        ' @param count Number of bytes to copy.
        ''
        Public Unsafe Sub Move(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
            If dest = 0 Or src = 0 Or count = 0 Or dest = src Then Exit Sub
            memmove dest, src, count
        End Sub

        ''
        ' @brief Fills count bytes of memory starting at dest with the specified byte value.
        '        (Named SetBytes because 'Set' is a reserved keyword in Low-Level Basic).
        ' @param dest Pointer to destination memory buffer.
        ' @param val Byte value to store across buffer.
        ' @param count Number of bytes to fill.
        ''
        Public Unsafe Sub SetBytes(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
            If dest = 0 Or count = 0 Then Exit Sub
            memset dest, CType(Int32, val), count
        End Sub

        ''
        ' @brief Lexicographically compares count bytes between two memory buffers.
        ' @param s1 Pointer to first memory buffer.
        ' @param s2 Pointer to second memory buffer.
        ' @param count Number of bytes to compare.
        ' @return < 0 if s1 < s2, 0 if s1 == s2, > 0 if s1 > s2.
        ''
        Public Unsafe Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32
            If count = 0 Or s1 = s2 Then
                Compare = 0
                Exit Function
            End If
            If s1 = 0 Then
                Compare = -1
                Exit Function
            End If
            If s2 = 0 Then
                Compare = 1
                Exit Function
            End If
            Compare = memcmp(s1, s2, count)
        End Function

    End Module

End Namespace

