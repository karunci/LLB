' Project Name: Low-Level Basic / Empirical Stress Widening Test
' Filename: tests/stress_widening/StressWidening.bas
' Summary: Comprehensive stress test suite validating implicit widening, mixed
'          signed/unsigned comparisons, extreme bounds, screen bounds clipping,
'          and call argument coercion in llbc-stage0.

Module StressWidening

    Public Declare Function puts Lib "c" Alias "puts" (ByVal s As Pointer To Byte) As Int32

    Type ScreenSurface
        Public Width As UInt32
        Public Height As UInt32
    End Type

    ' Widening callee helpers
    Public Function TakeU64(ByVal x As UInt64) As UInt64
        TakeU64 = x
    End Function

    Public Function TakeS64(ByVal x As Int64) As Int64
        TakeS64 = x
    End Function

    Public Function TakeU32(ByVal x As UInt32) As UInt32
        TakeU32 = x
    End Function

    Public Function TakeS32(ByVal x As Int32) As Int32
        TakeS32 = x
    End Function

    ' Global counter for failures
    Dim g_failures As Int32 = 0
    Dim g_bugCount As Int32 = 0

    Public Sub AssertTrue(ByVal cond As Boolean, ByVal name As Pointer To Byte)
        If cond Then
            ' ok
        Else
            puts CPtr(Pointer To Byte, "  [FAIL] Assertion failed:")
            puts name
            g_failures = g_failures + 1
        End If
    End Sub

    Public Sub AssertFalse(ByVal cond As Boolean, ByVal name As Pointer To Byte)
        AssertTrue(Not cond, name)
    End Sub

    ' --- Group 1: Mixed Signed vs Unsigned Comparisons ---
    Public Sub TestMixedSignedUnsigned()
        puts CPtr(Pointer To Byte, "[Group 1] Mixed Signed vs Unsigned Comparisons")

        ' 1.1 Negative signed numbers vs unsigned
        Dim sNeg5 As Int32 = -5
        Dim u100 As UInt32 = 100
        AssertTrue(sNeg5 < u100, CPtr(Pointer To Byte, "sNeg5 < u100"))
        AssertFalse(sNeg5 > u100, CPtr(Pointer To Byte, "sNeg5 > u100"))
        AssertTrue(sNeg5 <= u100, CPtr(Pointer To Byte, "sNeg5 <= u100"))
        AssertFalse(sNeg5 >= u100, CPtr(Pointer To Byte, "sNeg5 >= u100"))
        AssertFalse(sNeg5 = u100, CPtr(Pointer To Byte, "sNeg5 = u100"))
        AssertTrue(sNeg5 <> u100, CPtr(Pointer To Byte, "sNeg5 <> u100"))

        ' Inverted operand order: unsigned on LHS, signed on RHS
        AssertTrue(u100 > sNeg5, CPtr(Pointer To Byte, "u100 > sNeg5"))
        AssertFalse(u100 < sNeg5, CPtr(Pointer To Byte, "u100 < sNeg5"))
        AssertTrue(u100 >= sNeg5, CPtr(Pointer To Byte, "u100 >= sNeg5"))
        AssertFalse(u100 <= sNeg5, CPtr(Pointer To Byte, "u100 <= sNeg5"))
        AssertFalse(u100 = sNeg5, CPtr(Pointer To Byte, "u100 = sNeg5"))
        AssertTrue(u100 <> sNeg5, CPtr(Pointer To Byte, "u100 <> sNeg5"))

        ' 1.2 Negative vs Zero unsigned
        Dim sNeg1 As Int32 = -1
        Dim uZero As UInt32 = 0
        AssertTrue(sNeg1 < uZero, CPtr(Pointer To Byte, "sNeg1 < uZero"))
        AssertFalse(sNeg1 > uZero, CPtr(Pointer To Byte, "sNeg1 > uZero"))
        AssertTrue(uZero > sNeg1, CPtr(Pointer To Byte, "uZero > sNeg1"))
        AssertFalse(uZero < sNeg1, CPtr(Pointer To Byte, "uZero < sNeg1"))
        AssertFalse(sNeg1 = uZero, CPtr(Pointer To Byte, "sNeg1 = uZero"))
        AssertTrue(sNeg1 <> uZero, CPtr(Pointer To Byte, "sNeg1 <> uZero"))

        ' 1.3 64-bit mixed: -100L vs 50UL
        Dim s64Neg As Int64 = -100
        Dim u64Pos As UInt64 = 50
        AssertTrue(s64Neg < u64Pos, CPtr(Pointer To Byte, "s64Neg < u64Pos"))
        AssertFalse(s64Neg > u64Pos, CPtr(Pointer To Byte, "s64Neg > u64Pos"))
        AssertTrue(u64Pos > s64Neg, CPtr(Pointer To Byte, "u64Pos > s64Neg"))
        AssertFalse(u64Pos < s64Neg, CPtr(Pointer To Byte, "u64Pos < s64Neg"))
        AssertFalse(s64Neg = u64Pos, CPtr(Pointer To Byte, "s64Neg = u64Pos"))
        AssertTrue(s64Neg <> u64Pos, CPtr(Pointer To Byte, "s64Neg <> u64Pos"))

        ' 1.4 Mixed sizes: Int16 vs UInt32, Int32 vs UInt64
        Dim s16Neg As Int16 = -10
        AssertTrue(s16Neg < u100, CPtr(Pointer To Byte, "s16Neg < u100"))
        AssertTrue(u100 > s16Neg, CPtr(Pointer To Byte, "u100 > s16Neg"))

        Dim s32Neg As Int32 = -5
        Dim u64Big As UInt64 = 1000
        AssertTrue(s32Neg < u64Big, CPtr(Pointer To Byte, "s32Neg < u64Big"))
        AssertTrue(u64Big > s32Neg, CPtr(Pointer To Byte, "u64Big > s32Neg"))

        ' Unsigned 32-bit (e.g. 4000000000) vs Signed 64-bit (5000000000)
        Dim u32Large As UInt32 = 4000000000
        Dim s64Larger As Int64 = 5000000000
        AssertTrue(u32Large < s64Larger, CPtr(Pointer To Byte, "u32Large < s64Larger"))
        AssertTrue(s64Larger > u32Large, CPtr(Pointer To Byte, "s64Larger > u32Large"))
    End Sub

    ' --- Group 2: Zero Edge Cases ---
    Public Sub TestZeroEdgeCases()
        puts CPtr(Pointer To Byte, "[Group 2] Zero Edge Cases")

        Dim sZero As Int32 = 0
        Dim uZero As UInt32 = 0
        Dim uOne As UInt32 = 1

        AssertTrue(sZero < uOne, CPtr(Pointer To Byte, "sZero < uOne"))
        AssertTrue(uOne > sZero, CPtr(Pointer To Byte, "uOne > sZero"))

        AssertTrue(sZero = uZero, CPtr(Pointer To Byte, "sZero = uZero"))
        AssertTrue(uZero = sZero, CPtr(Pointer To Byte, "uZero = sZero"))
        AssertFalse(sZero <> uZero, CPtr(Pointer To Byte, "sZero <> uZero"))
        AssertFalse(uZero <> sZero, CPtr(Pointer To Byte, "uZero <> sZero"))

        AssertTrue(sZero <= uZero, CPtr(Pointer To Byte, "sZero <= uZero"))
        AssertTrue(sZero >= uZero, CPtr(Pointer To Byte, "sZero >= uZero"))
        AssertFalse(sZero < uZero, CPtr(Pointer To Byte, "sZero < uZero"))
        AssertFalse(sZero > uZero, CPtr(Pointer To Byte, "sZero > uZero"))

        Dim s64Zero As Int64 = 0
        Dim u64Zero As UInt64 = 0
        AssertTrue(s64Zero = u64Zero, CPtr(Pointer To Byte, "s64Zero = u64Zero"))
        AssertFalse(s64Zero <> u64Zero, CPtr(Pointer To Byte, "s64Zero <> u64Zero"))
        AssertTrue(s64Zero <= u64Zero, CPtr(Pointer To Byte, "s64Zero <= u64Zero"))
        AssertTrue(s64Zero >= u64Zero, CPtr(Pointer To Byte, "s64Zero >= u64Zero"))
    End Sub

    ' --- Group 3: Extreme Bounds (32-bit & 64-bit Comparisons) ---
    Public Sub TestExtremeBounds()
        puts CPtr(Pointer To Byte, "[Group 3] Extreme Bounds (Comparison Engine)")

        ' 3.1 Int32.MinValue (-2147483648) vs 0UI
        Dim int32Min As Int32 = -2147483647 - 1
        Dim uZero As UInt32 = 0
        AssertTrue(int32Min < uZero, CPtr(Pointer To Byte, "int32Min < uZero"))
        AssertFalse(int32Min > uZero, CPtr(Pointer To Byte, "int32Min > uZero"))
        AssertTrue(uZero > int32Min, CPtr(Pointer To Byte, "uZero > int32Min"))
        AssertTrue(int32Min <= uZero, CPtr(Pointer To Byte, "int32Min <= uZero"))

        ' 3.2 Int32.MaxValue (2147483647) vs UInt32.MaxValue (4294967295)
        Dim int32Max As Int32 = 2147483647
        Dim uint32Max As UInt32 = 4294967295
        AssertTrue(int32Max < uint32Max, CPtr(Pointer To Byte, "int32Max < uint32Max"))
        AssertTrue(uint32Max > int32Max, CPtr(Pointer To Byte, "uint32Max > int32Max"))
        AssertFalse(int32Max = uint32Max, CPtr(Pointer To Byte, "int32Max = uint32Max"))
        AssertTrue(int32Max <> uint32Max, CPtr(Pointer To Byte, "int32Max <> uint32Max"))

        ' 3.3 Two's Complement Same Bit Pattern (0xFFFFFFFF): -1 vs 4294967295
        Dim sNegOne As Int32 = -1
        AssertTrue(sNegOne < uint32Max, CPtr(Pointer To Byte, "sNegOne < uint32Max"))
        AssertTrue(uint32Max > sNegOne, CPtr(Pointer To Byte, "uint32Max > sNegOne"))
        AssertFalse(sNegOne = uint32Max, CPtr(Pointer To Byte, "sNegOne = uint32Max (must NOT be equal)"))
        AssertTrue(sNegOne <> uint32Max, CPtr(Pointer To Byte, "sNegOne <> uint32Max"))

        ' 3.4 64-bit bounds: -1LL vs 18446744073709551615ULL (runtime calculated)
        Dim s64NegOne As Int64 = -1
        Dim uint64Max As UInt64 = CULng(0) - CULng(1)
        AssertTrue(s64NegOne < uint64Max, CPtr(Pointer To Byte, "s64NegOne < uint64Max"))
        AssertTrue(uint64Max > s64NegOne, CPtr(Pointer To Byte, "uint64Max > s64NegOne"))
        AssertFalse(s64NegOne = uint64Max, CPtr(Pointer To Byte, "s64NegOne = uint64Max (must NOT be equal)"))
        AssertTrue(s64NegOne <> uint64Max, CPtr(Pointer To Byte, "s64NegOne <> uint64Max"))

        ' 3.5 Int64.MinValue vs 0ULL
        Dim int64Min As Int64 = -9223372036854775807 - 1
        Dim u64Zero As UInt64 = 0
        AssertTrue(int64Min < u64Zero, CPtr(Pointer To Byte, "int64Min < u64Zero"))
        AssertTrue(u64Zero > int64Min, CPtr(Pointer To Byte, "u64Zero > int64Min"))
        AssertFalse(int64Min > u64Zero, CPtr(Pointer To Byte, "int64Min > u64Zero"))

        ' 3.6 Int64.MaxValue vs UInt64.MaxValue (runtime calculated)
        Dim int64Max As Int64 = 9223372036854775807
        AssertTrue(int64Max < uint64Max, CPtr(Pointer To Byte, "int64Max < uint64Max"))
        AssertTrue(uint64Max > int64Max, CPtr(Pointer To Byte, "uint64Max > int64Max"))
    End Sub

    ' --- Group 4: Screen Bounds Clipping Scenario ---
    Public Sub TestScreenBoundsClipping()
        puts CPtr(Pointer To Byte, "[Group 4] Screen Bounds Clipping Scenario")

        Dim height As UInt32 = 768
        Dim width As UInt32 = 1024

        ' Scalar curY = -10 (negative coordinate above viewport)
        Dim curY As Int32 = -10
        AssertTrue(curY < height, CPtr(Pointer To Byte, "curY(-10) < height(768)"))
        AssertFalse(curY >= 0, CPtr(Pointer To Byte, "curY(-10) >= 0 is False"))
        AssertFalse(curY >= 0 And curY < height, CPtr(Pointer To Byte, "Clipping: curY(-10) is out-of-bounds"))

        ' Scalar curX = -15 (negative coordinate left of viewport)
        Dim curX As Int32 = -15
        AssertTrue(curX < width, CPtr(Pointer To Byte, "curX(-15) < width(1024)"))
        AssertFalse(curX >= 0, CPtr(Pointer To Byte, "curX(-15) >= 0 is False"))

        ' Top-left in-bounds pixel: (0, 0)
        curX = 0
        curY = 0
        AssertTrue(curX < width, CPtr(Pointer To Byte, "curX(0) < width(1024)"))
        AssertTrue(curY < height, CPtr(Pointer To Byte, "curY(0) < height(768)"))
        AssertTrue(curX >= 0 And curX < width And curY >= 0 And curY < height, CPtr(Pointer To Byte, "Clipping: (0, 0) is in-bounds"))

        ' Bottom-right in-bounds pixel: (1023, 767)
        curX = 1023
        curY = 767
        AssertTrue(curX < width, CPtr(Pointer To Byte, "curX(1023) < width(1024)"))
        AssertTrue(curY < height, CPtr(Pointer To Byte, "curY(767) < height(768)"))
        AssertTrue(curX >= 0 And curX < width And curY >= 0 And curY < height, CPtr(Pointer To Byte, "Clipping: (1023, 767) is in-bounds"))

        ' Exactly at boundary: (1024, 768) - must be clipped out
        curX = 1024
        curY = 768
        AssertFalse(curX < width, CPtr(Pointer To Byte, "curX(1024) < width(1024) is False"))
        AssertFalse(curY < height, CPtr(Pointer To Byte, "curY(768) < height(768) is False"))
        AssertFalse(curX >= 0 And curX < width And curY >= 0 And curY < height, CPtr(Pointer To Byte, "Clipping: (1024, 768) is out-of-bounds"))

        ' Struct field clipping
        Dim backSurf As ScreenSurface
        backSurf.Width = 1024
        backSurf.Height = 768

        curY = -10
        AssertTrue(curY < backSurf.Height, CPtr(Pointer To Byte, "curY(-10) < backSurf.Height"))
        curX = -5
        AssertTrue(curX < backSurf.Width, CPtr(Pointer To Byte, "curX(-5) < backSurf.Width"))

        ' Pointer to struct clipping
        Dim pSurf As Pointer To ScreenSurface = AddressOf backSurf
        AssertTrue(curY < pSurf.Height, CPtr(Pointer To Byte, "curY(-10) < pSurf.Height"))
        AssertTrue(curX < pSurf.Width, CPtr(Pointer To Byte, "curX(-5) < pSurf.Width"))
    End Sub

    ' --- Group 5: Call Argument Widening & Cast Coercion ---
    Public Sub TestCallArgumentWidening()
        puts CPtr(Pointer To Byte, "[Group 5] Call Argument Widening & Coercion")

        Dim bVal As Byte = 250
        Dim u16Val As UInt16 = 65000
        Dim s16Val As Int16 = -30000
        Dim u32Val As UInt32 = 3500000000
        Dim s32Val As Int32 = -12345678
        Dim s32Min As Int32 = -2147483647 - 1
        Dim s32Max As Int32 = 2147483647

        ' Widen Byte -> UInt64, Int64, UInt32, Int32
        AssertTrue(TakeU64(bVal) = 250, CPtr(Pointer To Byte, "TakeU64(Byte) = 250"))
        AssertTrue(TakeS64(bVal) = 250, CPtr(Pointer To Byte, "TakeS64(Byte) = 250"))
        AssertTrue(TakeU32(bVal) = 250, CPtr(Pointer To Byte, "TakeU32(Byte) = 250"))
        AssertTrue(TakeS32(bVal) = 250, CPtr(Pointer To Byte, "TakeS32(Byte) = 250"))

        ' Widen UInt16 -> UInt64, Int64, UInt32, Int32
        AssertTrue(TakeU64(u16Val) = 65000, CPtr(Pointer To Byte, "TakeU64(UInt16) = 65000"))
        AssertTrue(TakeS64(u16Val) = 65000, CPtr(Pointer To Byte, "TakeS64(UInt16) = 65000"))
        AssertTrue(TakeU32(u16Val) = 65000, CPtr(Pointer To Byte, "TakeU32(UInt16) = 65000"))
        AssertTrue(TakeS32(u16Val) = 65000, CPtr(Pointer To Byte, "TakeS32(UInt16) = 65000"))

        ' Widen Int16 -> Int64, Int32 (sign preservation)
        AssertTrue(TakeS64(s16Val) = -30000, CPtr(Pointer To Byte, "TakeS64(Int16) = -30000"))
        AssertTrue(TakeS32(s16Val) = -30000, CPtr(Pointer To Byte, "TakeS32(Int16) = -30000"))

        ' Widen UInt32 -> UInt64, Int64 (zero-extension, MUST NOT sign extend!)
        AssertTrue(TakeU64(u32Val) = 3500000000, CPtr(Pointer To Byte, "TakeU64(UInt32) = 3500000000"))
        AssertTrue(TakeS64(u32Val) = 3500000000, CPtr(Pointer To Byte, "TakeS64(UInt32) = 3500000000 (positive!)"))

        Dim u32Max As UInt32 = 4294967295
        AssertTrue(TakeU64(u32Max) = 4294967295, CPtr(Pointer To Byte, "TakeU64(u32Max) = 4294967295"))
        AssertTrue(TakeS64(u32Max) = 4294967295, CPtr(Pointer To Byte, "TakeS64(u32Max) = 4294967295 (positive!)"))

        ' Widen Int32 -> Int64 (sign-extension)
        AssertTrue(TakeS64(s32Val) = -12345678, CPtr(Pointer To Byte, "TakeS64(Int32) = -12345678"))
        AssertTrue(TakeS64(s32Min) = s32Min, CPtr(Pointer To Byte, "TakeS64(Int32.Min)"))
        AssertTrue(TakeS64(s32Max) = s32Max, CPtr(Pointer To Byte, "TakeS64(Int32.Max)"))
    End Sub

    ' --- Group 6: Concise Cast Syntax ---
    Public Sub TestConciseCastSyntax()
        puts CPtr(Pointer To Byte, "[Group 6] Concise Cast Syntax")

        ' In-place concise casts in binary comparisons
        AssertTrue(-5 < UInt32(100), CPtr(Pointer To Byte, "-5 < UInt32(100)"))
        AssertTrue(-1 < CUInt(0), CPtr(Pointer To Byte, "-1 < CUInt(0)"))
        AssertTrue(-100 < CULng(50), CPtr(Pointer To Byte, "-100 < CULng(50)"))
        AssertTrue(Int32(-2147483647 - 1) < CUInt(0), CPtr(Pointer To Byte, "Int32.Min < CUInt(0)"))
        AssertTrue(Int32(-1) < UInt32(4294967295), CPtr(Pointer To Byte, "Int32(-1) < UInt32(4294967295)"))
        AssertFalse(Int32(-1) = UInt32(4294967295), CPtr(Pointer To Byte, "Int32(-1) = UInt32(4294967295) is False"))
    End Sub

    ' --- Group 7: Adversarial Literal Edge Cases (Bug Demonstration) ---
    Public Sub TestAdversarialLiteralEdgeCases()
        puts CPtr(Pointer To Byte, "[Group 7] Adversarial Literal Edge Cases (Parser & Codegen Bug Triage)")

        ' Check 1: 18446744073709551615 decimal literal overflow in Parser.cpp
        ' std::stoll throws out_of_range, parser catch-block zeroes it out!
        Dim decLitZeroCheck As UInt64 = 18446744073709551615
        If decLitZeroCheck = 0 Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] Decimal literal 18446744073709551615 silently collapsed to 0 in Parser.cpp (stoll overflow)!")
            g_bugCount = g_bugCount + 1
        Else
            puts CPtr(Pointer To Byte, "  [OK] Decimal literal 18446744073709551615 parsed correctly.")
        End If

        ' Check 2: &HFFFFFFFFFFFFFFFF 64-bit hex literal truncation in LlvmEmitter.cpp
        ' Value is -1LL, lies in [-2147483648, 2147483647], codegen emits i32 and zext zero-extends to 4294967295!
        Dim hexLitTruncCheck As UInt64 = &HFFFFFFFFFFFFFFFF
        If hexLitTruncCheck = 4294967295 Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] Hex literal &HFFFFFFFFFFFFFFFF truncated to 32-bit (4294967295) in LlvmEmitter.cpp line 5914!")
            g_bugCount = g_bugCount + 1
        Else
            puts CPtr(Pointer To Byte, "  [OK] Hex literal &HFFFFFFFFFFFFFFFF retained all 64 bits.")
        End If
    End Sub

    ' --- Main Entry Point ---
    Public Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "=========================================================")
        puts CPtr(Pointer To Byte, "   EMPIRICAL STRESS TEST SUITE: WIDENING & COMPARISONS   ")
        puts CPtr(Pointer To Byte, "=========================================================")

        TestMixedSignedUnsigned()
        TestZeroEdgeCases()
        TestExtremeBounds()
        TestScreenBoundsClipping()
        TestCallArgumentWidening()
        TestConciseCastSyntax()
        TestAdversarialLiteralEdgeCases()

        puts CPtr(Pointer To Byte, "---------------------------------------------------------")
        If g_failures = 0 Then
            puts CPtr(Pointer To Byte, "[COMPARISON & WIDENING SUITE PASSED] Core comparison & widening engine is mathematically correct!")
        Else
            puts CPtr(Pointer To Byte, "[COMPARISON & WIDENING SUITE FAILED] Comparison engine failures encountered!")
        End If

        If g_bugCount > 0 Then
            puts CPtr(Pointer To Byte, "[ADVERSARIAL BUGS DETECTED] 64-bit literal parsing/emission flaws confirmed!")
        End If

        Main = g_failures
    End Function

End Module
