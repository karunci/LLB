' Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
' Filename: src/stage1/Parser.cls
' Summary: Stage-1 Recursive Descent Parser translating tokens to AST nodes.

Class Compiler.Parser

    Import Compiler.Lexer
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
            ParseModule = CPtr(Pointer To AstNode, 0)
            Exit Function
        End If

        Dim moduleNode As Pointer To AstNode
        moduleNode = CreateNode(AST_MODULE, CPtr(Pointer To Byte, Me.currentToken.Offset))
        
        Me.Advance

        ' Parse declarations within the module
        Do While Me.currentToken.Kind <> 0
            ' Check for 'End Module' or 'End Class'
            If Me.currentToken.Kind = 1 Then
                ' Processing top-level functions and subroutines
                Dim procNode As Pointer To AstNode
                procNode = Me.ParseProcedure()
                If CPtr(UInt64, procNode) <> 0 Then
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
        procNode = CreateNode(AST_PROCEDURE, CPtr(Pointer To Byte, Me.currentToken.Offset))

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