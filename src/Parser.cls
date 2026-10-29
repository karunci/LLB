' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

<Instancing(MultiUse)>
Class Compiler.Parser

    Use Compiler.Lexer
    Import Compiler.Ast

    Private lexerInstance As Pointer To Lexer
    Private currentToken As Token

    Public Sub Initialize(ByVal lexer As Pointer To Lexer)
        Me.lexerInstance = lexer
        Me.Advance
    End Sub

    Private Sub Advance()
        Me.currentToken = Me.lexerInstance.ScanNext()
    End Sub

    Public Unsafe Function ParseModule() As Pointer To AstNode
        ' Expect 'Module' or 'Class' keyword token
        If Me.currentToken.Kind <> 1 Then
            ParseModule = Nothing
            Exit Function
        End If

        Dim moduleNode As Pointer To AstNode
        moduleNode = CreateNode(AST_MODULE, *Byte(Me.currentToken.Offset))
        
        Me.Advance

        ' Parse declarations within the module
        Do While Me.currentToken.Kind <> 0
            ' Check for 'End Module' or 'End Class'
            If Me.currentToken.Kind = 1 Then
                ' Processing top-level functions and subroutines
                Dim procNode As Pointer To AstNode
                procNode = Me.ParseProcedure()
                If UInt64(procNode) <> 0 Then
                    ' Attach child procedure to module AST node
                    moduleNode.MemberCount = moduleNode.MemberCount + 1
                End If
            Else
                Me.Advance
            End If
        Loop

        ParseModule = moduleNode
    End Function

    Private Unsafe Function ParseProcedure() As Pointer To AstNode
        Dim procNode As Pointer To AstNode
        procNode = CreateNode(AST_PROCEDURE, *Byte(Me.currentToken.Offset))

        ' Consume Procedure Signature and Body
        Do While Me.currentToken.Kind <> 0
            If Me.currentToken.Kind = 1 Then
                ' Check for 'End Sub' / 'End Function' boundary
                Me.Advance
                Exit Do
            End If
            Me.Advance
        Loop

        ParseProcedure = procNode
    End Function

End Class