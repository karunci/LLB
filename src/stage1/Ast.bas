' Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
' Filename: src/stage1/Ast.bas
' Summary: Type definitions for Abstract Syntax Tree structures in Stage-1.

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

    ' Allocates a new AST Node structure
    Public Unsafe Function CreateNode(ByVal nodeType As UInt32, ByVal name As Pointer To Byte) As Pointer To AstNode
        Dim node As Pointer To AstNode
        ' Low-level placement allocation using custom runtime memory hook
        node = CPtr(Pointer To AstNode, __llbc_allocate_instance(64))
        node.NodeType = nodeType
        node.SymbolName = name
        node.MemberCount = 0
        node.Members = CPtr(Pointer To Pointer To AstNode, 0)
        CreateNode = node
    End Function

End Module