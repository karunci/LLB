' Project Name: Personal Research Operating System / PROS CoreUtils - cat
' Filename: apps/cli/coreutils/cat/CatMain.bas
' Summary: Standalone Ring 3 concatenate, display, and hex-dump file utility.

Import "../../../../include/pros.bas"

Module CatMain

    Private Unsafe Function IsBinaryBuffer(ByVal buf As Pointer To Byte, ByVal len As UInt32) As Boolean
        Dim checkLen As UInt32 = len
        If checkLen > 512 Then checkLen = 512
        Dim i As UInt32
        For i = 0 To checkLen - 1
            Dim b As Byte = buf(i)
            If b = 0 Then
                IsBinaryBuffer = True
                Exit Function
            End If
            If b < 7 Or (b > 13 And b < 32) Then
                IsBinaryBuffer = True
                Exit Function
            End If
        Next i
        IsBinaryBuffer = False
    End Function

    Private Sub ByteToHex(ByVal b As Byte, ByVal out As Pointer To Byte)
        Dim hChars As String = "0123456789ABCDEF"
        out(0) = Byte(hChars((b RShift 4) And &H0F))
        out(1) = Byte(hChars(b And &H0F))
    End Sub

    Private Sub WordToHex(ByVal w As UInt16, ByVal out As Pointer To Byte)
        ByteToHex Byte((w RShift 8) And &HFF), out
        ByteToHex Byte(w And &HFF), out + 2
    End Sub

    Private Unsafe Sub DumpHex(ByVal buf As Pointer To Byte, ByVal len As UInt32)
        Dim maxDump As UInt32 = len
        If maxDump > 512 Then maxDump = 512

        ConsolePrintWithUInt "[CAT] Binary content detected (", UInt64(len), " bytes). Hex dump:\r\n"

        Dim rowBuf(80) As Byte
        Dim offset As UInt32 = 0

        While offset < maxDump
            Dim rLen As UInt32 = maxDump - offset
            If rLen > 16 Then rLen = 16

            ' Clear row buffer with spaces
            Dim c As UInt32
            For c = 0 To 79
                rowBuf(c) = 32
            Next c

            ' Offset 0000:
            WordToHex UInt16(offset And &HFFFF), @rowBuf(0)
            rowBuf(4) = 58 ' ':'
            rowBuf(5) = 32 ' ' '

            ' Hex bytes
            Dim bIdx As UInt32
            For bIdx = 0 To rLen - 1
                Dim colOffset As UInt32 = 6 + (bIdx * 3)
                If bIdx >= 8 Then colOffset = colOffset + 1
                ByteToHex buf(offset + bIdx), @rowBuf(colOffset)
            Next bIdx

            ' ASCII representation
            Dim asciiStart As UInt32 = 57
            rowBuf(asciiStart) = 124 ' '|'
            For bIdx = 0 To rLen - 1
                Dim ch As Byte = buf(offset + bIdx)
                If ch >= 32 And ch <= 126 Then
                    rowBuf(asciiStart + 1 + bIdx) = ch
                Else
                    rowBuf(asciiStart + 1 + bIdx) = 46 ' '.'
                End If
            Next bIdx
            rowBuf(asciiStart + 1 + rLen) = 124 ' '|'
            rowBuf(asciiStart + 2 + rLen) = 0

            ConsoleWriteLine @rowBuf(0)
            offset = offset + 16
        Wend

        If len > maxDump Then
            ConsolePrintWithUInt "[CAT] ... (remaining ", UInt64(len - maxDump), " bytes omitted)\r\n"
        End If
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        If argc < 2 Or argv(1) = 0 Then
            ConsoleWriteLine "Usage: cat <path>"
            user_main = 1
            Exit Function
        End If

        Dim argPath As Pointer To Byte = argv(1)
        Dim resolvedPath(160) As Byte

        ' Path canonicalization fallback if not absolute
        Dim hasColon As Boolean = False
        Dim pIdx As UInt32 = 0
        While argPath(pIdx) <> 0
            If argPath(pIdx) = 58 Then hasColon = True ' ':'
            pIdx = pIdx + 1
        Wend

        If hasColon Or argPath(0) = 92 Or argPath(0) = 47 Then
            StrCopy @resolvedPath(0), 160, argPath
        Else
            resolvedPath(0) = 88 ' 'X'
            resolvedPath(1) = 58 ' ':'
            resolvedPath(2) = 92 ' '\'
            resolvedPath(3) = 0
            StrCopy @resolvedPath(3), 156, argPath
        End If

        Dim buf(65536) As Byte
        Dim bytesRead As UInt32 = ReadAllText(@resolvedPath(0), @buf(0), 65535)

        If bytesRead > 0 Then
            If IsBinaryBuffer(@buf(0), bytesRead) Then
                DumpHex @buf(0), bytesRead
            Else
                buf(bytesRead) = 0
                ConsoleWrite @buf(0)
            End If
        Else
            ConsoleWriteLine "cat: file not found or empty"
        End If

        user_main = 0
    End Function

End Module
