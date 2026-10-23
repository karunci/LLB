' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/Format.bas
' Summary: Low-level numeric and string formatting routines for hosted runtime.

Module Format

    ''
    ' @brief Formats an unsigned 64-bit integer into a hexadecimal ASCII string in a caller buffer.
    ' @param value Unsigned 64-bit value to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 19 bytes).
    ' @param prefix True to prepend "0x".
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToHex(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
        Dim pos As UInt32 = 0
        If prefix Then
            outBuf(pos) = 48 ' '0'
            pos = pos + 1
            outBuf(pos) = 120 ' 'x'
            pos = pos + 1
        End If

        If value = 0 Then
            outBuf(pos) = 48
            pos = pos + 1
            outBuf(pos) = 0
            ToHex = pos
            Exit Function
        End If

        Dim digits As Pointer To Byte = CPtr(Pointer To Byte, "0123456789ABCDEF")
        Dim temp(16) As Byte
        Dim tempPos As Int32 = 0

        Do While value > 0
            temp(tempPos) = digits(CType(Byte, value And CType(UInt64, 15)))
            value = value RShift 4
            tempPos = tempPos + 1
        Loop

        Dim i As Int32
        For i = tempPos - 1 To 0 Step -1
            outBuf(pos) = temp(i)
            pos = pos + 1
        Next i

        outBuf(pos) = 0
        ToHex = pos
    End Function

    ''
    ' @brief Formats an unsigned 64-bit integer into a base-10 decimal ASCII string.
    ' @param value Unsigned 64-bit integer to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 21 bytes).
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToUInt(ByVal value As UInt64, ByVal outBuf As Pointer To Byte) As UInt32
        Dim pos As UInt32 = 0
        If value = 0 Then
            outBuf(0) = 48 ' '0'
            outBuf(1) = 0
            ToUInt = 1
            Exit Function
        End If

        Dim temp(20) As Byte
        Dim tempPos As Int32 = 0

        Do While value > 0
            Dim remDigit As UInt64 = value Mod CType(UInt64, 10)
            temp(tempPos) = CType(Byte, 48 + remDigit)
            value = value / CType(UInt64, 10)
            tempPos = tempPos + 1
        Loop

        Dim i As Int32
        For i = tempPos - 1 To 0 Step -1
            outBuf(pos) = temp(i)
            pos = pos + 1
        Next i

        outBuf(pos) = 0
        ToUInt = pos
    End Function

    ''
    ' @brief Formats a signed 64-bit integer into a base-10 decimal ASCII string.
    ' @param value Signed 64-bit integer to convert.
    ' @param outBuf Pointer to destination buffer (must be at least 22 bytes).
    ' @return Number of characters written (excluding null terminator).
    ''
    Public Unsafe Function ToInt(ByVal value As Int64, ByVal outBuf As Pointer To Byte) As UInt32
        Dim pos As UInt32 = 0
        If value < 0 Then
            outBuf(0) = 45 ' '-'
            pos = 1
            Dim uval As UInt64 = CType(UInt64, 0 - value)
            pos = pos + ToUInt(uval, outBuf + pos)
            ToInt = pos
            Exit Function
        End If

        ToInt = ToUInt(CType(UInt64, value), outBuf)
    End Function

    ''
    ' @brief Formats arguments into a caller buffer according to a format string (snprintf/vsprintf equivalent).
    ' @param outBuf Pointer to destination buffer.
    ' @param maxLen Maximum bytes available in destination buffer.
    ' @param fmt Pointer to null-terminated format string (%s, %u, %d, %x, %c, %%).
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
        Dim tmpBuf(32) As Byte
        Dim tmpPtr As Pointer To Byte = CPtr(Pointer To Byte, tmpBuf)
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
                ElseIf spec = 115 Then ' '%s'
                    Dim strArg As Pointer To Byte = CPtr(Pointer To Byte, args(argIdx))
                    argIdx = argIdx + 1
                    If strArg = 0 Then
                        strArg = CPtr(Pointer To Byte, "(null)")
                    End If
                    Dim sIdx As UInt64 = 0
                    Do While strArg(sIdx) <> 0 And outPos < (maxLen - 1)
                        outBuf(outPos) = strArg(sIdx)
                        outPos = outPos + 1
                        sIdx = sIdx + 1
                    Loop
                ElseIf spec = 117 Then ' '%u'
                    Dim uval As UInt64 = CType(UInt64, args(argIdx))
                    argIdx = argIdx + 1
                    tmpLen = ToUInt(uval, tmpPtr)
                    tmpIdx = 0
                    Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                        outBuf(outPos) = tmpBuf(tmpIdx)
                        outPos = outPos + 1
                        tmpIdx = tmpIdx + 1
                    Loop
                ElseIf spec = 100 Or spec = 105 Then ' '%d', '%i'
                    Dim ival As Int64 = args(argIdx)
                    argIdx = argIdx + 1
                    tmpLen = ToInt(ival, tmpPtr)
                    tmpIdx = 0
                    Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                        outBuf(outPos) = tmpBuf(tmpIdx)
                        outPos = outPos + 1
                        tmpIdx = tmpIdx + 1
                    Loop
                ElseIf spec = 120 Or spec = 88 Then ' '%x', '%X'
                    Dim xval As UInt64 = CType(UInt64, args(argIdx))
                    argIdx = argIdx + 1
                    tmpLen = ToHex(xval, tmpPtr, False)
                    tmpIdx = 0
                    Do While tmpIdx < tmpLen And outPos < (maxLen - 1)
                        outBuf(outPos) = tmpBuf(tmpIdx)
                        outPos = outPos + 1
                        tmpIdx = tmpIdx + 1
                    Loop
                ElseIf spec = 99 Then ' '%c'
                    Dim cval As Byte = CType(Byte, args(argIdx) And 255)
                    argIdx = argIdx + 1
                    outBuf(outPos) = cval
                    outPos = outPos + 1
                Else
                    ' Unknown specifier: emit verbatim
                    outBuf(outPos) = 37
                    outPos = outPos + 1
                    If outPos < (maxLen - 1) Then
                        outBuf(outPos) = spec
                        outPos = outPos + 1
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
