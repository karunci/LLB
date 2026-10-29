' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

<Instancing(MultiUse)>
Class Compiler.Lexer

    Import Compiler.Ast

    Private sourceBuffer As Pointer To Byte
    Private bufferLength As UInt64
    Private cursorPosition As UInt64
    Private currentLine As UInt64
    Private currentColumn As UInt64

    ' Initialize scanner context over freestanding memory buffer
    Public Sub Initialize(ByVal buffer As Pointer To Byte, ByVal length As UInt64)
        Me.sourceBuffer = buffer
        Me.bufferLength = length
        Me.cursorPosition = 0
        Me.currentLine = 1
        Me.currentColumn = 1
    End Sub

    ' Peek current ASCII byte
    Private Function PeekByte() As Byte
        If Me.cursorPosition >= Me.bufferLength Then
            PeekByte = 0
        Else
            PeekByte = Me.sourceBuffer(Me.cursorPosition)
        End If
    End Function

    ' Advance stream cursor by 1 byte
    Private Function AdvanceByte() As Byte
        If Me.cursorPosition >= Me.bufferLength Then
            AdvanceByte = 0
            Exit Function
        End If

        Dim b As Byte
        b = Me.sourceBuffer(Me.cursorPosition)
        Me.cursorPosition = Me.cursorPosition + 1

        If b = 10 Then ' Line Feed (\n)
            Me.currentLine = Me.currentLine + 1
            Me.currentColumn = 1
        Else
            Me.currentColumn = Me.currentColumn + 1
        End If

        AdvanceByte = b
    End Function

    ' Skip comments and whitespace characters
    Private Sub SkipIgnored()
        Dim b As Byte
        Do While Me.cursorPosition < Me.bufferLength
            b = Me.PeekByte()
            ' Space, Tab, CR, LF
            If b = 32 Or b = 9 Or b = 13 Or b = 10 Then
                Me.AdvanceByte
            ' Single Quote Comment (')
            ElseIf b = 39 Then
                Do While Me.cursorPosition < Me.bufferLength And Me.PeekByte() <> 10
                    Me.AdvanceByte
                Loop
            Else
                Exit Sub
            End If
        Loop
    End Sub

    ' Scan and return next token in source stream
    Public Function ScanNext() As Token
        Me.SkipIgnored

        Dim tok As Token
        tok.Offset = Me.cursorPosition
        tok.LineNumber = Me.currentLine
        tok.ColumnNumber = Me.currentColumn

        If Me.cursorPosition >= Me.bufferLength Then
            tok.Kind = 0 ' EOF
            tok.Length = 0
            ScanNext = tok
            Exit Function
        End If

        Dim charByte As Byte
        charByte = Me.AdvanceByte()

        ' Identifiers & Keywords: [A-Z, a-z, _]
        If (charByte >= 65 And charByte <= 90) Or (charByte >= 97 And charByte <= 122) Or charByte = 95 Then
            Do While Me.cursorPosition < Me.bufferLength
                Dim nextByte As Byte
                nextByte = Me.PeekByte()
                If (nextByte >= 65 And nextByte <= 90) Or _
                   (nextByte >= 97 And nextByte <= 122) Or _
                   (nextByte >= 48 And nextByte <= 57) Or _
                   nextByte = 95 Then
                    Me.AdvanceByte
                Else
                    Exit Do
                End If
            Loop
            tok.Kind = 1 ' Identifier / Keyword
            tok.Length = Me.cursorPosition - tok.Offset
            ScanNext = tok
            Exit Function
        End If

        ' Numeric Literals: [0-9]
        If charByte >= 48 And charByte <= 57 Then
            Do While Me.cursorPosition < Me.bufferLength
                Dim numByte As Byte
                numByte = Me.PeekByte()
                If numByte >= 48 And numByte <= 57 Then
                    Me.AdvanceByte
                Else
                    Exit Do
                End If
            Loop
            tok.Kind = 2 ' Numeric Literal
            tok.Length = Me.cursorPosition - tok.Offset
            ScanNext = tok
            Exit Function
        End If

        ' Operators & Single Character Symbols
        tok.Kind = UInt32(charByte)
        tok.Length = 1
        ScanNext = tok
    End Function

End Class