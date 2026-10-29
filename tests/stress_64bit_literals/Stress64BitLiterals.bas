' Project Name: Low-Level Basic / Empirical 64-Bit Literal Stress Test
' Filename: tests/stress_64bit_literals/Stress64BitLiterals.bas
' Summary: Exhaustive empirical verification of 64-bit integer literal parsing,
'          bit-pattern retention, codegen widening, and mixed comparisons.

Module Stress64BitLiterals

    Public Declare Function puts Lib "c" Alias "puts" (ByVal s As Pointer To Byte) As Int32

    Dim g_failures As Int32 = 0
    Dim g_testsRun As Int32 = 0

    Public Sub AssertTrue(ByVal cond As Boolean, ByVal name As Pointer To Byte)
        g_testsRun = g_testsRun + 1
        If cond Then
            ' PASS
        Else
            puts CPtr(Pointer To Byte, "  [FAIL] Assertion failed:")
            puts name
            g_failures = g_failures + 1
        End If
    End Sub

    Public Sub AssertFalse(ByVal cond As Boolean, ByVal name As Pointer To Byte)
        AssertTrue(Not cond, name)
    End Sub

    Public Function TakeU64(ByVal x As UInt64) As UInt64
        TakeU64 = x
    End Function

    Public Function TakeS64(ByVal x As Int64) As Int64
        TakeS64 = x
    End Function

    ' Constants declared at module level
    Const K_DEC_MAX As UInt64 = 18446744073709551615
    Const K_HEX_MAX As UInt64 = &HFFFFFFFFFFFFFFFF
    Const K_INT64_MAX As Int64 = 9223372036854775807
    Const K_HEX_MID As UInt64 = &H123456789ABCDEF0

    ' --- Suite 1: Hex 64-Bit Literal Retention (&HFFFFFFFFFFFFFFFF) ---
    Public Sub TestHex64BitRetention()
        puts CPtr(Pointer To Byte, "[Suite 1] Hex 64-Bit Literal Retention (&HFFFFFFFFFFFFFFFF)")

        Dim u As UInt64 = &HFFFFFFFFFFFFFFFF

        ' 1.1 Non-truncation to 32 bits
        AssertFalse(u = 4294967295, CPtr(Pointer To Byte, "u <> 4294967295 (not truncated to 32-bit)"))
        AssertTrue(u <> 4294967295, CPtr(Pointer To Byte, "u <> 4294967295"))
        AssertTrue(u > 4294967295, CPtr(Pointer To Byte, "u > 4294967295"))

        ' 1.2 Exact value equivalence with decimal max and hex literal
        AssertTrue(u = &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "u = &HFFFFFFFFFFFFFFFF"))
        AssertTrue(u = 18446744073709551615, CPtr(Pointer To Byte, "u = 18446744073709551615"))

        ' 1.3 High bits retention (all upper 32 bits must be 0xFFFFFFFF)
        Dim high32 As UInt64 = u RShift 32
        AssertTrue(high32 = 4294967295, CPtr(Pointer To Byte, "(u RShift 32) = 4294967295"))
        AssertTrue(high32 = &HFFFFFFFF, CPtr(Pointer To Byte, "(u RShift 32) = &HFFFFFFFF"))

        Dim msb As UInt64 = u RShift 63
        AssertTrue(msb = 1, CPtr(Pointer To Byte, "(u RShift 63) = 1"))

        ' 1.4 Bitwise mask on high half
        Dim maskedHigh As UInt64 = u And &HFFFFFFFF00000000
        AssertTrue(maskedHigh = &HFFFFFFFF00000000, CPtr(Pointer To Byte, "(u And &HFFFFFFFF00000000) matches"))

        ' 1.5 Arithmetic on 64-bit maximum
        Dim uMinusOne As UInt64 = u - 1
        AssertTrue(uMinusOne = &HFFFFFFFFFFFFFFFE, CPtr(Pointer To Byte, "u - 1 = &HFFFFFFFFFFFFFFFE"))
        AssertTrue(uMinusOne = 18446744073709551614, CPtr(Pointer To Byte, "u - 1 = 18446744073709551614"))

        Dim uPlusOne As UInt64 = u + 1
        AssertTrue(uPlusOne = 0, CPtr(Pointer To Byte, "u + 1 = 0 (unsigned wrap)"))

        ' 1.6 Passing to function accepting UInt64
        AssertTrue(TakeU64(&HFFFFFFFFFFFFFFFF) = u, CPtr(Pointer To Byte, "TakeU64(&HFFFFFFFFFFFFFFFF) = u"))

        ' 1.7 Other 64-bit hex patterns
        Dim hexMid As UInt64 = &H123456789ABCDEF0
        AssertTrue((hexMid RShift 32) = &H12345678, CPtr(Pointer To Byte, "(&H123456789ABCDEF0 RShift 32) = &H12345678"))
        AssertTrue((hexMid And &HFFFFFFFF) = &H9ABCDEF0, CPtr(Pointer To Byte, "(&H123456789ABCDEF0 And &HFFFFFFFF) = &H9ABCDEF0"))

        Dim hexFirst64 As UInt64 = &H100000000
        AssertTrue(hexFirst64 = 4294967296, CPtr(Pointer To Byte, "&H100000000 = 4294967296 (2^32)"))
        AssertTrue(hexFirst64 > 4294967295, CPtr(Pointer To Byte, "&H100000000 > 4294967295"))
    End Sub

    ' --- Suite 2: Decimal 64-Bit Literal Non-Collapse (18446744073709551615) ---
    Public Sub TestDec64BitNonCollapse()
        puts CPtr(Pointer To Byte, "[Suite 2] Decimal 64-Bit Literal Non-Collapse (18446744073709551615)")

        Dim d As UInt64 = 18446744073709551615

        ' 2.1 Non-collapse to 0
        AssertFalse(d = 0, CPtr(Pointer To Byte, "d <> 0 (did not collapse to 0)"))
        AssertTrue(d <> 0, CPtr(Pointer To Byte, "d <> 0"))

        ' 2.2 Exact value equivalence
        AssertTrue(d = 18446744073709551615, CPtr(Pointer To Byte, "d = 18446744073709551615"))
        AssertTrue(d = &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "d = &HFFFFFFFFFFFFFFFF"))

        ' 2.3 Exceeds signed 64-bit max (9223372036854775807)
        AssertTrue(d > 9223372036854775807, CPtr(Pointer To Byte, "d > 9223372036854775807"))
        AssertTrue(d > 4294967295, CPtr(Pointer To Byte, "d > 4294967295"))

        ' 2.4 MSB check
        AssertTrue((d RShift 63) = 1, CPtr(Pointer To Byte, "(d RShift 63) = 1"))

        ' 2.5 Arithmetic
        AssertTrue(d - 1 = 18446744073709551614, CPtr(Pointer To Byte, "d - 1 = 18446744073709551614"))
        AssertTrue(d + 1 = 0, CPtr(Pointer To Byte, "d + 1 = 0"))

        ' 2.6 Passing decimal literal to function
        AssertTrue(TakeU64(18446744073709551615) = d, CPtr(Pointer To Byte, "TakeU64(18446744073709551615) = d"))

        ' 2.7 Other large decimal literals in [2^63, 2^64 - 1]
        Dim dHalf As UInt64 = 9223372036854775808
        AssertTrue(dHalf <> 0, CPtr(Pointer To Byte, "9223372036854775808 (2^63) <> 0"))
        AssertTrue(dHalf = &H8000000000000000, CPtr(Pointer To Byte, "9223372036854775808 = &H8000000000000000"))
        AssertTrue((dHalf RShift 63) = 1, CPtr(Pointer To Byte, "(2^63 RShift 63) = 1"))

        Dim dTenQuint As UInt64 = 10000000000000000000
        AssertTrue(dTenQuint <> 0, CPtr(Pointer To Byte, "10000000000000000000 <> 0"))
        AssertTrue(dTenQuint > dHalf, CPtr(Pointer To Byte, "10000000000000000000 > 9223372036854775808"))
        AssertTrue(d > dTenQuint, CPtr(Pointer To Byte, "18446744073709551615 > 10000000000000000000"))

        Dim dNearMax As UInt64 = 18446744073709551614
        AssertTrue(dNearMax = d - 1, CPtr(Pointer To Byte, "18446744073709551614 = d - 1"))
    End Sub

    ' --- Suite 3: Mixed Comparisons with 64-Bit Maximum Literals ---
    Public Sub TestMixedComparisonsWith64BitMax()
        puts CPtr(Pointer To Byte, "[Suite 3] Mixed Comparisons with 64-Bit Maximum Literals")

        ' 3.1 Direct literal comparisons: -1 < 18446744073709551615
        AssertTrue(-1 < 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 < 18446744073709551615"))
        AssertFalse(-1 > 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 > 18446744073709551615 is False"))
        AssertTrue(-1 <= 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 <= 18446744073709551615"))
        AssertFalse(-1 >= 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 >= 18446744073709551615 is False"))
        AssertFalse(-1 = 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 = 18446744073709551615 is False"))
        AssertTrue(-1 <> 18446744073709551615, CPtr(Pointer To Byte, "Literal: -1 <> 18446744073709551615"))

        ' Inverted direct literal
        AssertTrue(18446744073709551615 > -1, CPtr(Pointer To Byte, "Literal: 18446744073709551615 > -1"))
        AssertFalse(18446744073709551615 < -1, CPtr(Pointer To Byte, "Literal: 18446744073709551615 < -1 is False"))

        ' 3.2 Direct hex literal: -1 < &HFFFFFFFFFFFFFFFF
        AssertTrue(-1 < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Literal: -1 < &HFFFFFFFFFFFFFFFF"))
        AssertFalse(-1 > &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Literal: -1 > &HFFFFFFFFFFFFFFFF is False"))
        AssertTrue(&HFFFFFFFFFFFFFFFF > -1, CPtr(Pointer To Byte, "Literal: &HFFFFFFFFFFFFFFFF > -1"))
        AssertFalse(-1 = &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Literal: -1 = &HFFFFFFFFFFFFFFFF is False"))
        AssertTrue(-1 <> &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Literal: -1 <> &HFFFFFFFFFFFFFFFF"))

        ' 3.3 Variable Int64(-1) vs Literal Max
        Dim s64Neg1 As Int64 = -1
        AssertTrue(s64Neg1 < 18446744073709551615, CPtr(Pointer To Byte, "s64Neg1(-1) < 18446744073709551615"))
        AssertTrue(s64Neg1 < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "s64Neg1(-1) < &HFFFFFFFFFFFFFFFF"))
        AssertTrue(18446744073709551615 > s64Neg1, CPtr(Pointer To Byte, "18446744073709551615 > s64Neg1(-1)"))
        AssertTrue(&HFFFFFFFFFFFFFFFF > s64Neg1, CPtr(Pointer To Byte, "&HFFFFFFFFFFFFFFFF > s64Neg1(-1)"))
        AssertFalse(s64Neg1 = 18446744073709551615, CPtr(Pointer To Byte, "s64Neg1(-1) = 18446744073709551615 is False"))
        AssertTrue(s64Neg1 <> 18446744073709551615, CPtr(Pointer To Byte, "s64Neg1(-1) <> 18446744073709551615"))

        ' 3.4 Variable Int64(-1) vs Variable UInt64(Max)
        Dim u64MaxDec As UInt64 = 18446744073709551615
        Dim u64MaxHex As UInt64 = &HFFFFFFFFFFFFFFFF
        AssertTrue(s64Neg1 < u64MaxDec, CPtr(Pointer To Byte, "s64Neg1 < u64MaxDec"))
        AssertTrue(s64Neg1 < u64MaxHex, CPtr(Pointer To Byte, "s64Neg1 < u64MaxHex"))
        AssertTrue(u64MaxDec > s64Neg1, CPtr(Pointer To Byte, "u64MaxDec > s64Neg1"))
        AssertTrue(u64MaxHex > s64Neg1, CPtr(Pointer To Byte, "u64MaxHex > s64Neg1"))
        AssertFalse(s64Neg1 = u64MaxDec, CPtr(Pointer To Byte, "s64Neg1 = u64MaxDec is False"))
        AssertTrue(s64Neg1 <> u64MaxDec, CPtr(Pointer To Byte, "s64Neg1 <> u64MaxDec"))

        ' 3.5 Mixed sizes negative signed vs 64-bit max literal
        Dim s32Neg1 As Int32 = -1
        AssertTrue(s32Neg1 < 18446744073709551615, CPtr(Pointer To Byte, "s32Neg1(-1) < 18446744073709551615"))
        AssertTrue(s32Neg1 < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "s32Neg1(-1) < &HFFFFFFFFFFFFFFFF"))

        Dim s16Neg1 As Int16 = -1
        AssertTrue(s16Neg1 < 18446744073709551615, CPtr(Pointer To Byte, "s16Neg1(-1) < 18446744073709551615"))
        AssertTrue(s16Neg1 < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "s16Neg1(-1) < &HFFFFFFFFFFFFFFFF"))

        Dim s64Min As Int64 = -9223372036854775807 - 1
        AssertTrue(s64Min < 18446744073709551615, CPtr(Pointer To Byte, "Int64.Min < 18446744073709551615"))
        AssertTrue(s64Min < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Int64.Min < &HFFFFFFFFFFFFFFFF"))

        Dim s64Max As Int64 = 9223372036854775807
        AssertTrue(s64Max < 18446744073709551615, CPtr(Pointer To Byte, "Int64.Max(9223372036854775807) < 18446744073709551615"))
        AssertTrue(s64Max < &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Int64.Max < &HFFFFFFFFFFFFFFFF"))
        AssertTrue(18446744073709551615 > s64Max, CPtr(Pointer To Byte, "18446744073709551615 > Int64.Max"))

        ' 3.6 Concise cast syntax in comparisons
        AssertTrue(Int64(-1) < UInt64(18446744073709551615), CPtr(Pointer To Byte, "Int64(-1) < UInt64(18446744073709551615)"))
        AssertTrue(CLng(-1) < CULng(18446744073709551615), CPtr(Pointer To Byte, "CLng(-1) < CULng(18446744073709551615)"))
        AssertTrue(Int64(-1) < UInt64(&HFFFFFFFFFFFFFFFF), CPtr(Pointer To Byte, "Int64(-1) < UInt64(&HFFFFFFFFFFFFFFFF)"))
    End Sub

    ' --- Suite 4: Adversarial Edge Case: Module-Level Declared Constants in Comparisons ---
    Public Sub TestModuleLevelConstantsWith64BitMax()
        puts CPtr(Pointer To Byte, "[Suite 4] Module-Level Declared Constants in Comparisons (Adversarial Bug Finding)")

        Dim s64Neg1 As Int64 = -1

        ' In LlvmEmitter.cpp, emitProcedure() resets m_variableTypes = m_globalVariableTypes.
        ' Because module constants were registered only in m_variableTypes (not m_globalVariableTypes),
        ' their type info is lost inside procedures, causing them to fall back to signed Int64.
        Dim cBugs As Int32 = 0
        If Not (-1 < K_DEC_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] -1 < Const K_DEC_MAX evaluated to False! (Const type wiped by m_globalVariableTypes reset in emitProcedure)")
            cBugs = cBugs + 1
        End If
        If Not (-1 < K_HEX_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] -1 < Const K_HEX_MAX evaluated to False!")
            cBugs = cBugs + 1
        End If
        If Not (s64Neg1 < K_DEC_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] s64Neg1 < Const K_DEC_MAX evaluated to False!")
            cBugs = cBugs + 1
        End If
        If Not (s64Neg1 < K_HEX_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] s64Neg1 < Const K_HEX_MAX evaluated to False!")
            cBugs = cBugs + 1
        End If
        If Not (K_INT64_MAX < K_DEC_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] Const K_INT64_MAX < Const K_DEC_MAX evaluated to False!")
            cBugs = cBugs + 1
        End If
        If Not (K_INT64_MAX < K_HEX_MAX) Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] Const K_INT64_MAX < Const K_HEX_MAX evaluated to False!")
            cBugs = cBugs + 1
        End If

        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF
        If Not (uVal = K_HEX_MAX) Then
            puts CPtr(Pointer To Byte, "  [CRITICAL BUG CONFIRMED] (uVal As UInt64) = (Const K_HEX_MAX As UInt64) evaluated to False! Same bit pattern 0xFFFFFFFFFFFFFFFF failed equality because Const was sign-extended!")
            cBugs = cBugs + 1
        End If

        If cBugs = 0 Then
            puts CPtr(Pointer To Byte, "  [PASS] All module-level constant comparisons passed.")
        Else
            puts CPtr(Pointer To Byte, "  [CHALLENGE CONFIRMED] Module-level constants lose UInt64 type information during procedure emission!")
            g_failures = g_failures + cBugs
        End If
    End Sub

    ' --- Main Entry Point ---
    Public Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "=========================================================")
        puts CPtr(Pointer To Byte, "   EMPIRICAL CHALLENGER: 64-BIT LITERAL & CODEGEN SUITE   ")
        puts CPtr(Pointer To Byte, "=========================================================")

        TestHex64BitRetention()
        TestDec64BitNonCollapse()
        TestMixedComparisonsWith64BitMax()
        TestModuleLevelConstantsWith64BitMax()

        puts CPtr(Pointer To Byte, "---------------------------------------------------------")
        If g_failures = 0 Then
            puts CPtr(Pointer To Byte, "[ALL 64-BIT LITERAL & DIRECT COMPARISON TESTS PASSED]")
        Else
            puts CPtr(Pointer To Byte, "[64-BIT LITERAL FAILURES DETECTED!]")
        End If

        Main = g_failures
    End Function

End Module
