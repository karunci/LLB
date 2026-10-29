' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/stress_const_scoping/ExportConsts.bas
' Summary: Helper module providing 64-bit and 32-bit constants for cross-module import testing

Module ExportConsts

    Public Const EXP_HEX_MAX As UInt64 = &HFFFFFFFFFFFFFFFF
    Public Const EXP_DEC_MAX As UInt64 = 18446744073709551615
    Public Const EXP_INT_MAX As Int64 = 9223372036854775807
    Public Const EXP_INT_MIN As Int64 = -9223372036854775807 - 1
    Public Const EXP_NEG_TEN As Int32 = -10
    Public Const EXP_MAGIC_32 As UInt32 = &HDEADBEEF

    Public Function GetExpHexMax() As UInt64
        GetExpHexMax = EXP_HEX_MAX
    End Function

    Public Function GetExpIntMin() As Int64
        GetExpIntMin = EXP_INT_MIN
    End Function

End Module
