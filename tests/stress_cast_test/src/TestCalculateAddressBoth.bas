' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestCalculateAddressBoth.bas
' Summary: Empirically verify *CalculateAddress(42) and *(CalculateAddress(42)) dereference pointer.

Module TestCalculateAddressBoth

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public g_val As Int32 = 999
    Public g_callCount As Int32 = 0
    Public g_lastArg As Int32 = 0

    Public Function CalculateAddress(ByVal offset As Int32) As Pointer To Int32
        g_callCount = g_callCount + 1
        g_lastArg = offset
        CalculateAddress = AddressOf g_val
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        ' Test 1: *CalculateAddress(42)
        g_callCount = 0
        g_lastArg = 0
        Dim val1 As Int32 = *CalculateAddress(42)

        If g_callCount <> 1 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 1: CalculateAddress was NOT called for *CalculateAddress(42)!")
            Main = 1
            Exit Function
        End If

        If g_lastArg <> 42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 1: CalculateAddress argument was NOT 42!")
            Main = 1
            Exit Function
        End If

        If val1 = 42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 1: val1 was 42 (hijacked by cast rather than dereferenced)!")
            Main = 1
            Exit Function
        End If

        If val1 <> 999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 1: val1 did not equal dereferenced value 999!")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test 1: *CalculateAddress(42) correctly called fn with arg 42 and dereferenced to 999")

        ' Test 2: *(CalculateAddress(42))
        g_callCount = 0
        g_lastArg = 0
        Dim val2 As Int32 = *(CalculateAddress(42))

        If g_callCount <> 1 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 2: CalculateAddress was NOT called for *(CalculateAddress(42))!")
            Main = 1
            Exit Function
        End If

        If g_lastArg <> 42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 2: CalculateAddress argument was NOT 42!")
            Main = 1
            Exit Function
        End If

        If val2 = 42 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 2: val2 was 42 (hijacked by cast rather than dereferenced)!")
            Main = 1
            Exit Function
        End If

        If val2 <> 999 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 2: val2 did not equal dereferenced value 999!")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test 2: *(CalculateAddress(42)) correctly called fn with arg 42 and dereferenced to 999")

        ' Test 3: Modify value through pointer and verify dereference sees update
        g_val = 1234
        Dim val3 As Int32 = *CalculateAddress(100)
        If val3 <> 1234 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test 3: *CalculateAddress did not see updated pointee value!")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test 3: Dynamic update verification passed")

        puts CPtr(Pointer To Byte, "ALL CALCULATE_ADDRESS DEREFERENCE TESTS PASSED (100%)")
        Main = 0
    End Function

End Module

