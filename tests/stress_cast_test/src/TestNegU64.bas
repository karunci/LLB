' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestNegU64.bas
' Summary: Test UInt64 cast on negative signed integer.

Module TestNegU64

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        Dim s32Neg As Int32 = -5
        Dim u64Val As UInt64 = UInt64(s32Neg)

        ' If zero-extended: u64Val = 0x00000000FFFFFFFB = 4294967291
        ' If sign-extended: u64Val = 0xFFFFFFFFFFFFFFFB = 18446744073709551611
        If u64Val = UInt64(&HFFFFFFFFFFFFFFFB) Then
            puts CPtr(Pointer To Byte, "[INFO] UInt64(s32Neg) preserves 64-bit two's complement sign (sign-extended)")
        ElseIf u64Val = UInt64(&HFFFFFFFB) Then
            puts CPtr(Pointer To Byte, "[INFO] UInt64(s32Neg) zero-extended lower 32 bits")
        Else
            puts CPtr(Pointer To Byte, "[FAIL] Unexpected value")
        End If

        Main = 0
    End Function

End Module
