' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/StressCastMain.bas
' Summary: Comprehensive empirical test runner for concise casting and type conversions.

Module StressCastMain

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Type Point2D
        X As Int32
        Y As Int32
    End Type

    TypeAlias ProcessIdentifier = UInt64
    TypeAlias BytePtr = *Byte

    ''
    ' @brief Validates primitive concise casts across bitwidths and signedness.
    ' @return True if all primitive cast assertions pass; False otherwise.
    ''
    Public Unsafe Function TestPrimitiveConciseCasts() As Boolean
        ' 1. UInt64 concise casts
        Dim u64FromI32 As UInt64 = UInt64(100)
        If u64FromI32 <> 100 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt64 from Int32")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim u64FromByte As UInt64 = UInt64(Byte(255))
        If u64FromByte <> 255 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt64 from Byte")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim u64FromFlt As UInt64 = UInt64(Single(1234.0))
        If u64FromFlt <> 1234 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt64 from Single")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim u64FromDbl As UInt64 = UInt64(Double(9876543210.0))
        If u64FromDbl <> 9876543210 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt64 from Double")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 2. Int32 concise casts & truncation
        Dim s32FromU64 As Int32 = Int32(UInt64(4294967340)) ' 0x10000002C -> 0x2C = 44
        If s32FromU64 <> 44 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int32 from UInt64 truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim s32FromDbl As Int32 = Int32(Double(-42.75))
        If s32FromDbl <> -42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int32 from Double truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim s32FromBool As Int32 = Int32(Boolean(1))
        If s32FromBool = 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int32 from Boolean(1)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 3. UInt32 concise casts
        Dim u32Val As UInt32 = UInt32(UInt64(4000000000))
        If u32Val <> 4000000000 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt32 value preservation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim u32Trunc As UInt32 = UInt32(UInt64(&H100000002))
        If u32Trunc <> 2 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt32 truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 4. Byte concise casts & truncation
        Dim bVal As Byte = Byte(255)
        If bVal <> 255 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Byte(255)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim bTrunc256 As Byte = Byte(256)
        If bTrunc256 <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Byte(256) truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim bTrunc257 As Byte = Byte(257)
        If bTrunc257 <> 1 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Byte(257) truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim bTrunc515 As Byte = Byte(515)
        If bTrunc515 <> 3 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Byte(515) truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 5. Int64 concise casts & sign preservation
        Dim s64Neg As Int64 = Int64(Int32(-999))
        If s64Neg <> -999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int64 negative preservation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim s64FromS16 As Int64 = Int64(Int16(-32768))
        If s64FromS16 <> -32768 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int64 from Int16 sign preservation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 6. UInt16 and Int16 concise casts
        Dim u16Val As UInt16 = UInt16(UInt32(65535))
        If u16Val <> 65535 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt16 value preservation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim u16Trunc As UInt16 = UInt16(UInt32(65536))
        If u16Trunc <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: UInt16 truncation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim s16Val As Int16 = Int16(-12345)
        If s16Val <> -12345 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Int16 negative preservation")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 7. Single and Double concise casts
        Dim sngVal As Single = Single(100)
        If sngVal < 99.9 Or sngVal > 100.1 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Single(100)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim dblVal As Double = Double(-42)
        If dblVal < -42.1 Or dblVal > -41.9 Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Double(-42)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        ' 8. Boolean concise casts
        Dim boolZero As Boolean = Boolean(0)
        If boolZero Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Boolean(0)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        Dim boolOne As Boolean = Boolean(1)
        If Not boolOne Then
            puts CPtr(Pointer To Byte, "[FAIL] Primitive: Boolean(1)")
            TestPrimitiveConciseCasts = False
            Exit Function
        End If

        TestPrimitiveConciseCasts = True
    End Function

    ''
    ' @brief Validates classic Visual Basic conversion functions (CByte, CUInt, CULng, CInt, CLng, CSng, CDbl, CBool).
    ' @return True if all classic VB conversions pass; False otherwise.
    ''
    Public Unsafe Function TestClassicVbConversions() As Boolean
        Dim cbVal As Byte = CByte(200)
        If cbVal <> 200 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CByte(200)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cbTrunc As Byte = CByte(258)
        If cbTrunc <> 2 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CByte(258)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cs16 As Int16 = CShort(-32000)
        If cs16 <> -32000 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CShort(-32000)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cu16 As UInt16 = CUShort(64000)
        If cu16 <> 64000 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CUShort(64000)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim ci32 As Int32 = CInt(-2147483647)
        If ci32 <> -2147483647 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CInt(-2147483647)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cu32 As UInt32 = CUInt(4294967295)
        If cu32 <> 4294967295 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CUInt(4294967295)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cl64 As Int64 = CLng(-9000000000000000)
        If cl64 <> -9000000000000000 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CLng(-9000000000000000)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cul64 As UInt64 = CULng(18000000000000000)
        If cul64 <> 18000000000000000 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CULng(18000000000000000)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim csngV As Single = CSng(3.5)
        If csngV < 3.4 Or csngV > 3.6 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CSng(3.5)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cdblV As Double = CDbl(2.718281828)
        If cdblV < 2.71828 Or cdblV > 2.71829 Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CDbl(2.718281828)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cboolF As Boolean = CBool(0)
        If cboolF Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CBool(0)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cboolT As Boolean = CBool(1)
        If Not cboolT Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CBool(1)")
            TestClassicVbConversions = False
            Exit Function
        End If

        Dim cboolNeg As Boolean = CBool(-5)
        If Not cboolNeg Then
            puts CPtr(Pointer To Byte, "[FAIL] Classic VB: CBool(-5)")
            TestClassicVbConversions = False
            Exit Function
        End If

        TestClassicVbConversions = True
    End Function

    ''
    ' @brief Validates string-to-numeric conversions through concise and classic syntax.
    ' @return True if all string conversions pass; False otherwise.
    ''
    Public Unsafe Function TestStringNumericConversions() As Boolean
        ' String literal to Int32
        Dim s1 As Int32 = CInt("123")
        If s1 <> 123 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CInt(""123"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String literal to Int64
        Dim s2 As Int64 = CLng("999999")
        If s2 <> 999999 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CLng(""999999"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String literal to Int32 via concise syntax
        Dim s3 As Int32 = Int32("555")
        If s3 <> 555 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: Int32(""555"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String literal to UInt64
        Dim s4 As UInt64 = UInt64("1234567890")
        If s4 <> 1234567890 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: UInt64(""1234567890"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' Negative string to Int32
        Dim s5 As Int32 = CInt("-42")
        If s5 <> -42 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CInt(""-42"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String with leading whitespace
        Dim s6 As Int32 = CInt("   777")
        If s6 <> 777 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CInt(""   777"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String to Double
        Dim s7 As Double = CDbl("3.14159")
        If s7 < 3.14158 Or s7 > 3.14160 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CDbl(""3.14159"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String variable conversion
        Dim strVar As String = "8888"
        Dim s8 As Int32 = Int32(strVar)
        If s8 <> 8888 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: Int32(strVar)")
            TestStringNumericConversions = False
            Exit Function
        End If

        ' String concatenation conversion
        Dim s9 As Int32 = CInt("12" & "34")
        If s9 <> 1234 Then
            puts CPtr(Pointer To Byte, "[FAIL] String: CInt(""12"" & ""34"")")
            TestStringNumericConversions = False
            Exit Function
        End If

        TestStringNumericConversions = True
    End Function

    ''
    ' @brief Validates prefix pointer casts (*Byte(p), *UInt64(p)) and unary pointer dereference.
    ' @return True if all pointer casts pass; False otherwise.
    ''
    Public Unsafe Function TestPrefixPointerCasts() As Boolean
        Dim rawVal As UInt64 = &H0102030405060708

        ' Prefix pointer cast to byte pointer: *Byte(AddressOf rawVal)
        Dim pByte As *Byte = *Byte(AddressOf rawVal)
        If pByte(0) <> &H08 Then
            puts CPtr(Pointer To Byte, "[FAIL] Pointer: *Byte(addr)(0) little-endian")
            TestPrefixPointerCasts = False
            Exit Function
        End If

        ' Prefix pointer cast to uint64 pointer: *UInt64(AddressOf rawVal)
        Dim pU64 As *UInt64 = *UInt64(AddressOf rawVal)
        If pU64(0) <> &H0102030405060708 Then
            puts CPtr(Pointer To Byte, "[FAIL] Pointer: *UInt64(addr)(0)")
            TestPrefixPointerCasts = False
            Exit Function
        End If

        ' Unary dereference *pU64
        Dim derefVal As UInt64 = *pU64
        If derefVal <> &H0102030405060708 Then
            puts CPtr(Pointer To Byte, "[FAIL] Pointer: *pU64 unary dereference")
            TestPrefixPointerCasts = False
            Exit Function
        End If

        ' Double pointer cast and dereference
        Dim pAddr As Pointer To UInt64 = AddressOf rawVal
        Dim ppU64 As **UInt64 = **UInt64(AddressOf pAddr)
        Dim loadedP As *UInt64 = *ppU64
        If loadedP(0) <> &H0102030405060708 Then
            puts CPtr(Pointer To Byte, "[FAIL] Pointer: **UInt64 double pointer")
            TestPrefixPointerCasts = False
            Exit Function
        End If

        ' Cast pointer to address integer: UInt64(pByte)
        Dim ptrAsInt As UInt64 = UInt64(pByte)
        Dim backToPtr As *Byte = *Byte(ptrAsInt)
        If backToPtr(0) <> &H08 Then
            puts CPtr(Pointer To Byte, "[FAIL] Pointer: UInt64(ptr) -> *Byte(int)")
            TestPrefixPointerCasts = False
            Exit Function
        End If

        TestPrefixPointerCasts = True
    End Function

    ''
    ' @brief Validates nested expressions and arithmetic inside concise casts.
    ' @return True if all nested expression tests pass; False otherwise.
    ''
    Public Unsafe Function TestNestedExpressions() As Boolean
        Dim a As Int32 = 100
        Dim b As Byte = 25
        Dim c As UInt16 = 300

        ' Nested: UInt64(Int32(a) + Byte(b))
        Dim res1 As UInt64 = UInt64(Int32(a) + Byte(b))
        If res1 <> 125 Then
            puts CPtr(Pointer To Byte, "[FAIL] Nested: UInt64(Int32(a) + Byte(b))")
            TestNestedExpressions = False
            Exit Function
        End If

        ' Complex arithmetic: CULng(a * b + c) -> 100 * 25 + 300 = 2800
        Dim res2 As UInt64 = CULng(a * b + c)
        If res2 <> 2800 Then
            puts CPtr(Pointer To Byte, "[FAIL] Nested: CULng(a * b + c)")
            TestNestedExpressions = False
            Exit Function
        End If

        ' Nested multiple level casts: Byte(UInt16(UInt32(UInt64(70000)))) -> 70000 % 65536 = 4464; 4464 % 256 = 112
        Dim res3 As Byte = Byte(UInt16(UInt32(UInt64(70000))))
        If res3 <> 112 Then
            puts CPtr(Pointer To Byte, "[FAIL] Nested: Multi-level cast chain")
            TestNestedExpressions = False
            Exit Function
        End If

        ' Bitwise inside cast: CByte(CInt(a) And &HFF)
        Dim res4 As Byte = CByte(CInt(300) And &HFF)
        If res4 <> 44 Then
            puts CPtr(Pointer To Byte, "[FAIL] Nested: CByte(CInt(300) And &HFF)")
            TestNestedExpressions = False
            Exit Function
        End If

        ' Casts inside comparison expressions
        Dim u1 As UInt32 = 500
        Dim u2 As UInt32 = 1000
        If Not (UInt64(u1) < UInt64(u2)) Then
            puts CPtr(Pointer To Byte, "[FAIL] Nested: If UInt64(u1) < UInt64(u2)")
            TestNestedExpressions = False
            Exit Function
        End If

        TestNestedExpressions = True
    End Function

    ''
    ' @brief Validates TypeAlias casts and user-defined structure casts.
    ' @return True if alias and structure casts pass; False otherwise.
    ''
    Public Unsafe Function TestTypeAliasAndStructCasts() As Boolean
        Dim pid As ProcessIdentifier = ProcessIdentifier(1024)
        If pid <> 1024 Then
            puts CPtr(Pointer To Byte, "[FAIL] TypeAlias: ProcessIdentifier(1024)")
            TestTypeAliasAndStructCasts = False
            Exit Function
        End If

        Dim pt As Point2D
        pt.X = 123
        pt.Y = 456

        Dim ptPtr As *Point2D = *Point2D(AddressOf pt)
        If ptPtr.X <> 123 Or ptPtr.Y <> 456 Then
            puts CPtr(Pointer To Byte, "[FAIL] Struct Cast: *Point2D(AddressOf pt)")
            TestTypeAliasAndStructCasts = False
            Exit Function
        End If

        TestTypeAliasAndStructCasts = True
    End Function

    ''
    ' @brief Validates backward compatibility with legacy CType() and CPtr() syntax.
    ' @return True if backward compatibility tests pass; False otherwise.
    ''
    Public Unsafe Function TestBackwardCompatibility() As Boolean
        Dim val As UInt64 = 9999
        Dim legacyU64 As UInt64 = CType(UInt64, 9999)
        If legacyU64 <> 9999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Legacy: CType(UInt64, 9999)")
            TestBackwardCompatibility = False
            Exit Function
        End If

        Dim legacyI32 As Int32 = CType(Int32, -42)
        If legacyI32 <> -42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Legacy: CType(Int32, -42)")
            TestBackwardCompatibility = False
            Exit Function
        End If

        Dim legacyPtr As Pointer To UInt64 = CPtr(Pointer To UInt64, AddressOf val)
        If legacyPtr(0) <> 9999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Legacy: CPtr(Pointer To UInt64, AddressOf val)")
            TestBackwardCompatibility = False
            Exit Function
        End If

        Dim legacyPtrStar As *UInt64 = CPtr(*UInt64, AddressOf val)
        If legacyPtrStar(0) <> 9999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Legacy: CPtr(*UInt64, AddressOf val)")
            TestBackwardCompatibility = False
            Exit Function
        End If

        TestBackwardCompatibility = True
    End Function

    ''
    ' @brief Main test runner entry point.
    ' @param argc Number of command line arguments.
    ' @param argv Pointer to argument strings.
    ' @return 0 on success; 1 on test failure.
    ''
    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "================================================")
        puts CPtr(Pointer To Byte, "  RUNNING EMPIRICAL CHALLENGER CAST TEST SUITE  ")
        puts CPtr(Pointer To Byte, "================================================")

        If Not TestPrimitiveConciseCasts() Then
            puts CPtr(Pointer To Byte, "[-] Suite 1 FAILED: Primitive Concise Casts")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 1 PASSED: Primitive Concise Casts")

        If Not TestClassicVbConversions() Then
            puts CPtr(Pointer To Byte, "[-] Suite 2 FAILED: Classic VB Conversions")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 2 PASSED: Classic VB Conversions")

        If Not TestStringNumericConversions() Then
            puts CPtr(Pointer To Byte, "[-] Suite 3 FAILED: String-to-Numeric Conversions")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 3 PASSED: String-to-Numeric Conversions")

        If Not TestPrefixPointerCasts() Then
            puts CPtr(Pointer To Byte, "[-] Suite 4 FAILED: Prefix Pointer Casts & Dereference")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 4 PASSED: Prefix Pointer Casts & Dereference")

        If Not TestNestedExpressions() Then
            puts CPtr(Pointer To Byte, "[-] Suite 5 FAILED: Nested Expressions & Complex Arithmetic")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 5 PASSED: Nested Expressions & Complex Arithmetic")

        If Not TestTypeAliasAndStructCasts() Then
            puts CPtr(Pointer To Byte, "[-] Suite 6 FAILED: TypeAlias and Struct Casts")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 6 PASSED: TypeAlias and Struct Casts")

        If Not TestBackwardCompatibility() Then
            puts CPtr(Pointer To Byte, "[-] Suite 7 FAILED: Backward Compatibility (CType & CPtr)")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[+] Suite 7 PASSED: Backward Compatibility (CType & CPtr)")

        puts CPtr(Pointer To Byte, "================================================")
        puts CPtr(Pointer To Byte, "  ALL 7 CHALLENGER TEST SUITES PASSED (100%)    ")
        puts CPtr(Pointer To Byte, "================================================")
        Main = 0
    End Function

End Module
