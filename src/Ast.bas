' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module Compiler.Ast

    ' Node Type Identifiers
    Public Const AST_MODULE As UInt32 = 1
    Public Const AST_CLASS As UInt32 = 2
    Public Const AST_PROCEDURE As UInt32 = 3
    Public Const AST_DIM_STMT As UInt32 = 4

    ' Represents type metadata
    Public Structure TypeDescriptor
        Public TypeName As Pointer To Byte
        Public IsPointer As Boolean
        Public IsVolatile As Boolean
    End Structure

    ' Token metadata representation
    Public Structure Token
        Public Kind As UInt32
        Public Offset As UInt64
        Public Length As UInt64
        Public LineNumber As UInt64
        Public ColumnNumber As UInt64
    End Structure

    ' Core AST Node structure layout
    Public Structure AstNode
        Public NodeType As UInt32
        Public SymbolName As Pointer To Byte
        Public ReturnType As TypeDescriptor
        Public IsUnsafe As Boolean
        Public IsPublic As Boolean
        Public MemberCount As UInt64
        Public Members As Pointer To Pointer To AstNode
    End Structure

    ' External memory allocator runtime hook
    Public Declare Function __llbc_allocate_instance Lib "c" (ByVal size As UInt64) As Pointer To Byte

    ' Allocates a new AST Node structure
    Public Unsafe Function CreateNode(ByVal nodeType As UInt32, ByVal name As Pointer To Byte) As Pointer To AstNode
        Dim node As Pointer To AstNode
        ' Low-level placement allocation using custom runtime memory hook
        node = *AstNode(__llbc_allocate_instance(64))
        node.NodeType = nodeType
        node.SymbolName = name
        node.MemberCount = 0
        node.Members = Nothing
        CreateNode = node
    End Function

End Module