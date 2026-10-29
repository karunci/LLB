' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestI128Cmp.bas
' Summary: Test 64-bit mixed signed/unsigned comparison.

Module TestI128Cmp

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        Dim s64Neg As Int64 = -1
        Dim u64Pos As UInt64 = 100

        If s64Neg < u64Pos Then
            puts CPtr(Pointer To Byte, "[PASS] Int64(-1) < UInt64(100)")
        Else
            puts CPtr(Pointer To Byte, "[FAIL] Int64(-1) < UInt64(100)")
            Main = 1
            Exit Function
        End If

        Dim u64Large As UInt64 = UInt64(&HFFFFFFFFFFFFFFFF)
        If s64Neg < u64Large Then
            puts CPtr(Pointer To Byte, "[PASS] Int64(-1) < UInt64::Max")
        Else
            puts CPtr(Pointer To Byte, "[FAIL] Int64(-1) < UInt64::Max")
            Main = 1
            Exit Function
        End If

        If s64Neg = u64Large Then
            puts CPtr(Pointer To Byte, "[FAIL] Int64(-1) should NOT equal UInt64::Max")
            Main = 1
            Exit Function
        Else
            puts CPtr(Pointer To Byte, "[PASS] Int64(-1) <> UInt64::Max")
        End If

        Main = 0
    End Function

End Module
