' Project Name: LibLLB_Metal / Low-Level Basic
' Filename: lib/metal/src/Ascii.bas
' Summary: ASCII character classification and conversion routines (ctype.h equivalent).

Module Ascii

    ''
    ' @brief Checks if character is a decimal digit ('0'..'9').
    ' @param c Character byte.
    ' @return True if '0' <= c <= '9'.
    ''
    Public Function IsDigit(ByVal c As Byte) As Boolean
        IsDigit = (c >= 48 And c <= 57)
    End Function

    ''
    ' @brief Checks if character is an alphabetic letter ('A'..'Z', 'a'..'z').
    ' @param c Character byte.
    ' @return True if alphabetic.
    ''
    Public Function IsAlpha(ByVal c As Byte) As Boolean
        IsAlpha = ((c >= 65 And c <= 90) Or (c >= 97 And c <= 122))
    End Function

    ''
    ' @brief Checks if character is alphanumeric ('A'..'Z', 'a'..'z', '0'..'9').
    ' @param c Character byte.
    ' @return True if alphanumeric.
    ''
    Public Function IsAlnum(ByVal c As Byte) As Boolean
        IsAlnum = (IsAlpha(c) Or IsDigit(c))
    End Function

    ''
    ' @brief Checks if character is whitespace (space, tab, CR, LF, VT, FF).
    ' @param c Character byte.
    ' @return True if whitespace.
    ''
    Public Function IsWhitespace(ByVal c As Byte) As Boolean
        IsWhitespace = (c = 32 Or (c >= 9 And c <= 13))
    End Function

    ''
    ' @brief Converts lowercase character to uppercase.
    ' @param c Character byte.
    ' @return Uppercase ASCII character.
    ''
    Public Function ToUpper(ByVal c As Byte) As Byte
        If c >= 97 And c <= 122 Then
            ToUpper = CType(Byte, c - 32)
        Else
            ToUpper = c
        End If
    End Function

    ''
    ' @brief Converts uppercase character to lowercase.
    ' @param c Character byte.
    ' @return Lowercase ASCII character.
    ''
    Public Function ToLower(ByVal c As Byte) As Byte
        If c >= 65 And c <= 90 Then
            ToLower = CType(Byte, c + 32)
        Else
            ToLower = c
        End If
    End Function

    ''
    ' @brief Checks if character is a hexadecimal digit ('0'..'9', 'A'..'F', 'a'..'f').
    ' @param c Character byte.
    ' @return True if hex digit.
    ''
    Public Function IsHexDigit(ByVal c As Byte) As Boolean
        IsHexDigit = (IsDigit(c) Or (c >= 65 And c <= 70) Or (c >= 97 And c <= 102))
    End Function

End Module
