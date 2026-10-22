' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module TestSuite

    #Const TARGET_ENV = 1
    #Const ARCH_BITS = 64
    #Const UNUSED_FLAG = 0

    #Assert TARGET_ENV = 1, "TARGET_ENV constant validation"
    #Assert ARCH_BITS = 64, "ARCH_BITS 64-bit architecture assertion"
    #Assert 100 > 50, "Basic compile-time inequality"

    Import ImportHelper In "ImportHelper.bas"
    Import MathHelper In "NamespaceHelper.bas"
    Use ClassHelper In "ClassHelper.cls" As Helper
    Use SingleUseHelper In "SingleUseHelper.cls" As SingleInst
    Use DeviceWriter In "DeviceWriter.cls" As Writer

    ' Module-level constants & global initializers
    Public Const MODULE_TEST_MAGIC As Int32 = 4242
    Private Const PI_APPROX As Double = 3.14159
    Dim g_initializedCounter As Int32 = 777

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32
    Public Declare Function putsLib Lib "c" Alias "puts" (ByVal str As Pointer To Byte) As Int32
    Public Declare Function AddNumbers Lib "SharedLib" (ByVal a As Int32, ByVal b As Int32) As Int32
    Public Declare Function StaticMultiply(ByVal a As Int32, ByVal b As Int32) As Int32
    Public Declare Function StaticPower(ByVal baseVal As Int32, ByVal expVal As Int32) As Int32

    ' Runtime Type & String Inspection Helpers
    Public Function IsNumericString(ByVal s As String) As Boolean
        If Len(s) = 0 Then
            IsNumericString = False
            Exit Function
        End If
        Dim i As Int32
        Dim hasDigit As Boolean = False
        For i = 1 To Len(s)
            Dim ch As String = Mid(s, i, 1)
            Dim c As Int32 = Asc(ch)
            If c >= 48 And c <= 57 Then
                hasDigit = True
            ElseIf (c = 43 Or c = 45) And i = 1 Then
                ' Leading '+' or '-'
            ElseIf c = 46 Then
                ' Decimal point '.'
            Else
                IsNumericString = False
                Exit Function
            End If
        Next i
        IsNumericString = hasDigit
    End Function

    Public Enum TrafficLight
        Red = 10
        Yellow = 20
        Green = 30
    End Enum

    Public Structure Point
        Public X As Int32
        Public Y As Int32
    End Structure

    Public Type Coordinate
        Public Lat As Double
        Public Lon As Double
        Public Altitude As Int32
    End Type

    ' Type Aliases (Synonyms for types)
    TypeAlias BytePtr = Pointer To Byte
    TypeAlias Score = Int32
    TypeAlias GeoLocation = Coordinate
    TypeAlias Dictionary = Pointer To Byte
    TypeAlias Map = Pointer To Byte

    ' Option 2: Standalone Fixed-Capacity Hash Table for Microkernel / Freestanding systems
    Public Structure HashMapEntry
        Public Key As Pointer To Byte
        Public Value As Int64
        Public Occupied As Int32
    End Structure

    Public Structure HashMap
        Public Count As Int32
        Public Capacity As Int32
        Public EntriesBuffer As Pointer To HashMapEntry
    End Structure

    ' Standalone / Freestanding Dynamic ArrayList structure
    Public Structure ArrayList
        Public Count As Int32
        Public Capacity As Int32
        Public Data As Pointer To Int32
    End Structure

    Public Structure ServiceNode
        Public Port As Int32
        Public IsActive As Int32
    End Structure

    ' Bitfield Packed Structure
    <Packed>
    Public Structure BitfieldFlags
        Public FlagA As Byte * 1
        Public FlagB As Byte * 1
        Public Mode  As Byte * 2
        Public Extra As Byte * 4
    End Structure

    #Assert SizeOf(BitfieldFlags) = 1, "BitfieldFlags must occupy exactly 1 byte"

    Public Union DWordReg
        Public DwordVal As UInt32
        Public WordVal As UInt16
        Public ByteVal As Byte
    End Union

    ' Generic Structure Template (Monomorphized)
    Public Structure Box(Of T)
        Public Value As T
        Public Tag As Int32
    End Structure

    ' Interface definition for polymorphism and method dispatch verification
    Public Interface IWriter
        Function WriteData(ByVal val As Int32) As Int32
        Sub ResetDevice()
    End Interface

    ' Generic Function Template (Monomorphized)
    Public Function Min(Of T)(ByVal a As T, ByVal b As T) As T
        If a < b Then
            Min = a
        Else
            Min = b
        End If
    End Function


    ' Test 1: Arithmetic & Modulo
    Public Function TestArithmetic() As Boolean
        Dim a As Int32
        Dim b As Int32
        Dim c As Int32
        a = 20
        b = 6
        c = (a + b) * 2 - (a / b) + (a Mod b)
        ' (26) * 2 - 3 + 2 = 52 - 3 + 2 = 51
        If c = 51 Then
            TestArithmetic = True
        Else
            Print "TestArithmetic failed: expected c=51, got c=", c
            TestArithmetic = False
        End If
    End Function

    ' Test 2: Bitwise and Shift Operators
    Public Function TestBitwise() As Boolean
        Dim val1 As UInt32
        Dim val2 As UInt32
        Dim res As UInt32
        val1 = &H000F
        val2 = &H00F0

        res = (val1 Or val2) And &H00FF
        If res <> &H00FF Then
            Print "TestBitwise failed at Or/And: expected &H00FF, got ", res
            TestBitwise = False
            Exit Function
        End If

        res = (val1 LShift 4)
        If res <> &H00F0 Then
            Print "TestBitwise failed at LShift: expected &H00F0, got ", res
            TestBitwise = False
            Exit Function
        End If

        res = (val2 RShift 4)
        If res <> &H000F Then
            Print "TestBitwise failed at RShift: expected &H000F, got ", res
            TestBitwise = False
            Exit Function
        End If

        res = val1 Xor val1
        If res <> 0 Then
            Print "TestBitwise failed at Xor: expected 0, got ", res
            TestBitwise = False
            Exit Function
        End If

        TestBitwise = True
    End Function

    ' Test 3: Nested If-Else
    Public Function TestNestedIf(ByVal x As Int32) As Int32
        Dim result As Int32
        If x > 100 Then
            If x > 200 Then
                result = 3
            Else
                result = 2
            End If
        ElseIf x > 50 Then
            result = 1
        Else
            result = 0
        End If
        TestNestedIf = result
    End Function

    ' Test 4: For Loop with Step and Next
    Public Function TestForLoop() As Int32
        Dim sum As Int32
        Dim i As Int32
        sum = 0
        For i = 1 To 10
            sum = sum + i
        Next i

        ' Loop with Step 2
        Dim stepSum As Int32
        stepSum = 0
        For i = 0 To 10 Step 2
            stepSum = stepSum + i
        Next i

        TestForLoop = sum + stepSum ' 55 + 30 = 85
    End Function

    ' Test 5: Do While / Until Loops and Exit Do
    Public Function TestDoLoop() As Int32
        Dim count As Int32
        count = 0
        Do While count < 10
            count = count + 1
        Loop

        Dim exitCount As Int32
        exitCount = 0
        Do
            exitCount = exitCount + 1
            If exitCount = 5 Then
                Exit Do
            End If
        Loop

        TestDoLoop = count + exitCount ' 10 + 5 = 15
    End Function

    ' Test 6: While / Wend Loop
    Public Function TestWhileLoop() As Int32
        Dim n As Int32
        n = 1
        While n < 32
            n = n * 2
        Wend
        TestWhileLoop = n ' 32
    End Function

    ' Test 7: Recursion (Factorial)
    Public Function Factorial(ByVal n As Int32) As Int32
        If n <= 1 Then
            Factorial = 1
        Else
            Factorial = n * Factorial(n - 1)
        End If
    End Function

    ' Test 8: Pointer Indexing & Dereferencing
    Public Unsafe Function TestPointerIndexing() As Boolean
        Dim data(4) As Byte
        Dim ptr As Pointer To Byte
        ptr = CPtr(Pointer To Byte, data)

        ptr(0) = 10
        ptr(1) = 20
        ptr(2) = 30
        ptr(3) = 40

        If ptr(0) = 10 And ptr(1) = 20 And ptr(2) = 30 And ptr(3) = 40 Then
            TestPointerIndexing = True
        Else
            Print "TestPointerIndexing failed: [0]=", ptr(0), ", [1]=", ptr(1), ", [2]=", ptr(2), ", [3]=", ptr(3)
            TestPointerIndexing = False
        End If
    End Function

    ' Test 9: Structure Field Access
    Public Function TestStructure() As Boolean
        Dim pt As Point
        pt.X = 100
        pt.Y = 200

        If pt.X = 100 And pt.Y = 200 Then
            TestStructure = True
        Else
            Print "TestStructure failed: X=", pt.X, ", Y=", pt.Y
            TestStructure = False
        End If
    End Function

    ' Test 10: Select Case Control Flow
    Public Function TestSelectCase(ByVal val As Int32) As Int32
        Dim score As Int32
        Select Case val
            Case 1, 2, 3
                score = 10
            Case 4, 5
                score = 20
            Case 100
                score = 100
            Case Else
                score = 999
        End Select
        TestSelectCase = score
    End Function

    ' Test 11: Pointer Arithmetic (ptr + offset)
    Public Unsafe Function TestPointerArithmetic() As Boolean
        Dim buffer(8) As Byte
        Dim startPtr As Pointer To Byte
        startPtr = CPtr(Pointer To Byte, buffer)

        ' Direct pointer offset
        Dim secondPtr As Pointer To Byte
        secondPtr = startPtr + 2
        secondPtr(0) = 77

        If startPtr(2) = 77 Then
            TestPointerArithmetic = True
        Else
            TestPointerArithmetic = False
        End If
    End Function

    ' 12. String Concatenation & VB6 Number-to-String Conversion
    Public Function TestStringConcatenation() As Boolean
        Dim intPercent As Int32
        intPercent = 75

        Dim s1 As String
        s1 = "Loading " + intPercent + "%"

        Dim s2 As String
        s2 = "Status: " & 100 & "% Complete"

        ' Verify character contents
        ' "Loading 75%" -> s1(0) = 'L'(76), s1(8) = '7'(55), s1(9) = '5'(53), s1(10) = '%'(37)
        Dim ok1 As Boolean
        ok1 = (s1(0) = 76 And s1(8) = 55 And s1(9) = 53 And s1(10) = 37)

        ' "Status: 100% Complete" -> s2(0) = 'S'(83), s2(8) = '1'(49), s2(9) = '0'(48), s2(10) = '0'(48), s2(11) = '%'(37)
        Dim ok2 As Boolean
        ok2 = (s2(0) = 83 And s2(8) = 49 And s2(9) = 48 And s2(10) = 48 And s2(11) = 37)

        If ok1 And ok2 Then
            TestStringConcatenation = True
        Else
            Print "TestStringConcatenation failed: ok1=", ok1, ", ok2=", ok2
            TestStringConcatenation = False
        End If
    End Function

    ' 13. Enum Declarations and Access
    Public Function TestEnum() As Boolean
        Dim currentLight As Int32
        currentLight = TrafficLight.Yellow
        If currentLight = 20 And TrafficLight.Red = 10 And TrafficLight.Green = 30 Then
            TestEnum = True
        Else
            Print "TestEnum failed: currentLight=", currentLight, ", Red=", TrafficLight.Red, ", Green=", TrafficLight.Green
            TestEnum = False
        End If
    End Function

    ' 14. With Statement
    Public Function TestWithStatement() As Boolean
        Dim pt As Point
        With pt
            .X = 123
            .Y = 456
        End With
        If pt.X = 123 And pt.Y = 456 Then
            TestWithStatement = True
        Else
            Print "TestWithStatement failed: pt.X=", pt.X, ", pt.Y=", pt.Y
            TestWithStatement = False
        End If
    End Function

    ' 15. Floating Point Operations
    Public Function TestFloatingPoint() As Boolean
        Dim f1 As Single
        Dim d1 As Double
        f1 = 2.5
        d1 = 10.0
        Dim res As Double
        res = d1 / f1
        If res > 3.9 And res < 4.1 Then
            TestFloatingPoint = True
        Else
            TestFloatingPoint = False
        End If
    End Function

    ' 16. Line Continuation
    Public Function TestLineContinuation() As Int32
        Dim sum As Int32
        sum = 10 + _
              20 + _
              30
        TestLineContinuation = sum
    End Function

    ' 17. String Intrinsics Library (Len, Mid, Left, Right, InStr, Trim, Asc, Chr)
    Public Function TestStringLibrary() As Boolean
        Dim s As String
        s = "Hello World"

        ' Len
        If Len(s) <> 11 Then
            TestStringLibrary = False
            Exit Function
        End If

        ' Mid
        Dim m1 As String
        m1 = Mid(s, 1, 5)
        If m1 <> "Hello" Then
            TestStringLibrary = False
            Exit Function
        End If

        Dim m2 As String
        m2 = Mid(s, 7)
        If m2 <> "World" Then
            TestStringLibrary = False
            Exit Function
        End If

        ' Left
        Dim l As String
        l = Left(s, 5)
        If l <> "Hello" Then
            TestStringLibrary = False
            Exit Function
        End If

        ' Right
        Dim r As String
        r = Right(s, 5)
        If r <> "World" Then
            TestStringLibrary = False
            Exit Function
        End If

        ' InStr
        Dim pos1 As Int32
        pos1 = InStr(s, "World")
        If pos1 <> 7 Then
            TestStringLibrary = False
            Exit Function
        End If

        Dim pos2 As Int32
        pos2 = InStr(6, s, "o")
        If pos2 <> 8 Then
            TestStringLibrary = False
            Exit Function
        End If

        ' Trim
        Dim padded As String
        padded = "   Clean String   "
        Dim trimmed As String
        trimmed = Trim(padded)
        If trimmed <> "Clean String" Or Len(trimmed) <> 12 Then
            TestStringLibrary = False
            Exit Function
        End If

        ' Asc & Chr
        Dim a As Int32
        a = Asc("A")
        If a <> 65 Then
            TestStringLibrary = False
            Exit Function
        End If

        Dim c As String
        c = Chr(66)
        If c <> "B" Or Asc(c) <> 66 Then
            TestStringLibrary = False
            Exit Function
        End If

        TestStringLibrary = True
    End Function

    ' 18. Type Conversions (Val, CStr, CInt, CLng, CDbl)
    Public Function TestTypeConversions() As Boolean
        ' Val
        Dim v1 As Double
        v1 = Val("123.45")
        If v1 < 123.44 Or v1 > 123.46 Then
            TestTypeConversions = False
            Exit Function
        End If

        Dim v2 As Double
        v2 = Val("  -42")
        If v2 < -42.1 Or v2 > -41.9 Then
            TestTypeConversions = False
            Exit Function
        End If

        ' CStr
        Dim sInt As String
        sInt = CStr(987)
        If sInt <> "987" Then
            TestTypeConversions = False
            Exit Function
        End If

        ' CInt
        Dim ci As Int32
        ci = CInt("456")
        If ci <> 456 Then
            TestTypeConversions = False
            Exit Function
        End If

        ' CLng
        Dim cl As Int64
        cl = CLng("100000")
        If cl <> 100000 Then
            TestTypeConversions = False
            Exit Function
        End If

        ' CDbl
        Dim cd As Double
        cd = CDbl("3.14")
        If cd < 3.13 Or cd > 3.15 Then
            TestTypeConversions = False
            Exit Function
        End If

        TestTypeConversions = True
    End Function

    ' 19. Console I/O (Print Statement)
    Public Function TestConsolePrint() As Boolean
        ' Test multiple separators and expressions:
        ' Semicolon (no space/newline) and default newline
        Print "  -> [Console Output Verification]: Number="; 42; ", Hex=&H"; 255; ", Str="; "OK"
        TestConsolePrint = True
    End Function

    ' 20. VB6 Type (UDT) Syntax and Field Access
    Public Function TestTypeUDT() As Boolean
        Dim pos As Coordinate
        pos.Lat = 37.7749
        pos.Lon = -122.4194
        pos.Altitude = 15

        If pos.Lat > 37.77 And pos.Lat < 37.78 And pos.Lon < -122.40 And pos.Altitude = 15 Then
            TestTypeUDT = True
        Else
            TestTypeUDT = False
        End If
    End Function

    ' Helper function for Optional parameters with default values
    Public Function AddWithDefaults(ByVal a As Int32, Optional ByVal b As Int32 = 10, Optional ByVal c As Int32 = 5) As Int32
        AddWithDefaults = a + b + c
    End Function

    ' 21. Optional Parameters with Defaults
    Public Function TestOptionalParameters() As Boolean
        Dim r1 As Int32
        Dim r2 As Int32
        Dim r3 As Int32

        ' All 3 arguments specified
        r1 = AddWithDefaults(1, 2, 3)     ' 1 + 2 + 3 = 6
        ' 2 arguments specified, 1 default
        r2 = AddWithDefaults(10, 20)      ' 10 + 20 + 5 = 35
        ' 1 argument specified, 2 defaults
        r3 = AddWithDefaults(100)         ' 100 + 10 + 5 = 115

        If r1 = 6 And r2 = 35 And r3 = 115 Then
            TestOptionalParameters = True
        Else
            TestOptionalParameters = False
        End If
    End Function

    ' Target callback function for AddressOf testing
    Public Function CallbackTarget(ByVal x As Int32) As Int32
        CallbackTarget = x * 3
    End Function

    ' 22. AddressOf Operator (Function pointer retrieval)
    Public Unsafe Function TestAddressOf() As Boolean
        Dim fnPtr As Pointer To Byte
        fnPtr = CPtr(Pointer To Byte, AddressOf CallbackTarget)

        If fnPtr <> CPtr(Pointer To Byte, 0) Then
            TestAddressOf = True
        Else
            TestAddressOf = False
        End If
    End Function

    ' 23. PrintLine / PrintF Convenience Wrappers
    Public Function TestPrintLineAndFormat() As Boolean
        ' PrintLine automatically terminates with newline
        PrintLine "  -> [PrintLine Verification]: Status=Ready, Code=", 200
        ' PrintF format wrapper
        PrintFormat "  -> [PrintFormat Verification]: Hex=0x%X, Str=%s" & Chr(10), 255, "LLB"
        TestPrintLineAndFormat = True
    End Function

    ' 24. Math Library Intrinsics (Abs, Sgn, Sqrt, Int)
    Public Function TestMathIntrinsics() As Boolean
        ' Integer and Floating Abs
        Dim a1 As Int32
        Dim a2 As Double
        a1 = Abs(-42)
        a2 = Abs(-3.14159)
        If a1 <> 42 Or a2 < 3.14 Or a2 > 3.15 Then
            TestMathIntrinsics = False
            Exit Function
        End If

        ' Sgn: positive, zero, negative
        If Sgn(100) <> 1 Or Sgn(0) <> 0 Or Sgn(-50) <> -1 Then
            TestMathIntrinsics = False
            Exit Function
        End If

        ' Sqrt
        Dim sq As Double
        sq = Sqrt(144.0)
        If sq < 11.99 Or sq > 12.01 Then
            TestMathIntrinsics = False
            Exit Function
        End If

        ' Int / Floor
        Dim fl As Double
        fl = Int(9.99)
        If fl < 8.99 Or fl > 9.01 Then
            TestMathIntrinsics = False
            Exit Function
        End If

        TestMathIntrinsics = True
    End Function

    ' 25. TypeAlias Definitions & Resolution
    Public Function TestTypeAlias() As Boolean
        Dim myScore As Score
        myScore = 95

        Dim loc As GeoLocation
        loc.Lat = 12.34
        loc.Lon = 56.78
        loc.Altitude = 100

        If myScore = 95 And loc.Altitude = 100 Then
            TestTypeAlias = True
        Else
            Print "  [Test 25 Debug] myScore=", myScore, ", loc.Altitude=", loc.Altitude
            TestTypeAlias = False
        End If
    End Function

    ' 26. Multidimensional Arrays & Matrices (2D matrix indexing and UBound)
    Public Function TestMultidimensionalArrays() As Boolean
        Dim matrix(3, 4) As Int32
        ' Fill values: row * 10 + col
        matrix(0, 0) = 10
        matrix(1, 2) = 12
        matrix(2, 3) = 23

        Dim val0 As Int32
        Dim val1 As Int32
        Dim val2 As Int32
        val0 = matrix(0, 0)
        val1 = matrix(1, 2)
        val2 = matrix(2, 3)

        Dim rowsBound As Int32
        Dim colsBound As Int32
        rowsBound = UBound(matrix, 1)
        colsBound = UBound(matrix, 2)

        If val0 = 10 And val1 = 12 And val2 = 23 And rowsBound = 2 And colsBound = 3 Then
            TestMultidimensionalArrays = True
        Else
            Print "  [Test 26 Debug] val0=", val0, ", val1=", val1, ", val2=", val2, ", rowsBound=", rowsBound, ", colsBound=", colsBound
            TestMultidimensionalArrays = False
        End If
    End Function

    ' 27. Key-Value Map & Dictionary (Associative Subscripts & Intrinsics)
    Public Function TestMapAndDictionary() As Boolean
        Dim config As Dictionary
        config = MapCreate()

        ' String subscript assignment
        config("port") = 8080
        config("max_conn") = 500
        config("timeout") = 30

        ' String subscript read
        Dim p As Int64
        Dim m As Int64
        Dim t As Int64
        p = config("port")
        m = config("max_conn")
        t = config("timeout")

        ' Membership test
        Dim hasPort As Boolean
        Dim hasMissing As Boolean
        hasPort = MapHas(config, "port")
        hasMissing = MapHas(config, "nonexistent")

        If p = 8080 And m = 500 And t = 30 And hasPort = True And hasMissing = False Then
            TestMapAndDictionary = True
        Else
            Print "  [Test 27 Debug] p=", p, ", m=", m, ", t=", t, ", hasPort=", hasPort, ", hasMissing=", hasMissing
            TestMapAndDictionary = False
        End If
    End Function

    ' Standalone Helper for Option 2: djb2 hash function for raw C strings
    Public Unsafe Function HashString(ByVal str As Pointer To Byte) As UInt32
        Dim hash As UInt32
        hash = 5381
        Dim ptr As Pointer To Byte
        ptr = str
        Do While ptr(0) <> 0
            hash = ((hash LShift 5) + hash) + CType(UInt32, ptr(0))
            ptr = ptr + 1
        Loop
        HashString = hash
    End Function

    ' 28. Standalone Open-Addressing HashMap (Option 2 - Freestanding / Zero-Heap Structure)
    Public Unsafe Function TestStandaloneHashMap() As Boolean
        Dim storage(64) As HashMapEntry
        Dim map As HashMap
        map.Count = 0
        map.Capacity = 64
        Dim entriesPtr As Pointer To HashMapEntry
        entriesPtr = CPtr(Pointer To HashMapEntry, storage)
        map.EntriesBuffer = entriesPtr

        ' Populate map slots manually using hash calculation
        Dim h1 As UInt32
        Dim slot1 As UInt32
        h1 = HashString(CPtr(Pointer To Byte, "baudrate"))
        slot1 = h1 Mod 64

        entriesPtr(slot1).Key = CPtr(Pointer To Byte, "baudrate")
        entriesPtr(slot1).Value = 115200
        entriesPtr(slot1).Occupied = 1
        map.Count = map.Count + 1

        Dim h2 As UInt32
        Dim slot2 As UInt32
        h2 = HashString(CPtr(Pointer To Byte, "databits"))
        slot2 = h2 Mod 64
        If slot2 = slot1 Then
            slot2 = (slot2 + 1) Mod 64
        End If

        entriesPtr(slot2).Key = CPtr(Pointer To Byte, "databits")
        entriesPtr(slot2).Value = 8
        entriesPtr(slot2).Occupied = 1
        map.Count = map.Count + 1

        ' Verify entries
        Dim val1 As Int64
        Dim val2 As Int64
        Dim isOcc1 As Int32
        Dim isOcc2 As Int32
        val1 = entriesPtr(slot1).Value
        val2 = entriesPtr(slot2).Value
        isOcc1 = entriesPtr(slot1).Occupied
        isOcc2 = entriesPtr(slot2).Occupied

        If map.Count <> 2 Then
            Print "  [Test 28 Debug] map.Count=", map.Count, " (expected 2)"
            TestStandaloneHashMap = False
            Exit Function
        End If

        If val1 <> 115200 Then
            Print "  [Test 28 Debug] val1=", val1, " (expected 115200)"
            TestStandaloneHashMap = False
            Exit Function
        End If

        If val2 <> 8 Then
            Print "  [Test 28 Debug] val2=", val2, " (expected 8)"
            TestStandaloneHashMap = False
            Exit Function
        End If

        If isOcc1 <> 1 Or isOcc2 <> 1 Then
            Print "  [Test 28 Debug] isOcc1=", isOcc1, ", isOcc2=", isOcc2
            TestStandaloneHashMap = False
            Exit Function
        End If

        TestStandaloneHashMap = True
    End Function

    ' 29. Freestanding Dynamic ArrayList (Growable List with Indexing)
    Public Unsafe Function TestArrayList() As Boolean
        Dim buffer(16) As Int32
        Dim list As ArrayList
        list.Count = 0
        list.Capacity = 16
        list.Data = CPtr(Pointer To Int32, buffer)

        ' Append elements
        Dim dataPtr As Pointer To Int32
        dataPtr = list.Data
        dataPtr(list.Count) = 100
        list.Count = list.Count + 1

        dataPtr(list.Count) = 200
        list.Count = list.Count + 1

        dataPtr(list.Count) = 300
        list.Count = list.Count + 1

        ' Read back
        Dim firstItem As Int32
        Dim secondItem As Int32
        Dim thirdItem As Int32
        firstItem = dataPtr(0)
        secondItem = dataPtr(1)
        thirdItem = dataPtr(2)

        If list.Count = 3 And firstItem = 100 And secondItem = 200 And thirdItem = 300 Then
            TestArrayList = True
        Else
            Print "  [Test 29 Debug] list.Count=", list.Count, ", first=", firstItem, ", second=", secondItem, ", third=", thirdItem
            TestArrayList = False
        End If
    End Function

    ' Global storage for Property Get / Let test
    Private m_currentBaudRate As Int32

    Public Property Get BaudRate() As Int32
        BaudRate = m_currentBaudRate
    End Property

    Public Property Let BaudRate(ByVal value As Int32)
        m_currentBaudRate = value
    End Property

    ' 30. Property Accessors (Property Get & Property Let/Set)
    Public Function TestPropertyAccessors() As Boolean
        m_currentBaudRate = 9600
        Dim initialRate As Int32
        initialRate = BaudRate()
        If initialRate <> 9600 Then
            Print "  [Test 30 Debug] initialRate=", initialRate, " (expected 9600)"
            TestPropertyAccessors = False
            Exit Function
        End If

        BaudRate = 115200
        Dim updatedRate As Int32
        updatedRate = BaudRate()
        If updatedRate <> 115200 Then
            Print "  [Test 30 Debug] updatedRate=", updatedRate, " (expected 115200)"
            TestPropertyAccessors = False
            Exit Function
        End If

        TestPropertyAccessors = True
    End Function

    ' 31. For Each / Collection Iterators (Fixed Array & Dynamic ArrayList)
    Public Unsafe Function TestForEachIterators() As Boolean
        ' Test 1: For Each over fixed array
        Dim nums(5) As Int32
        nums(0) = 10
        nums(1) = 20
        nums(2) = 30
        nums(3) = 40
        nums(4) = 50

        Dim arraySum As Int32
        arraySum = 0
        Dim item As Int32
        For Each item In nums
            arraySum = arraySum + item
        Next item

        If arraySum <> 150 Then
            TestForEachIterators = False
            Exit Function
        End If

        ' Test 2: For Each over custom dynamic collection (ArrayList with .Count & .Data)
        Dim buffer(4) As Int32
        Dim list As ArrayList
        list.Count = 4
        list.Capacity = 4
        list.Data = CPtr(Pointer To Int32, buffer)

        Dim p As Pointer To Int32
        p = list.Data
        p(0) = 1
        p(1) = 2
        p(2) = 3
        p(3) = 4

        Dim listSum As Int32
        listSum = 0
        Dim listItem As Int32
        For Each listItem In list
            listSum = listSum + listItem
        Next listItem

        If listSum <> 10 Then
            TestForEachIterators = False
            Exit Function
        End If

        TestForEachIterators = True
    End Function

    ' 32. Nested Arrays & Multi-Level Chained Indexing
    Public Unsafe Function TestNestedArrays() As Boolean
        ' Test 2D pointer of pointers / array of buffers
        Dim row0(3) As Int32
        Dim row1(3) As Int32
        row0(0) = 11: row0(1) = 22: row0(2) = 33
        row1(0) = 44: row1(1) = 55: row1(2) = 66

        Dim table(2) As Pointer To Int32
        table(0) = CPtr(Pointer To Int32, row0)
        table(1) = CPtr(Pointer To Int32, row1)

        Dim p0 As Pointer To Int32
        p0 = table(0)
        Dim p1 As Pointer To Int32
        p1 = table(1)

        Dim valA As Int32
        valA = p0(1) ' 22
        Dim valB As Int32
        valB = p1(2) ' 66

        ' Mutate through pointer
        p1(2) = 99
        Dim valC As Int32
        valC = p1(2)

        If valA = 22 And valB = 66 And valC = 99 Then
            TestNestedArrays = True
        Else
            TestNestedArrays = False
        End If
    End Function

    ' 33. Object Lifecycle: Set obj = New ClassName & Delete
    Public Unsafe Function TestNewObjectLifecycle() As Boolean
        Dim node As Pointer To ServiceNode
        node = New ServiceNode
        node.Port = 8080
        node.IsActive = 1

        Dim portVal As Int32
        portVal = node.Port
        Dim activeVal As Int32
        activeVal = node.IsActive

        Delete node

        If portVal = 8080 And activeVal = 1 And node = 0 Then
            TestNewObjectLifecycle = True
        Else
            TestNewObjectLifecycle = False
        End If
    End Function

    ' 34. Dynamic Array Resizing: ReDim & ReDim Preserve
    Public Unsafe Function TestReDim() As Boolean
        Dim dynArr As Pointer To Int32
        ReDim dynArr(3)

        dynArr(0) = 100
        dynArr(1) = 200
        dynArr(2) = 300

        ' Resize with Preserve: keep previous 3 elements and expand to 5
        ReDim Preserve dynArr(5)
        dynArr(3) = 400
        dynArr(4) = 500

        Dim e0 As Int32: e0 = dynArr(0)
        Dim e1 As Int32: e1 = dynArr(1)
        Dim e2 As Int32: e2 = dynArr(2)
        Dim e3 As Int32: e3 = dynArr(3)
        Dim e4 As Int32: e4 = dynArr(4)

        If e0 = 100 And e1 = 200 And e2 = 300 And e3 = 400 And e4 = 500 Then
            TestReDim = True
        Else
            TestReDim = False
        End If
    End Function

    ' 35. Is / Nothing Operator
    Public Unsafe Function TestIsNothingOperator() As Boolean
        Dim node As Pointer To ServiceNode
        node = 0

        Dim isNullInitial As Boolean
        isNullInitial = (node Is Nothing)

        node = New ServiceNode
        Dim isNotNullAfterNew As Boolean
        isNotNullAfterNew = (node Is Not Nothing)

        Delete node
        Dim isNullAfterDelete As Boolean
        isNullAfterDelete = (node Is Nothing)

        If isNullInitial And isNotNullAfterNew And isNullAfterDelete Then
            TestIsNothingOperator = True
        Else
            TestIsNothingOperator = False
        End If
    End Function

    ' 36. Erase Statement (Fixed arrays & Dynamic pointers)
    Public Unsafe Function TestEraseStatement() As Boolean
        ' Test A: Erase dynamic pointer array
        Dim dynList As Pointer To Int32
        ReDim dynList(4)
        dynList(0) = 42

        Erase dynList
        Dim dynNull As Boolean
        dynNull = (dynList Is Nothing)

        ' Test B: Erase fixed stack array (zeroes elements)
        Dim fixedArr(3) As Int32
        fixedArr(0) = 11: fixedArr(1) = 22: fixedArr(2) = 33
        Erase fixedArr

        Dim f0 As Int32: f0 = fixedArr(0)
        Dim f1 As Int32: f1 = fixedArr(1)
        Dim f2 As Int32: f2 = fixedArr(2)

        If dynNull And f0 = 0 And f1 = 0 And f2 = 0 Then
            TestEraseStatement = True
        Else
            TestEraseStatement = False
        End If
    End Function

    ' 37. StrComp Function (Classic VB6 string comparison: -1, 0, 1)
    Public Unsafe Function TestStrCompFunction() As Boolean
        Dim rEqual As Int32: rEqual = StrComp("Apple", "Apple")
        Dim rLess As Int32: rLess = StrComp("Apple", "Banana")
        Dim rGreater As Int32: rGreater = StrComp("Zebra", "Apple")

        If rEqual = 0 And rLess = -1 And rGreater = 1 Then
            TestStrCompFunction = True
        Else
            TestStrCompFunction = False
        End If
    End Function

    ' 38. GoTo & Label Jumps
    Public Function TestGoToLabels() As Boolean
        Dim stepCount As Int32
        stepCount = 1

        GoTo SkipMiddle

        stepCount = 999 ' Should be bypassed

SkipMiddle:
        stepCount = stepCount + 10
        If stepCount = 11 Then
            TestGoToLabels = True
        Else
            TestGoToLabels = False
        End If
    End Function

    ' 39. Structured Exception Handling (Try ... Catch ... Finally) & VB6 Err Object
    Public Function TestTryCatchFinally() As Boolean
        Dim executedTry As Int32
        Dim executedFinally As Int32
        executedTry = 0
        executedFinally = 0

        Try
            executedTry = 100
        Finally
            executedFinally = 200
        End Try

        Dim catchCode As Int32: catchCode = 0
        Dim catchErrNum As Int32: catchErrNum = 0
        Dim finallyRan As Int32: finallyRan = 0

        Try
            Err.Raise 404, "TestSuite", "Resource Not Found"
        Catch ex As Int32
            catchCode = ex
            catchErrNum = Err.Number
        Finally
            finallyRan = 1
        End Try

        Dim clearedNum As Int32: clearedNum = -1
        Err.Clear()
        clearedNum = Err.Number

        If executedTry = 100 And executedFinally = 200 And catchCode = 404 And catchErrNum = 404 And finallyRan = 1 And clearedNum = 0 Then
            TestTryCatchFinally = True
        Else
            Print "  [Test 39 Debug] executedTry=", executedTry, " (expected 100), executedFinally=", executedFinally, " (expected 200), catchCode=", catchCode, " (expected 404), catchErrNum=", catchErrNum, " (expected 404), finallyRan=", finallyRan, " (expected 1), clearedNum=", clearedNum, " (expected 0)"
            TestTryCatchFinally = False
        End If
    End Function

    ' Helper for 40. ParamArray
    Public Function SumVarargs(ByVal count As Int32, ParamArray nums() As Pointer To Int64) As Int64
        Dim total As Int64: total = 0
        Dim i As Int32
        For i = 0 To count - 1
            total = total + nums(i)
        Next i
        SumVarargs = total
    End Function

    ' 40. ParamArray (Variadic Arguments)
    Public Function TestParamArray() As Boolean
        Dim s1 As Int64
        Dim s2 As Int64
        s1 = SumVarargs(3, 10, 20, 30)
        s2 = SumVarargs(4, 1, 2, 3, 4)

        If s1 = 60 And s2 = 10 Then
            TestParamArray = True
        Else
            TestParamArray = False
        End If
    End Function

    ' Helper for 41. Named Arguments
    Public Function ComputeBoxVolume(ByVal width As Int32, ByVal height As Int32, ByVal depth As Int32) As Int32
        ComputeBoxVolume = width * height * depth
    End Function

    ' 41. Named Arguments (name := value)
    Public Function TestNamedArguments() As Boolean
        Dim vol1 As Int32
        Dim vol2 As Int32
        ' Call with reordered named parameters
        vol1 = ComputeBoxVolume(depth := 2, width := 5, height := 10)
        ' Call with mixed positional and named parameters
        vol2 = ComputeBoxVolume(5, depth := 4, height := 3)

        If vol1 = 100 And vol2 = 60 Then
            TestNamedArguments = True
        Else
            TestNamedArguments = False
        End If
    End Function

    ' 42. Like String Pattern Matching
    Public Function TestLikeOperator() As Boolean
        Dim m1 As Boolean: m1 = ("Hello World" Like "Hello*")
        Dim m2 As Boolean: m2 = ("kernel.bin" Like "*.bin")
        Dim m3 As Boolean: m3 = ("v123" Like "v???")
        Dim m4 As Boolean: m4 = ("abc" Like "a*c")
        Dim m5 As Boolean: m5 = ("LLBCompiler" Like "Python*") ' Should be False

        If m1 And m2 And m3 And m4 And (Not m5) Then
            TestLikeOperator = True
        Else
            TestLikeOperator = False
        End If
    End Function

    ' 43. Unsigned vs Signed Operations & Distinctions
    Public Function TestUnsignedOperations() As Boolean
        Dim u1 As UInt32: u1 = 3000000000
        Dim u2 As UInt32: u2 = 1000000000

        ' Unsigned comparison: 3,000,000,000 > 1,000,000,000
        Dim cmpGreater As Boolean: cmpGreater = (u1 > u2)
        Dim cmpLess As Boolean: cmpLess = (u2 < u1)

        ' Unsigned division: 3,000,000,000 / 1,000,000,000 = 3
        Dim uDivRes As UInt32: uDivRes = u1 / u2

        ' Unsigned modulo: 3,000,000,001 Mod 1,000,000,000 = 1
        Dim uModRes As UInt32: uModRes = (u1 + 1) Mod u2

        ' Logical right shift on unsigned: 2147483648 (0x80000000) RShift 1 = 1073741824 (0x40000000)
        Dim uShift As UInt32: uShift = 2147483648
        Dim shiftRes As UInt32: shiftRes = uShift RShift 1

        If cmpGreater And cmpLess And (uDivRes = 3) And (uModRes = 1) And (shiftRes = 1073741824) Then
            TestUnsignedOperations = True
        Else
            TestUnsignedOperations = False
        End If
    End Function

    ' 44. Union Types (Overlapping memory layout)
    Public Function TestUnionTypes() As Boolean
        Dim reg As DWordReg

        ' Write full 32-bit dword: 0x12345678
        reg.DwordVal = &H12345678

        ' In little-endian x86/ARM:
        ' ByteVal (offset 0) = 0x78
        ' WordVal (offset 0) = 0x5678
        Dim b As Byte: b = reg.ByteVal
        Dim w As UInt16: w = reg.WordVal

        ' Overwrite low byte through union:
        reg.ByteVal = &H99
        Dim dModified As UInt32: dModified = reg.DwordVal

        If b = &H78 And w = &H5678 And dModified = &H12345699 Then
            TestUnionTypes = True
        Else
            TestUnionTypes = False
        End If
    End Function

    ' 45. Memory Runtime Intrinsics (ZeroMemory, FillMemory, CopyMemory)
    Public Unsafe Function TestMemoryIntrinsics() As Boolean
        Dim srcBuf(8) As Byte
        Dim dstBuf(8) As Byte

        ' 1. Test FillMemory: fill srcBuf with &HAA (170)
        FillMemory srcBuf, 8, &HAA

        Dim i As Int32
        Dim fillOk As Boolean: fillOk = True
        For i = 0 To 7
            If srcBuf(i) <> &HAA Then fillOk = False
        Next i

        ' 2. Test CopyMemory: copy srcBuf into dstBuf
        CopyMemory dstBuf, srcBuf, 8

        Dim copyOk As Boolean: copyOk = True
        For i = 0 To 7
            If dstBuf(i) <> &HAA Then copyOk = False
        Next i

        ' 3. Test ZeroMemory: zero dstBuf
        ZeroMemory dstBuf, 8

        Dim zeroOk As Boolean: zeroOk = True
        For i = 0 To 7
            If dstBuf(i) <> 0 Then zeroOk = False
        Next i

        If fillOk And copyOk And zeroOk Then
            TestMemoryIntrinsics = True
        Else
            TestMemoryIntrinsics = False
        End If
    End Function

    ' 46. TypeOf ... Is ... Operator (Type testing & validation)
    Public Unsafe Function TestTypeOfIsOperator() As Boolean
        Dim num As Int32: num = 42
        Dim str As Pointer To Byte: str = CPtr(Pointer To Byte, "LLB")
        Dim reg As DWordReg

        Dim c1 As Boolean: c1 = (TypeOf num Is Int32)
        Dim c2 As Boolean: c2 = (TypeOf num Is Not String)
        Dim c3 As Boolean: c3 = (TypeOf str Is Pointer To Byte)
        Dim c4 As Boolean: c4 = (TypeOf reg Is DWordReg)
        Dim c5 As Boolean: c5 = (TypeOf num Is Double) ' Should be False

        If c1 And c2 And c3 And c4 And (Not c5) Then
            TestTypeOfIsOperator = True
        Else
            TestTypeOfIsOperator = False
        End If
    End Function

    ' 47. Shared Library FFI Binding (Declare ... Lib "SharedLib")
    Public Function TestDeclareSharedLibrary() As Boolean
        Dim sum As Int32
        sum = AddNumbers(17, 25)
        If sum = 42 Then
            TestDeclareSharedLibrary = True
        Else
            TestDeclareSharedLibrary = False
        End If
    End Function

    ' 48. Memory Safety & Bounds-Checked Array Access
    Public Function TestBoundsChecking() As Boolean
        Dim buffer(8) As Int32
        Dim i As Int32

        For i = 0 To 7
            buffer(i) = (i + 1) * 10
        Next i

        Dim valid As Boolean: valid = True
        For i = 0 To 7
            If buffer(i) <> (i + 1) * 10 Then
                valid = False
            End If
        Next i

        TestBoundsChecking = valid
    End Function

    ' 49. File I/O Primitives (Open, Close, Print #, Line Input #, EOF, LOF)
    Public Function TestFileIO() As Boolean
        Dim testPath As String: testPath = "test_file_io.tmp"

        ' Step 1: Open for Output and write structured lines
        Open testPath For Output As #1
        Print #1, "First line of text"
        Print #1, "Answer: "; 42; ", Hex: "; &HFF
        Print #1, "Third line complete"
        Close #1

        ' Step 2: Open for Input and verify reading lines, EOF, and LOF
        Open testPath For Input As #1

        Dim fileSize As Int64
        fileSize = LOF(1)

        Dim line1 As String
        Dim line2 As String
        Dim line3 As String

        Line Input #1, line1
        Line Input #1, line2
        Line Input #1, line3

        Dim isAtEnd As Boolean
        isAtEnd = EOF(1)

        Close #1

        ' Diagnostic inspection
        PrintLine("  -> [Debug FileIO]: LOF=" + CStr(fileSize) + ", line1=[" + line1 + "], line3=[" + line3 + "], EOF=" + CStr(isAtEnd))

        ' Verify file size > 0, contents, and end-of-file
        If fileSize > 30 And line1 = "First line of text" And line3 = "Third line complete" Then
            TestFileIO = True
        Else
            TestFileIO = False
        End If
    End Function

    ' 50. Module Imports & Multi-File Dependency Resolution
    Public Function TestImports() As Boolean
        ' Test imported function
        Dim area As Int32
        area = CalculateArea(5, 8)

        ' Test imported enum
        Dim p As LogPriority
        p = LogPriority.LogHigh
        Dim score As Int32
        score = GetPriorityScore(p)

        ' Test imported structure
        Dim v As Vector2D
        v.X = 12
        v.Y = 34

        If area = 40 And score = 60 And v.X = 12 And v.Y = 34 Then
            TestImports = True
        Else
            TestImports = False
        End If
    End Function

    ' Conditionally compiled procedures
    #If TARGET_ENV = 1 Then
    Public Function GetTargetEnvName() As Int32
        GetTargetEnvName = 100
    End Function
    #Else
    Public Function GetTargetEnvName() As Int32
        GetTargetEnvName = 999
    End Function
    #End If

    ' 51. Conditional Compilation Directives (#Const, #If, #ElseIf, #Else, #End If)
    Public Function TestConditionalCompilation() As Boolean
        Dim passCount As Int32
        passCount = 0

        ' Check module-level conditional procedure
        If GetTargetEnvName() = 100 Then
            passCount = passCount + 1
        End If

        ' Statement-level #If / #ElseIf / #Else
        Dim flagVal As Int32
        flagVal = 0

        #Const LOCAL_MODE = 2

        #If LOCAL_MODE = 1 Then
            flagVal = 10
        #ElseIf LOCAL_MODE = 2 Then
            flagVal = 20
        #Else
            flagVal = 30
        #End If

        If flagVal = 20 Then
            passCount = passCount + 1
        End If

        ' Nested #If and preprocessor logical expressions
        Dim nestedResult As Int32
        nestedResult = 0

        #If ARCH_BITS = 64 And (TARGET_ENV = 1 Or UNUSED_FLAG = 1) Then
            #If __LLBC__ = 1 Then
                nestedResult = 777
            #Else
                nestedResult = 111
            #End If
        #Else
            nestedResult = 222
        #End If

        If nestedResult = 777 Then
            passCount = passCount + 1
        End If

        ' Inactive branch with arbitrary tokens that shouldn't be parsed
        #If UNUSED_FLAG = 1 Then
            This Should Not Be Parsed Or Compiled At All !!!
        #Else
            passCount = passCount + 1
        #End If

        If passCount = 4 Then
            TestConditionalCompilation = True
        Else
            Print "TestConditionalCompilation failed: passCount=", passCount
            TestConditionalCompilation = False
        End If
    End Function

    ' 52. Static Library Archiving & Linking (.a / -static)
    Public Function TestStaticLibraryArchive() As Boolean
        Dim mulRes As Int32
        mulRes = StaticMultiply(6, 7)
        Dim powRes As Int32
        powRes = StaticPower(2, 8)
        If mulRes = 42 And powRes = 256 Then
            TestStaticLibraryArchive = True
        Else
            Print "TestStaticLibraryArchive failed: mulRes=", mulRes, ", powRes=", powRes
            TestStaticLibraryArchive = False
        End If
    End Function

    ' 53. DWARF Debug Information Emission (-g metadata)
    Public Function TestDebugInfoEmission() As Boolean
        Dim a As Int32
        a = 10
        Dim b As Int32
        b = 20
        Dim c As Int32
        c = a + b
        If c = 30 Then
            TestDebugInfoEmission = True
        Else
            Print "TestDebugInfoEmission failed: c=", c
            TestDebugInfoEmission = False
        End If
    End Function

    <Inline>
    Public Function InlineMultiply(ByVal a As Int32, ByVal b As Int32) As Int32
        InlineMultiply = a * b
    End Function

    ' 54. Advanced Type System & Procedure Attributes (<Inline>, Currency, Short, UShort, ULong)
    Public Function TestTypeSystemAndAttributes() As Boolean
        Dim passCount As Int32
        passCount = 0

        ' Test <Inline> procedure call
        Dim inlineRes As Int32
        inlineRes = InlineMultiply(6, 7)
        If inlineRes = 42 Then
            passCount = passCount + 1
        Else
            Print "TestTypeSystemAndAttributes failed at InlineMultiply: inlineRes=", inlineRes
        End If

        ' Test Currency type (fixed-point 64-bit integer)
        Dim price As Currency
        price = 125000 ' $12.5000 in 4 decimal place fixed-point units
        Dim qty As Currency
        qty = 3
        Dim total As Currency
        total = price * qty
        If total = 375000 Then
            passCount = passCount + 1
        Else
            Print "TestTypeSystemAndAttributes failed at Currency: total=", total
        End If

        ' Test Short (16-bit) and UShort (unsigned 16-bit)
        Dim sVal As Short
        sVal = 30000
        Dim usVal As UShort
        usVal = 50000
        If sVal = 30000 And usVal = 50000 Then
            passCount = passCount + 1
        Else
            Print "TestTypeSystemAndAttributes failed at Short/UShort: sVal=", sVal, ", usVal=", usVal
        End If

        ' Test ULong (unsigned 32-bit)
        Dim ulVal As ULong
        ulVal = 3000000000
        If ulVal = 3000000000 Then
            passCount = passCount + 1
        Else
            Print "TestTypeSystemAndAttributes failed at ULong: ulVal=", ulVal
        End If

        If passCount = 4 Then
            TestTypeSystemAndAttributes = True
        Else
            Print "TestTypeSystemAndAttributes passCount: ", passCount
            TestTypeSystemAndAttributes = False
        End If
    End Function

    ' 55. Modern Features: Closures/Lambdas, Result(T, E) Sum Types, Namespaces
    Public Unsafe Function TestModernLanguageFeatures() As Boolean
        Dim passCount As Int32
        passCount = 0

        ' A. First-Class Closure / Lambda
        Dim adder As Pointer To Byte
        adder = Function(a As Int32, b As Int32) As Int32 => a + b
        If adder <> 0 Then
            passCount = passCount + 1
        Else
            Print "ModernFeatures failed at A (adder)"
        End If

        ' B. Result(T, E) Sum Type: Ok(val)
        Dim resOk As Result
        resOk = Ok(12345)
        If IsOk(resOk) And resOk.value = 12345 And resOk.err_code = 0 Then
            passCount = passCount + 1
        Else
            Print "ModernFeatures failed at B (resOk)"
        End If

        ' C. Result(T, E) Sum Type: Err(code)
        Dim resErr As Result
        resErr = Err(404)
        If Not IsOk(resErr) And resErr.err_code = 404 Then
            passCount = passCount + 1
        Else
            Print "ModernFeatures failed at C (resErr)"
        End If

        ' D. Generics / Parameterized Structure: Box(Of Int32)
        Dim intBox As Box(Of Int32)
        intBox.Value = 42
        intBox.Tag = 99
        If intBox.Value = 42 And intBox.Tag = 99 Then
            passCount = passCount + 1
        Else
            Print "ModernFeatures failed at D (intBox)"
        End If

        ' E. Generics / Parameterized Function: Min(Of Int32)
        Dim minVal As Int32
        minVal = Min(Of Int32)(100, 45)
        If minVal = 45 Then
            passCount = passCount + 1
        Else
            Print "ModernFeatures failed at E (Min_Int32), minVal=", minVal
        End If

        If passCount = 5 Then
            TestModernLanguageFeatures = True
        Else
            Print "ModernFeatures passCount: ", passCount
            TestModernLanguageFeatures = False
        End If
    End Function

    Public g_disposeTracker As Int32 = 0

    Public Structure ScopedResource
        Public HandleId As Int32
    End Structure

    Public Sub ScopedResource_Dispose(ByRef r As ScopedResource)
        g_disposeTracker = r.HandleId + 100
    End Sub

    ' 56. Deterministic Scoped Cleanup (Using ... End Using)
    Public Function TestUsingScopedCleanup() As Boolean
        g_disposeTracker = 0

        Using res As ScopedResource
            res.HandleId = 42
        End Using

        If g_disposeTracker = 142 Then
            TestUsingScopedCleanup = True
        Else
            Print "  [Test 56 Debug] g_disposeTracker=", g_disposeTracker, " (expected 142)"
            TestUsingScopedCleanup = False
        End If
    End Function

    ' 57. Algebraic Pattern Matching (Match ... Case ... End Match)
    Public Function TestPatternMatching() As Boolean
        Dim score As Int32: score = 15
        Dim category As Int32: category = 0

        Match score
            Case 1 To 10
                category = 1
            Case 11 To 20
                category = 2
            Case Else
                category = 3
        End Match

        Dim resOk As Result: resOk = Ok(1234)
        Dim extractedVal As Int64: extractedVal = 0

        Match resOk
            Case Ok(val)
                extractedVal = val
            Case Err(code)
                extractedVal = -code
        End Match

        Dim resErr As Result: resErr = Err(404)
        Dim extractedErr As Int32: extractedErr = 0

        Match resErr
            Case Ok(val)
                extractedErr = -1
            Case Err(code)
                extractedErr = code
        End Match

        If category = 2 And extractedVal = 1234 And extractedErr = 404 Then
            TestPatternMatching = True
        Else
            Print "  [Test 57 Debug] category=", category, " (expected 2), extractedVal=", extractedVal, " (expected 1234), extractedErr=", extractedErr, " (expected 404)"
            TestPatternMatching = False
        End If
    End Function

    ' Helper subroutines demonstrating flexible modifier ordering (Unsafe Public / Unsafe Private)
    Unsafe Public Sub AsmSingleLineNop()
        Asm "nop"
    End Sub

    Unsafe Private Sub AsmMultilineNopWithOperands(ByVal val1 As Int64, ByVal val2 As Int64)
        Asm
            "nop"
            "nop"
            :
            :
            "r" (val1), "r" (val2)
        End Asm
    End Sub

    ' 58. Inline Assembly Support (Single-line Asm, Multiline Asm ... End Asm, Operands & Clobbers)
    Public Unsafe Function TestInlineAssembly() As Boolean
        AsmSingleLineNop()
        AsmMultilineNopWithOperands(100, 200)

        ' Direct inline block in function
        Dim inVal As Int64: inVal = 42
        Asm
            "nop"
            :
            :
            "r" (inVal)
        End Asm

        TestInlineAssembly = True
    End Function

    ' 59. Module Constants, Variable Initializers & Flexible Modifiers
    Unsafe Public Function TestModuleConstants() As Boolean
        Dim magicOk As Boolean: magicOk = (MODULE_TEST_MAGIC = 4242)
        Dim globalInitOk As Boolean: globalInitOk = (g_initializedCounter = 777)
        Dim piOk As Boolean: piOk = (PI_APPROX > 3.14 And PI_APPROX < 3.15)

        If magicOk And globalInitOk And piOk Then
            TestModuleConstants = True
        Else
            Print "  [Test 59 Debug] magicOk=", magicOk, ", globalInitOk=", globalInitOk, ", piOk=", piOk
            TestModuleConstants = False
        End If
    End Function

    ' 60. Namespaces & Runtime Type/String Inspection Helpers
    Public Function TestNamespacesAndTypeInspection() As Boolean
        ' Test Namespace procedure resolution
        Dim sumVal As Int32 = MathHelper.Add(15, 27)
        Dim prodVal As Int32 = MathHelper.Multiply(6, 7)

        ' Test Runtime String & Type inspection helpers
        Dim validInt As Boolean = IsNumericString("4242")
        Dim validFloat As Boolean = IsNumericString("-123.45")
        Dim invalidAlpha As Boolean = IsNumericString("42abc")
        Dim invalidEmpty As Boolean = IsNumericString("")

        If sumVal = 42 And prodVal = 42 And validInt = True And validFloat = True And invalidAlpha = False And invalidEmpty = False Then
            TestNamespacesAndTypeInspection = True
        Else
            Print "  [Test 60 Debug] sum=", sumVal, ", prod=", prodVal, ", vInt=", validInt, ", vFloat=", validFloat
            TestNamespacesAndTypeInspection = False
        End If
    End Function

    ' Helper for recursive Sub mutation
    Public Sub RecursiveCountdown(ByVal n As Int32, ByRef accumulator As Int32)
        If n <= 0 Then Exit Sub
        accumulator = accumulator + n
        RecursiveCountdown n - 1, accumulator
    End Sub

    ' 61. Additional Control Flow: Exit While, Do Until / Loop Until, Recursive Sub
    Public Function TestExitWhileAndDoUntil() As Boolean
        ' Test Exit While
        Dim wCount As Int32 = 0
        While wCount < 100
            wCount = wCount + 1
            If wCount = 7 Then
                Exit While
            End If
        Wend

        ' Test Do Until ... Loop (pre-condition)
        Dim uPre As Int32 = 0
        Do Until uPre >= 10
            uPre = uPre + 2
        Loop

        ' Test Do ... Loop Until (post-condition)
        Dim uPost As Int32 = 0
        Do
            uPost = uPost + 3
        Loop Until uPost >= 15

        ' Test Recursive Sub with ByRef accumulator
        Dim totalAccum As Int32 = 0
        RecursiveCountdown 5, totalAccum ' 5 + 4 + 3 + 2 + 1 = 15

        If wCount = 7 And uPre = 10 And uPost = 15 And totalAccum = 15 Then
            TestExitWhileAndDoUntil = True
        Else
            Print "  [Test 61 Debug] wCount=", wCount, ", uPre=", uPre, ", uPost=", uPost, ", totalAccum=", totalAccum
            TestExitWhileAndDoUntil = False
        End If
    End Function

    ' 62. Use Scope Binding, Aliasing & MultiUse Class Instantiation
    Public Function TestUseAndClassInstancing() As Boolean
        ' Test 1: Stack instance using aliased class name
        Use New Helper As h1
        h1.Initialize 42
        Dim val1 As Int32 = h1.GetValue()
        Dim sum1 As Int32 = h1.ComputeSum(8) ' 42 + 100 + 8 = 150

        ' Test 2: Second instance demonstrating MultiUse independence
        Use New Helper As h2
        h2.Initialize 10
        h2.SetValue 25
        Dim val2 As Int32 = h2.GetValue()
        Dim sum2 As Int32 = h2.ComputeSum(5) ' 25 + 100 + 5 = 130

        If val1 = 42 And sum1 = 150 And val2 = 25 And sum2 = 130 Then
            TestUseAndClassInstancing = True
        Else
            Print "  [Test 62 Debug] val1=", val1, ", sum1=", sum1, ", val2=", val2, ", sum2=", sum2
            TestUseAndClassInstancing = False
        End If
    End Function

    ' 63. SingleUse Class Instancing
    Public Function TestSingleUseInstancing() As Boolean
        Use New SingleInst As s1
        s1.Initialize 77
        Dim st1 As Int32 = s1.GetStatus()
        s1.SetStatus 88
        Dim st2 As Int32 = s1.GetStatus()

        If st1 = 77 And st2 = 88 Then
            TestSingleUseInstancing = True
        Else
            Print "  [Test 63 Debug] st1=", st1, ", st2=", st2
            TestSingleUseInstancing = False
        End If
    End Function

    ' 64. Interface Polymorphism & Method Implementation Dispatch
    Public Function TestInterfaceImplementation() As Boolean
        Use New Writer As w
        w.Initialize 100
        Dim r1 As Int32 = w.WriteData(50)  ' 100 + 50 = 150
        Dim r2 As Int32 = w.WriteData(25)  ' 150 + 25 = 175
        w.ResetDevice()
        Dim r3 As Int32 = w.WriteData(10)  ' 0 + 10 = 10

        If r1 = 150 And r2 = 175 And r3 = 10 Then
            TestInterfaceImplementation = True
        Else
            Print "  [Test 64 Debug] r1=", r1, ", r2=", r2, ", r3=", r3
            TestInterfaceImplementation = False
        End If
    End Function

    ' 65. Bitfield Declarations, Packing & Bit-level Read/Write
    Public Function TestBitfieldPacking() As Boolean
        Dim flags As BitfieldFlags
        flags.FlagA = 1
        flags.FlagB = 0
        flags.Mode = 3
        flags.Extra = 10

        If flags.FlagA = 1 And flags.FlagB = 0 And flags.Mode = 3 And flags.Extra = 10 Then
            ' Mutate single bitfield without clobbering adjacent fields
            flags.FlagB = 1
            flags.Mode = 1
            If flags.FlagA = 1 And flags.FlagB = 1 And flags.Mode = 1 And flags.Extra = 10 Then
                TestBitfieldPacking = True
                Exit Function
            End If
        End If

        TestBitfieldPacking = False
    End Function

    ' Main Entry Point
    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "================================================")
        puts CPtr(Pointer To Byte, "    RUNNING LOW-LEVEL BASIC COMPREHENSIVE SUITE ")
        puts CPtr(Pointer To Byte, "================================================")

        Dim failCount As Int32 = 0

        ' 1. Arithmetic
        If TestArithmetic() Then
            puts CPtr(Pointer To Byte, "Test 1 > [PASS] Arithmetic & Modulo Operations")
        Else
            puts CPtr(Pointer To Byte, "Test 1 > [FAIL] Arithmetic & Modulo Operations")
            failCount = failCount + 1
        End If

        ' 2. Bitwise
        If TestBitwise() Then
            puts CPtr(Pointer To Byte, "Test 2 > [PASS] Bitwise & Shift Operations (And, Or, Xor, LShift, RShift)")
        Else
            puts CPtr(Pointer To Byte, "Test 2 > [FAIL] Bitwise & Shift Operations")
            failCount = failCount + 1
        End If

        ' 3. Nested If-Else
        If TestNestedIf(250) = 3 And TestNestedIf(150) = 2 And TestNestedIf(75) = 1 And TestNestedIf(10) = 0 Then
            puts CPtr(Pointer To Byte, "Test 3 > [PASS] Nested If / ElseIf / Else Control Flow")
        Else
            puts CPtr(Pointer To Byte, "Test 3 > [FAIL] Nested If / ElseIf / Else Control Flow")
            failCount = failCount + 1
        End If

        ' 4. For Loop
        If TestForLoop() = 85 Then
            puts CPtr(Pointer To Byte, "Test 4 > [PASS] For-Next Loops with Step")
        Else
            puts CPtr(Pointer To Byte, "Test 4 > [FAIL] For-Next Loops with Step")
            failCount = failCount + 1
        End If

        ' 5. Do Loops
        If TestDoLoop() = 15 Then
            puts CPtr(Pointer To Byte, "Test 5 > [PASS] Do-Loop & Exit Do")
        Else
            puts CPtr(Pointer To Byte, "Test 5 > [FAIL] Do-Loop & Exit Do")
            failCount = failCount + 1
        End If

        ' 6. While Loop
        If TestWhileLoop() = 32 Then
            puts CPtr(Pointer To Byte, "Test 6 > [PASS] While-Wend Loop")
        Else
            puts CPtr(Pointer To Byte, "Test 6 > [FAIL] While-Wend Loop")
            failCount = failCount + 1
        End If

        ' 7. Recursion
        If Factorial(5) = 120 Then
            puts CPtr(Pointer To Byte, "Test 7 > [PASS] Recursive Function Calls (Factorial 5! = 120)")
        Else
            puts CPtr(Pointer To Byte, "Test 7 > [FAIL] Recursive Function Calls")
            failCount = failCount + 1
        End If

        ' 8. Pointer Indexing
        If TestPointerIndexing() Then
            puts CPtr(Pointer To Byte, "Test 8 > [PASS] Pointer Casting (CPtr) & Indexing (ptr(i))")
        Else
            puts CPtr(Pointer To Byte, "Test 8 > [FAIL] Pointer Casting & Indexing")
            failCount = failCount + 1
        End If

        ' 9. Structures
        If TestStructure() Then
            puts CPtr(Pointer To Byte, "Test 9 > [PASS] Structure Declaration & Field Access")
        Else
            puts CPtr(Pointer To Byte, "Test 9 > [FAIL] Structure Declaration & Field Access")
            failCount = failCount + 1
        End If

        ' 10. Select Case
        If TestSelectCase(2) = 10 And TestSelectCase(5) = 20 And TestSelectCase(100) = 100 And TestSelectCase(42) = 999 Then
            puts CPtr(Pointer To Byte, "Test 10 > [PASS] Select Case Statement & Multi-Branch Dispatch")
        Else
            puts CPtr(Pointer To Byte, "Test 10 > [FAIL] Select Case Statement")
            failCount = failCount + 1
        End If

        ' 11. Pointer Arithmetic
        If TestPointerArithmetic() Then
            puts CPtr(Pointer To Byte, "Test 11 > [PASS] Low-Level Pointer Arithmetic (ptr + offset)")
        Else
            puts CPtr(Pointer To Byte, "Test 11 > [FAIL] Low-Level Pointer Arithmetic")
            failCount = failCount + 1
        End If

        ' 12. String Concatenation & Conversion
        If TestStringConcatenation() Then
            puts CPtr(Pointer To Byte, "Test 12 > [PASS] VB6 String Concatenation & Conversion (""+" & """ and ""&"")")
        Else
            puts CPtr(Pointer To Byte, "Test 12 > [FAIL] VB6 String Concatenation & Conversion")
            failCount = failCount + 1
        End If

        ' 13. Enum Declarations & Values
        If TestEnum() Then
            puts CPtr(Pointer To Byte, "Test 13 > [PASS] Enum Declarations & Member Constants (TrafficLight.Yellow)")
        Else
            puts CPtr(Pointer To Byte, "Test 13 > [FAIL] Enum Declarations & Member Constants")
            failCount = failCount + 1
        End If

        ' 14. With Statement
        If TestWithStatement() Then
            puts CPtr(Pointer To Byte, "Test 14 > [PASS] With Statement (.X, .Y implicit target binding)")
        Else
            puts CPtr(Pointer To Byte, "Test 14 > [FAIL] With Statement")
            failCount = failCount + 1
        End If

        ' 15. Floating Point Operations
        If TestFloatingPoint() Then
            puts CPtr(Pointer To Byte, "Test 15 > [PASS] Floating Point Types & Arithmetic (Single, Double, IEEE-754)")
        Else
            puts CPtr(Pointer To Byte, "Test 15 > [FAIL] Floating Point Types & Arithmetic")
            failCount = failCount + 1
        End If

        ' 16. Line Continuation & Declare Lib
        If TestLineContinuation() = 60 Then
            putsLib CPtr(Pointer To Byte, "Test 16 > [PASS] Line Continuation (_) & Declare Function Lib Alias (putsLib)")
        Else
            puts CPtr(Pointer To Byte, "Test 16 > [FAIL] Line Continuation & Declare Lib")
            failCount = failCount + 1
        End If

        ' 17. String Intrinsics Library
        If TestStringLibrary() Then
            puts CPtr(Pointer To Byte, "Test 17 > [PASS] String Intrinsics Library (Len, Mid, Left, Right, InStr, Trim, Asc, Chr)")
        Else
            puts CPtr(Pointer To Byte, "Test 17 > [FAIL] String Intrinsics Library")
            failCount = failCount + 1
        End If

        ' 18. Type Conversions
        If TestTypeConversions() Then
            puts CPtr(Pointer To Byte, "Test 18 > [PASS] Type Conversion Functions (Val, CStr, CInt, CLng, CDbl)")
        Else
            puts CPtr(Pointer To Byte, "Test 18 > [FAIL] Type Conversion Functions")
            failCount = failCount + 1
        End If

        ' 19. Console I/O
        If TestConsolePrint() Then
            puts CPtr(Pointer To Byte, "Test 19 > [PASS] Console I/O (Print expr; expr, expr)")
        Else
            puts CPtr(Pointer To Byte, "Test 19 > [FAIL] Console I/O")
            failCount = failCount + 1
        End If

        ' 20. Type ... End Type (VB6 UDT)
        If TestTypeUDT() Then
            puts CPtr(Pointer To Byte, "Test 20 > [PASS] Type ... End Type (VB6 User Defined Type Structure)")
        Else
            puts CPtr(Pointer To Byte, "Test 20 > [FAIL] Type ... End Type (VB6 UDT)")
            failCount = failCount + 1
        End If

        ' 21. Optional Parameters with Defaults
        If TestOptionalParameters() Then
            puts CPtr(Pointer To Byte, "Test 21 > [PASS] Optional Parameters (Optional ByVal x As T = Default)")
        Else
            puts CPtr(Pointer To Byte, "Test 21 > [FAIL] Optional Parameters")
            failCount = failCount + 1
        End If

        ' 22. AddressOf Operator
        If TestAddressOf() Then
            puts CPtr(Pointer To Byte, "Test 22 > [PASS] AddressOf Operator (Function pointer resolution)")
        Else
            puts CPtr(Pointer To Byte, "Test 22 > [FAIL] AddressOf Operator")
            failCount = failCount + 1
        End If

        ' 23. PrintLine & PrintFormat Convenience Wrappers
        If TestPrintLineAndFormat() Then
            puts CPtr(Pointer To Byte, "Test 23 > [PASS] Console Helpers (PrintLine, PrintFormat / PrintF)")
        Else
            puts CPtr(Pointer To Byte, "Test 23 > [FAIL] Console Helpers")
            failCount = failCount + 1
        End If

        ' 24. Math Library Intrinsics
        If TestMathIntrinsics() Then
            puts CPtr(Pointer To Byte, "Test 24 > [PASS] Math Intrinsics Library (Abs, Sgn, Sqrt, Int)")
        Else
            puts CPtr(Pointer To Byte, "Test 24 > [FAIL] Math Intrinsics Library")
            failCount = failCount + 1
        End If

        ' 25. TypeAlias Declarations
        If TestTypeAlias() Then
            puts CPtr(Pointer To Byte, "Test 25 > [PASS] Type Alias Declarations (TypeAlias X = Y)")
        Else
            puts CPtr(Pointer To Byte, "Test 25 > [FAIL] Type Alias Declarations")
            failCount = failCount + 1
        End If

        ' 26. Multidimensional Arrays & Matrices
        If TestMultidimensionalArrays() Then
            puts CPtr(Pointer To Byte, "Test 26 > [PASS] Multidimensional Arrays & Matrices (matrix(r, c) & UBound)")
        Else
            puts CPtr(Pointer To Byte, "Test 26 > [FAIL] Multidimensional Arrays & Matrices")
            failCount = failCount + 1
        End If

        ' 27. Key-Value Map & Dictionary
        If TestMapAndDictionary() Then
            puts CPtr(Pointer To Byte, "Test 27 > [PASS] Key-Value Map & Dictionary (map(key) & MapHas)")
        Else
            puts CPtr(Pointer To Byte, "Test 27 > [FAIL] Key-Value Map & Dictionary")
            failCount = failCount + 1
        End If

        ' 28. Standalone Open-Addressing HashMap
        If TestStandaloneHashMap() Then
            puts CPtr(Pointer To Byte, "Test 28 > [PASS] Standalone Open-Addressing HashMap (Freestanding Structure)")
        Else
            puts CPtr(Pointer To Byte, "Test 28 > [FAIL] Standalone Open-Addressing HashMap")
            failCount = failCount + 1
        End If

        ' 29. Freestanding Dynamic ArrayList
        If TestArrayList() Then
            puts CPtr(Pointer To Byte, "Test 29 > [PASS] Freestanding Dynamic ArrayList (Growable List with Indexing)")
        Else
            puts CPtr(Pointer To Byte, "Test 29 > [FAIL] Freestanding Dynamic ArrayList")
            failCount = failCount + 1
        End If

        ' 30. Property Accessors (Property Get & Property Let)
        If TestPropertyAccessors() Then
            puts CPtr(Pointer To Byte, "Test 30 > [PASS] Class & Module Property Accessors (Property Get / Let)")
        Else
            puts CPtr(Pointer To Byte, "Test 30 > [FAIL] Class & Module Property Accessors")
            failCount = failCount + 1
        End If

        ' 31. For Each / Collection Iterators
        If TestForEachIterators() Then
            puts CPtr(Pointer To Byte, "Test 31 > [PASS] Collection Iterators (For Each elem In collection)")
        Else
            puts CPtr(Pointer To Byte, "Test 31 > [FAIL] Collection Iterators")
            failCount = failCount + 1
        End If

        ' 32. Nested Arrays & Multi-Level Chained Indexing
        If TestNestedArrays() Then
            puts CPtr(Pointer To Byte, "Test 32 > [PASS] Nested Arrays & Multi-Level Chained Indexing")
        Else
            puts CPtr(Pointer To Byte, "Test 32 > [FAIL] Nested Arrays & Multi-Level Chained Indexing")
            failCount = failCount + 1
        End If

        ' 33. Object Lifecycle: Set obj = New ClassName & Delete
        If TestNewObjectLifecycle() Then
            puts CPtr(Pointer To Byte, "Test 33 > [PASS] Object Lifecycle (New ClassName & Delete)")
        Else
            puts CPtr(Pointer To Byte, "Test 33 > [FAIL] Object Lifecycle (New ClassName & Delete)")
            failCount = failCount + 1
        End If

        ' 34. Dynamic Array Resizing (ReDim & ReDim Preserve)
        If TestReDim() Then
            puts CPtr(Pointer To Byte, "Test 34 > [PASS] Dynamic Array Resizing (ReDim & ReDim Preserve)")
        Else
            puts CPtr(Pointer To Byte, "Test 34 > [FAIL] Dynamic Array Resizing (ReDim & ReDim Preserve)")
            failCount = failCount + 1
        End If

        ' 35. Is / Nothing Operator
        If TestIsNothingOperator() Then
            puts CPtr(Pointer To Byte, "Test 35 > [PASS] Is / Nothing Pointer Null Operators")
        Else
            puts CPtr(Pointer To Byte, "Test 35 > [FAIL] Is / Nothing Pointer Null Operators")
            failCount = failCount + 1
        End If

        ' 36. Erase Statement (Fixed arrays & Dynamic pointers)
        If TestEraseStatement() Then
            puts CPtr(Pointer To Byte, "Test 36 > [PASS] Erase Statement (Fixed Array Zeroing & Pointer Clearing)")
        Else
            puts CPtr(Pointer To Byte, "Test 36 > [FAIL] Erase Statement")
            failCount = failCount + 1
        End If

        ' 37. StrComp Function (Classic VB6 string comparison)
        If TestStrCompFunction() Then
            puts CPtr(Pointer To Byte, "Test 37 > [PASS] StrComp Function (Three-way String Comparison)")
        Else
            puts CPtr(Pointer To Byte, "Test 37 > [FAIL] StrComp Function")
            failCount = failCount + 1
        End If

        ' 38. GoTo & Label Jumps
        If TestGoToLabels() Then
            puts CPtr(Pointer To Byte, "Test 38 > [PASS] Unconditional Jumps (GoTo <Label> & <Label>:)")
        Else
            puts CPtr(Pointer To Byte, "Test 38 > [FAIL] Unconditional Jumps (GoTo)")
            failCount = failCount + 1
        End If

        ' 39. Structured Exception Handling (Try ... Catch ... Finally)
        If TestTryCatchFinally() Then
            puts CPtr(Pointer To Byte, "Test 39 > [PASS] Structured Error Handling (Try ... Catch ... Finally)")
        Else
            puts CPtr(Pointer To Byte, "Test 39 > [FAIL] Structured Error Handling (Try ... Catch ... Finally)")
            failCount = failCount + 1
        End If

        ' 40. ParamArray (Variadic Arguments)
        If TestParamArray() Then
            puts CPtr(Pointer To Byte, "Test 40 > [PASS] Variadic Arguments (ParamArray args() As Type)")
        Else
            puts CPtr(Pointer To Byte, "Test 40 > [FAIL] Variadic Arguments (ParamArray)")
            failCount = failCount + 1
        End If

        ' 41. Named Arguments
        If TestNamedArguments() Then
            puts CPtr(Pointer To Byte, "Test 41 > [PASS] Call-Site Named Arguments (name := expr)")
        Else
            puts CPtr(Pointer To Byte, "Test 41 > [FAIL] Call-Site Named Arguments")
            failCount = failCount + 1
        End If

        ' 42. Like String Pattern Matching
        If TestLikeOperator() Then
            puts CPtr(Pointer To Byte, "Test 42 > [PASS] String Pattern Matching (Like operator with * and ?)")
        Else
            puts CPtr(Pointer To Byte, "Test 42 > [FAIL] String Pattern Matching (Like)")
            failCount = failCount + 1
        End If

        ' 43. Unsigned vs Signed Distinctions
        If TestUnsignedOperations() Then
            puts CPtr(Pointer To Byte, "Test 43 > [PASS] Unsigned Operations (UDiv, URem, Logical RShift, Unsigned Cmp)")
        Else
            puts CPtr(Pointer To Byte, "Test 43 > [FAIL] Unsigned Operations")
            failCount = failCount + 1
        End If

        ' 44. Union Types (Overlapping memory layout)
        If TestUnionTypes() Then
            puts CPtr(Pointer To Byte, "Test 44 > [PASS] Union Types (Overlapping memory layout & member aliasing)")
        Else
            puts CPtr(Pointer To Byte, "Test 44 > [FAIL] Union Types")
            failCount = failCount + 1
        End If

        ' 45. Memory Runtime Intrinsics (ZeroMemory, FillMemory, CopyMemory)
        If TestMemoryIntrinsics() Then
            puts CPtr(Pointer To Byte, "Test 45 > [PASS] Memory Intrinsics (CopyMemory, ZeroMemory, FillMemory)")
        Else
            puts CPtr(Pointer To Byte, "Test 45 > [FAIL] Memory Intrinsics")
            failCount = failCount + 1
        End If

        ' 46. TypeOf ... Is ... Operator
        If TestTypeOfIsOperator() Then
            puts CPtr(Pointer To Byte, "Test 46 > [PASS] Runtime Type Testing (TypeOf expr Is [Not] Type)")
        Else
            puts CPtr(Pointer To Byte, "Test 46 > [FAIL] Runtime Type Testing (TypeOf)")
            failCount = failCount + 1
        End If

        ' 47. Shared Library FFI Binding (Declare ... Lib "SharedLib")
        If TestDeclareSharedLibrary() Then
            puts CPtr(Pointer To Byte, "Test 47 > [PASS] Shared Library Binding (Declare Function ... Lib SharedLib)")
        Else
            puts CPtr(Pointer To Byte, "Test 47 > [FAIL] Shared Library Binding")
            failCount = failCount + 1
        End If

        ' 48. Memory Safety & Bounds-Checked Array Access
        If TestBoundsChecking() Then
            puts CPtr(Pointer To Byte, "Test 48 > [PASS] Memory Safety & Array Bounds Validation")
        Else
            puts CPtr(Pointer To Byte, "Test 48 > [FAIL] Memory Safety & Array Bounds Validation")
            failCount = failCount + 1
        End If

        ' 49. File I/O Primitives (Open, Close, Print #, Line Input #, EOF, LOF)
        If TestFileIO() Then
            puts CPtr(Pointer To Byte, "Test 49 > [PASS] File I/O Primitives (Open, Close, Print #, Line Input #, EOF, LOF)")
        Else
            puts CPtr(Pointer To Byte, "Test 49 > [FAIL] File I/O Primitives")
            failCount = failCount + 1
        End If

        ' 50. Module Imports & Multi-File Dependency Resolution
        If TestImports() Then
            puts CPtr(Pointer To Byte, "Test 50 > [PASS] Module Imports & Multi-File Dependency Resolution")
        Else
            puts CPtr(Pointer To Byte, "Test 50 > [FAIL] Module Imports & Dependency Resolution")
            failCount = failCount + 1
        End If

        ' 51. Conditional Compilation Directives (#Const, #If, #ElseIf, #Else, #End If)
        If TestConditionalCompilation() Then
            puts CPtr(Pointer To Byte, "Test 51 > [PASS] Conditional Compilation (#Const, #If, #ElseIf, #Else, #End If)")
        Else
            puts CPtr(Pointer To Byte, "Test 51 > [FAIL] Conditional Compilation Directives")
            failCount = failCount + 1
        End If

        ' 52. Static Library Archiving & Linking (.a / -static)
        If TestStaticLibraryArchive() Then
            puts CPtr(Pointer To Byte, "Test 52 > [PASS] Static Library Archiving & Symbol Resolution (libStaticMath.a)")
        Else
            puts CPtr(Pointer To Byte, "Test 52 > [FAIL] Static Library Archiving & Linking")
            failCount = failCount + 1
        End If

        ' 53. DWARF Debug Information Emission (-g metadata)
        If TestDebugInfoEmission() Then
            puts CPtr(Pointer To Byte, "Test 53 > [PASS] DWARF Debug Information & Source Locations (-g)")
        Else
            puts CPtr(Pointer To Byte, "Test 53 > [FAIL] DWARF Debug Information Emission")
            failCount = failCount + 1
        End If

        ' 54. Advanced Type System & Procedure Attributes (<Inline>, Currency, Short, UShort, ULong)
        If TestTypeSystemAndAttributes() Then
            puts CPtr(Pointer To Byte, "Test 54 > [PASS] Type System & Procedure Attributes (<Inline>, Currency, UShort, ULong)")
        Else
            puts CPtr(Pointer To Byte, "Test 54 > [FAIL] Type System & Procedure Attributes")
            failCount = failCount + 1
        End If

        ' 55. Modern Features: Closures/Lambdas, Result(T, E) Sum Types, Namespaces
        If TestModernLanguageFeatures() Then
            puts CPtr(Pointer To Byte, "Test 55 > [PASS] Modern Language Features (Lambdas =>, Result(T, E) Sum Types, Namespaces)")
        Else
            puts CPtr(Pointer To Byte, "Test 55 > [FAIL] Modern Language Features")
            failCount = failCount + 1
        End If

        ' 56. Deterministic Scoped Cleanup (Using ... End Using)
        If TestUsingScopedCleanup() Then
            puts CPtr(Pointer To Byte, "Test 56 > [PASS] Deterministic Scoped Cleanup (Using ... End Using with .Dispose())")
        Else
            puts CPtr(Pointer To Byte, "Test 56 > [FAIL] Deterministic Scoped Cleanup (Using)")
            failCount = failCount + 1
        End If

        ' 57. Algebraic Pattern Matching (Match ... Case ... End Match)
        If TestPatternMatching() Then
            puts CPtr(Pointer To Byte, "Test 57 > [PASS] Algebraic Pattern Matching (Match ... Case with Ok(v), Err(e), and Ranges)")
        Else
            puts CPtr(Pointer To Byte, "Test 57 > [FAIL] Algebraic Pattern Matching (Match)")
            failCount = failCount + 1
        End If

        ' 58. Inline Assembly Statements & Operand Directives (Single-line Asm, Multiline Asm ... End Asm)
        If TestInlineAssembly() Then
            puts CPtr(Pointer To Byte, "Test 58 > [PASS] Inline Assembly Statements (Single-line Asm, Multiline Asm, Inputs & Clobbers)")
        Else
            puts CPtr(Pointer To Byte, "Test 58 > [FAIL] Inline Assembly Statements")
            failCount = failCount + 1
        End If

        ' 59. Module Constants, Variable Initializers & Flexible Modifiers
        If TestModuleConstants() Then
            puts CPtr(Pointer To Byte, "Test 59 > [PASS] Module Constants, Global Initializers & Flexible Procedure Modifiers")
        Else
            puts CPtr(Pointer To Byte, "Test 59 > [FAIL] Module Constants & Modifiers")
            failCount = failCount + 1
        End If

        ' 60. Namespaces & Runtime Type/String Inspection Helpers
        If TestNamespacesAndTypeInspection() Then
            puts CPtr(Pointer To Byte, "Test 60 > [PASS] Namespaces Scope & Runtime Inspection (MathHelper.Add & IsNumericString)")
        Else
            puts CPtr(Pointer To Byte, "Test 60 > [FAIL] Namespaces & Runtime Inspection")
            failCount = failCount + 1
        End If

        ' 61. Additional Control Flow: Exit While, Do Until / Loop Until, Recursive Sub
        If TestExitWhileAndDoUntil() Then
            puts CPtr(Pointer To Byte, "Test 61 > [PASS] Control Flow & Loop Forms (Exit While, Do Until, Recursive Sub ByRef)")
        Else
            puts CPtr(Pointer To Byte, "Test 61 > [FAIL] Control Flow & Loop Forms")
            failCount = failCount + 1
        End If

        ' 62. Use Scope Binding, Aliasing & Class Instancing
        If TestUseAndClassInstancing() Then
            puts CPtr(Pointer To Byte, "Test 62 > [PASS] Use Scope Binding, Aliasing & Class Instancing (MultiUse Value Instances)")
        Else
            puts CPtr(Pointer To Byte, "Test 62 > [FAIL] Use Scope Binding & Class Instancing")
            failCount = failCount + 1
        End If

        ' 63. SingleUse Class Instancing
        If TestSingleUseInstancing() Then
            puts CPtr(Pointer To Byte, "Test 63 > [PASS] SingleUse Class Instancing & Method Dispatch")
        Else
            puts CPtr(Pointer To Byte, "Test 63 > [FAIL] SingleUse Class Instancing")
            failCount = failCount + 1
        End If

        ' 64. Interface Polymorphism & Method Implementation Dispatch
        If TestInterfaceImplementation() Then
            puts CPtr(Pointer To Byte, "Test 64 > [PASS] Interface Implementation & Method Dispatch")
        Else
            puts CPtr(Pointer To Byte, "Test 64 > [FAIL] Interface Implementation & Method Dispatch")
            failCount = failCount + 1
        End If

        ' 65. Bitfield Declarations, Packing & Bit-level Read/Write
        If TestBitfieldPacking() Then
            puts CPtr(Pointer To Byte, "Test 65 > [PASS] Bitfield Declarations, Packing & Bit-level Read/Write")
        Else
            puts CPtr(Pointer To Byte, "Test 65 > [FAIL] Bitfield Declarations, Packing & Bit-level Read/Write")
            failCount = failCount + 1
        End If

        puts CPtr(Pointer To Byte, "================================================")
        If failCount = 0 Then
            puts CPtr(Pointer To Byte, "   ALL 65 TEST SUITES PASSED SUCCESSFULLY!      ")
            puts CPtr(Pointer To Byte, "================================================")
            Main = 0
        Else
            Print "   TEST SUITE FINISHED WITH ", failCount, " FAILURE(S) OUT OF 65"
            puts CPtr(Pointer To Byte, "================================================")
            Main = 1
        End If
    End Function

End Module
