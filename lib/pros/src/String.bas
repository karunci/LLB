' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/String.bas
' Summary: Pure Low-Level Basic standard string manipulation and formatting library.

Namespace Pros.String

    Public Module StringUtil

        ''
        ' @brief Computes length of null-terminated ASCII string excluding null terminator.
        ' @param s String or pointer to null-terminated string.
        ' @return Number of characters before null terminator, or 0 if pointer is null.
        ''
        Public Unsafe Function StrLen(ByVal s As String) As UInt64
            If s = 0 Then
                StrLen = 0
                Exit Function
            End If

            Dim lenVal As UInt64 = 0
            While s(lenVal) <> 0
                lenVal = lenVal + 1
            Wend
            StrLen = lenVal
        End Function

        ''
        ' @brief Compares two null-terminated ASCII strings for exact byte-for-byte equality.
        ' @param s1 First string.
        ' @param s2 Second string.
        ' @return True if strings are byte-for-byte identical, False otherwise.
        ''
        Public Unsafe Function StrEquals(ByVal s1 As String, ByVal s2 As String) As Boolean
            If s1 = s2 Then
                StrEquals = True
                Exit Function
            End If

            If s1 = 0 Or s2 = 0 Then
                StrEquals = False
                Exit Function
            End If

            Dim i As UInt64 = 0
            While s1(i) <> 0 And s2(i) <> 0
                If s1(i) <> s2(i) Then
                    StrEquals = False
                    Exit Function
                End If
                i = i + 1
            Wend

            If s1(i) = 0 And s2(i) = 0 Then
                StrEquals = True
            Else
                StrEquals = False
            End If
        End Function

        ''
        ' @brief Appends null-terminated ASCII string into destination buffer at outIdx.
        '        Does not append trailing null terminator; caller controls string completion.
        ' @param s Source string to append.
        ' @param buf Pointer to destination buffer.
        ' @param outIdx Current index in destination buffer; updated to index after last appended byte.
        ''
        Public Unsafe Sub AppendStr(ByVal s As String, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
            If s = 0 Or buf = 0 Then Exit Sub

            Dim i As UInt32 = 0
            While s(i) <> 0
                buf(outIdx) = s(i)
                outIdx = outIdx + 1
                i = i + 1
            Wend
        End Sub

        ''
        ' @brief Formats an unsigned 64-bit integer as base-10 ASCII digits and appends to buffer.
        ' @param val Unsigned 64-bit integer value to format.
        ' @param buf Pointer to destination buffer.
        ' @param outIdx Current index in destination buffer; updated to index after last appended digit.
        ''
        Public Unsafe Sub AppendUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
            If buf = 0 Then Exit Sub

            If val = 0 Then
                buf(outIdx) = 48 ' '0'
                outIdx = outIdx + 1
                Exit Sub
            End If

            Dim tmp(24) As Byte
            Dim tIdx As UInt32 = 0
            Dim v As UInt64 = val

            While v > 0
                tmp(tIdx) = Byte((v Mod 10) + 48)
                v = v / 10
                tIdx = tIdx + 1
            Wend

            While tIdx > 0
                tIdx = tIdx - 1
                buf(outIdx) = tmp(tIdx)
                outIdx = outIdx + 1
            Wend
        End Sub

        ''
        ' @brief Formats an unsigned 64-bit integer as uppercase hexadecimal ASCII digits and appends to buffer.
        ' @param val Unsigned 64-bit integer value to format.
        ' @param buf Pointer to destination buffer.
        ' @param outIdx Current index in destination buffer; updated to index after last appended digit.
        ''
        Public Unsafe Sub AppendHex(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
            If buf = 0 Then Exit Sub

            If val = 0 Then
                buf(outIdx) = 48 ' '0'
                outIdx = outIdx + 1
                Exit Sub
            End If

            Dim tmp(20) As Byte
            Dim tIdx As UInt32 = 0
            Dim v As UInt64 = val

            While v > 0
                Dim digit As Byte = Byte(v And 15)
                If digit < 10 Then
                    tmp(tIdx) = digit + 48 ' '0'..'9'
                Else
                    tmp(tIdx) = digit + 55 ' 'A'..'F' (10 + 55 = 65 = 'A')
                End If
                v = v RShift 4
                tIdx = tIdx + 1
            Wend

            While tIdx > 0
                tIdx = tIdx - 1
                buf(outIdx) = tmp(tIdx)
                outIdx = outIdx + 1
            Wend
        End Sub

        ''
        ' @brief Strips leading and trailing whitespace characters (ASCII <= 32),
        '        writing result into outBuf with a terminating null byte.
        ' @param src Source null-terminated string.
        ' @param outBuf Pointer to destination buffer receiving trimmed string.
        ' @return Number of characters in trimmed string (excluding null terminator).
        ''
        Public Unsafe Function Trim(ByVal src As String, ByVal outBuf As Pointer To Byte) As UInt64
            If outBuf = 0 Then
                Trim = 0
                Exit Function
            End If

            If src = 0 Then
                outBuf(0) = 0
                Trim = 0
                Exit Function
            End If

            ' Find first non-whitespace character (ASCII > 32)
            Dim startIdx As UInt64 = 0
            While src(startIdx) <> 0 And src(startIdx) <= 32
                startIdx = startIdx + 1
            Wend

            ' If entire string was whitespace or empty
            If src(startIdx) = 0 Then
                outBuf(0) = 0
                Trim = 0
                Exit Function
            End If

            ' Find total length of src string starting from startIdx
            Dim totalLen As UInt64 = startIdx
            While src(totalLen) <> 0
                totalLen = totalLen + 1
            Wend

            ' Scan backward from end to find last non-whitespace character
            Dim endIdx As UInt64 = totalLen - 1
            While endIdx > startIdx And src(endIdx) <= 32
                endIdx = endIdx - 1
            Wend

            ' Copy trimmed span into outBuf
            Dim count As UInt64 = (endIdx - startIdx) + 1
            Dim i As UInt64 = 0
            While i < count
                outBuf(i) = src(startIdx + i)
                i = i + 1
            Wend
            outBuf(count) = 0

            Trim = count
        End Function

    End Module

End Namespace

