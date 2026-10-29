' Project Name: LibLLB_Metal / Low-Level Basic
' Filename: lib/metal/src/Format.bas
' Summary: Low-level numeric and string formatting routines (zero dynamic allocation).

Module Format

    ''
    ' @brief Formats an unsigned 64-bit integer into a hexadecimal ASCII string in a caller buffer.
    ' @param value Unsigned 64-bit value to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 26 bytes).
    ' @param prefix True to prepend "0x".
    ' @param uppercase True for uppercase (ABCDEF), False for lowercase (abcdef).
    ' @param minWidth Minimum digits to emit; zero-padded if length is less.
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToHexEx(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean, ByVal uppercase As Boolean, ByVal minWidth As UInt32) As UInt32
        Dim pos As UInt32 = 0
        If prefix Then
            outBuf(pos) = 48 ' '0'
            pos = pos + 1
            outBuf(pos) = 120 ' 'x'
            pos = pos + 1
        End If

        Dim digitsUpper As Pointer To Byte = "0123456789ABCDEF"
        Dim digitsLower As Pointer To Byte = "0123456789abcdef"
        Dim digits As Pointer To Byte = digitsLower
        If uppercase Then
            digits = digitsUpper
        End If

        Dim temp(24) As Byte
        Dim tempPos As Int32 = 0

        If value = 0 Then
            temp(0) = 48 ' '0'
            tempPos = 1
        Else
            Do While value > 0
                temp(tempPos) = digits(Byte(value And UInt64(15)))
                value = value RShift 4
                tempPos = tempPos + 1
            Loop
        End If

        ' Apply zero padding if minWidth > tempPos
        Do While UInt32(tempPos) < minWidth And tempPos < 20
            temp(tempPos) = 48 ' '0'
            tempPos = tempPos + 1
        Loop

        Dim i As Int32
        For i = tempPos - 1 To 0 Step -1
            outBuf(pos) = temp(i)
            pos = pos + 1
        Next i

        outBuf(pos) = 0
        ToHexEx = pos
    End Function

    ''
    ' @brief Classic ToHex wrapper for uppercase hex with optional prefix.
    ''
    Public Unsafe Function ToHex(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
        ToHex = ToHexEx(value, outBuf, prefix, True, 0)
    End Function

    ''
    ' @brief Formats an unsigned 64-bit integer into a base-10 decimal ASCII string with optional zero padding.
    ' @param value Unsigned 64-bit integer to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 24 bytes).
    ' @param minWidth Minimum digits to emit; zero-padded if length is less.
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToUIntEx(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal minWidth As UInt32) As UInt32
        Dim pos As UInt32 = 0
        Dim temp(24) As Byte
        Dim tempPos As Int32 = 0

        If value = 0 Then
            temp(0) = 48 ' '0'
            tempPos = 1
        Else
            Do While value > 0
                Dim remDigit As UInt64 = value Mod UInt64(10)
                temp(tempPos) = Byte(48 + remDigit)
                value = value / UInt64(10)
                tempPos = tempPos + 1
            Loop
        End If

        ' Apply zero padding
        Do While UInt32(tempPos) < minWidth And tempPos < 22
            temp(tempPos) = 48 ' '0'
            tempPos = tempPos + 1
        Loop

        Dim i As Int32
        For i = tempPos - 1 To 0 Step -1
            outBuf(pos) = temp(i)
            pos = pos + 1
        Next i

        outBuf(pos) = 0
        ToUIntEx = pos
    End Function

    ''
    ' @brief Classic ToUInt without padding.
    ''
    Public Unsafe Function ToUInt(ByVal value As UInt64, ByVal outBuf As Pointer To Byte) As UInt32
        ToUInt = ToUIntEx(value, outBuf, 0)
    End Function

    ''
    ' @brief Formats a signed 64-bit integer into a base-10 decimal ASCII string with optional zero padding.
    ' @param value Signed 64-bit integer to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 26 bytes).
    ' @param minWidth Minimum digits to emit; zero-padded if length is less.
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToIntEx(ByVal value As Int64, ByVal outBuf As Pointer To Byte, ByVal minWidth As UInt32) As UInt32
        Dim pos As UInt32 = 0
        If value < 0 Then
            outBuf(0) = 45 ' '-'
            pos = 1
            Dim uval As UInt64 = UInt64(0 - value)
            pos = pos + ToUIntEx(uval, outBuf + pos, minWidth)
            ToIntEx = pos
            Exit Function
        End If

        ToIntEx = ToUIntEx(UInt64(value), outBuf, minWidth)
    End Function

    ''
    ' @brief Classic ToInt without padding.
    ''
    Public Unsafe Function ToInt(ByVal value As Int64, ByVal outBuf As Pointer To Byte) As UInt32
        ToInt = ToIntEx(value, outBuf, 0)
    End Function

    ''
    ' @brief Formats an unsigned 64-bit integer into a base-2 binary ASCII string.
    ' @param value Unsigned 64-bit value to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 70 bytes).
    ' @param prefix True to prepend "0b".
    ' @param minWidth Minimum bits to emit; zero-padded if length is less.
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToBinary(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean, ByVal minWidth As UInt32) As UInt32
        Dim pos As UInt32 = 0
        If prefix Then
            outBuf(pos) = 48 ' '0'
            pos = pos + 1
            outBuf(pos) = 98 ' 'b'
            pos = pos + 1
        End If

        Dim temp(66) As Byte
        Dim tempPos As Int32 = 0

        If value = 0 Then
            temp(0) = 48 ' '0'
            tempPos = 1
        Else
            Do While value > 0
                temp(tempPos) = Byte(48 + (value And UInt64(1)))
                value = value RShift 1
                tempPos = tempPos + 1
            Loop
        End If

        ' Apply zero padding
        Do While UInt32(tempPos) < minWidth And tempPos < 64
            temp(tempPos) = 48 ' '0'
            tempPos = tempPos + 1
        Loop

        Dim i As Int32
        For i = tempPos - 1 To 0 Step -1
            outBuf(pos) = temp(i)
            pos = pos + 1
        Next i

        outBuf(pos) = 0
        ToBinary = pos
    End Function

    ''
    ' @brief Formats arguments into a caller buffer according to a format string (snprintf equivalent).
    ' @param outBuf Pointer to destination buffer.
    ' @param maxLen Maximum bytes available in destination buffer.
    ' @param fmt Pointer to null-terminated format string (%s, %u, %d, %x, %X, %p, %b, %c, %%).
    ' @param args Variadic format arguments.
    ' @return Total characters written to outBuf (excluding null terminator).
    ''
    Public Unsafe Function SprintF(ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
        If outBuf = 0 Or maxLen = 0 Then
            SprintF = 0
            Exit Function
        End If

        Dim outPos As UInt32 = 0
        Dim fmtPos As UInt32 = 0
        Dim argIdx As Int32 = 0
        Dim tmpBuf(68) As Byte
        Dim tmpPtr As Pointer To Byte = tmpBuf
        Dim tmpLen As UInt32 = 0
        Dim tmpIdx As UInt32 = 0

        Do While fmt(fmtPos) <> 0 And outPos < (maxLen - 1)
            If fmt(fmtPos) = 37 Then ' '%'
                fmtPos = fmtPos + 1
                Dim spec As Byte = fmt(fmtPos)
                If spec = 0 Then Exit Do

                If spec = 37 Then ' '%%'
                    outBuf(outPos) = 37
                    outPos = outPos + 1
                Else
                    ' Parse flags: '-' (left-align), '0' (zero-pad)
                    Dim leftAlign As Boolean = False
                    Dim zeroPad As Boolean = False
                    Do While spec = 45 Or spec = 48 ' '-' = 45, '0' = 48
                        If spec = 45 Then leftAlign = True
                        If spec = 48 Then zeroPad = True
                        fmtPos = fmtPos + 1
                        spec = fmt(fmtPos)
                    Loop

                    ' Parse minimum field width
                    Dim minWidth As UInt32 = 0
                    Do While spec >= 48 And spec <= 57 ' '0'..'9'
                        minWidth = (minWidth * 10) + UInt32(spec - 48)
                        fmtPos = fmtPos + 1
                        spec = fmt(fmtPos)
                    Loop

                    ' Skip length modifiers ('l', 'L', 'h', 'z')
                    Dim isLong As Boolean = False
                    Do While spec = 108 Or spec = 76 Or spec = 104 Or spec = 122
                        isLong = True
                        fmtPos = fmtPos + 1
                        spec = fmt(fmtPos)
                        If spec = 0 Then Exit Do
                    Loop
                    If spec = 0 Then Exit Do

                    If spec = 115 Then ' '%s'
                        Dim strArg As Pointer To Byte = *Byte(args(argIdx))
                        argIdx = argIdx + 1
                        If strArg = 0 Then
                            strArg = "(null)"
                        End If
                        Dim sLen As UInt32 = 0
                        Do While strArg(sLen) <> 0
                            sLen = sLen + 1
                        Loop

                        ' Right-align padding (if not left-aligned)
                        If Not leftAlign And minWidth > sLen Then
                            Dim padCount As UInt32 = minWidth - sLen
                            Dim p As UInt32
                            For p = 0 To padCount - 1
                                If outPos < (maxLen - 1) Then
                                    outBuf(outPos) = 32 ' ' '
                                    outPos = outPos + 1
                                End If
                            Next p
                        End If

                        ' Copy string characters
                        Dim sIdx As UInt32 = 0
                        Do While sIdx < sLen And outPos < (maxLen - 1)
                            outBuf(outPos) = strArg(sIdx)
                            outPos = outPos + 1
                            sIdx = sIdx + 1
                        Loop

                        ' Left-align padding
                        If leftAlign And minWidth > sLen Then
                            Dim padCountL As UInt32 = minWidth - sLen
                            Dim pL As UInt32
                            For pL = 0 To padCountL - 1
                                If outPos < (maxLen - 1) Then
                                    outBuf(outPos) = 32 ' ' '
                                    outPos = outPos + 1
                                End If
                            Next pL
                        End If

                    ElseIf spec = 117 Then ' '%u'
                        Dim uval As UInt64 = UInt64(args(argIdx))
                        argIdx = argIdx + 1
                        Dim padWidth As UInt32 = 0
                        If zeroPad Then padWidth = minWidth
                        tmpLen = ToUIntEx(uval, tmpPtr, padWidth)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 100 Or spec = 105 Then ' '%d', '%i'
                        Dim ival As Int64 = Int64(args(argIdx))
                        argIdx = argIdx + 1
                        Dim padWidthD As UInt32 = 0
                        If zeroPad Then padWidthD = minWidth
                        tmpLen = ToIntEx(ival, tmpPtr, padWidthD)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 120 Then ' '%x' (lowercase)
                        Dim xval As UInt64 = UInt64(args(argIdx))
                        argIdx = argIdx + 1
                        Dim padWidthX As UInt32 = 0
                        If zeroPad Then padWidthX = minWidth
                        tmpLen = ToHexEx(xval, tmpPtr, False, False, padWidthX)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 88 Then ' '%X' (uppercase)
                        Dim xvalU As UInt64 = UInt64(args(argIdx))
                        argIdx = argIdx + 1
                        Dim padWidthXU As UInt32 = 0
                        If zeroPad Then padWidthXU = minWidth
                        tmpLen = ToHexEx(xvalU, tmpPtr, False, True, padWidthXU)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 112 Then ' '%p' (pointer 0x...)
                        Dim pval As UInt64 = UInt64(args(argIdx))
                        argIdx = argIdx + 1
                        tmpLen = ToHexEx(pval, tmpPtr, True, False, 16)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 98 Then ' '%b' (binary)
                        Dim bval As UInt64 = UInt64(args(argIdx))
                        argIdx = argIdx + 1
                        Dim padWidthB As UInt32 = 0
                        If zeroPad Then padWidthB = minWidth
                        tmpLen = ToBinary(bval, tmpPtr, False, padWidthB)
                        tmpIdx = 0
                        Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                            outBuf(outPos) = tmpBuf(tmpIdx)
                            outPos = outPos + 1
                            tmpIdx = tmpIdx + 1
                        Loop

                    ElseIf spec = 99 Then ' '%c'
                        Dim cval As Byte = Byte(UInt64(args(argIdx)) And UInt64(255))
                        argIdx = argIdx + 1
                        outBuf(outPos) = cval
                        outPos = outPos + 1

                    Else
                        ' Unknown specifier: emit verbatim '%' + spec
                        outBuf(outPos) = 37
                        outPos = outPos + 1
                        If outPos < (maxLen - 1) Then
                            outBuf(outPos) = spec
                            outPos = outPos + 1
                        End If
                    End If
                End If
                fmtPos = fmtPos + 1
            Else
                outBuf(outPos) = fmt(fmtPos)
                outPos = outPos + 1
                fmtPos = fmtPos + 1
            End If
        Loop

        outBuf(outPos) = 0
        SprintF = outPos
    End Function

End Module
