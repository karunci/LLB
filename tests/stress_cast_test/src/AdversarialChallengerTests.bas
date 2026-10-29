' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/AdversarialChallengerTests.bas
' Summary: Deep adversarial empirical tests for pointer dereference, double dereference,
'          zero-arg calls, nested casts, and struct pointer dereferences.

Module AdversarialChallengerTests

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Type TestCoord
        X As Int32
        Y As Int32
    End Type

    Public g_targetVal As Int32 = 789
    Public g_targetPtr As Pointer To Int32 = 0
    Public g_coord As TestCoord

    ' 1. Zero-argument function returning pointer
    Public Function GetZeroArgPtr() As Pointer To Int32
        GetZeroArgPtr = AddressOf g_targetVal
    End Function

    ' 2. Function returning double pointer (Pointer To Pointer To Int32)
    Public Function GetDoublePtr(ByVal dummy As Int32) As Pointer To Pointer To Int32
        g_targetPtr = AddressOf g_targetVal
        GetDoublePtr = AddressOf g_targetPtr
    End Function

    ' 3. Function returning struct pointer
    Public Function GetCoordPtr(ByVal x As Int32, ByVal y As Int32) As Pointer To TestCoord
        g_coord.X = x
        g_coord.Y = y
        GetCoordPtr = AddressOf g_coord
    End Function

    ' 4. Function with multiple arguments returning pointer
    Public Function GetMultiArgPtr(ByVal a As Int32, ByVal b As Int32, ByVal c As Int32) As Pointer To Int32
        g_targetVal = a + b + c
        GetMultiArgPtr = AddressOf g_targetVal
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "=== RUNNING ADVERSARIAL CHALLENGER STRESS TESTS ===")

        ' Test A: Zero-arg call dereference: *GetZeroArgPtr()
        Dim valA As Int32 = *GetZeroArgPtr()
        If valA <> 789 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test A: *GetZeroArgPtr() did not equal 789")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test A: *GetZeroArgPtr() zero-argument call dereferenced correctly")

        ' Test B: Parenthesized zero-arg call dereference: *(GetZeroArgPtr())
        Dim valB As Int32 = *(GetZeroArgPtr())
        If valB <> 789 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test B: *(GetZeroArgPtr()) did not equal 789")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test B: *(GetZeroArgPtr()) parenthesized zero-arg call dereferenced correctly")

        ' Test C: Double dereference on call returning pointer to pointer: **GetDoublePtr(0)
        Dim valC As Int32 = **GetDoublePtr(0)
        If valC <> 789 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test C: **GetDoublePtr(0) did not equal 789")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test C: **GetDoublePtr(0) double dereference on function call passed")

        ' Test D: Multi-argument function call dereference: *GetMultiArgPtr(10, 20, 30)
        Dim valD As Int32 = *GetMultiArgPtr(10, 20, 30)
        If valD <> 60 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test D: *GetMultiArgPtr(10, 20, 30) did not equal 60")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test D: *GetMultiArgPtr(10, 20, 30) multi-arg call dereferenced correctly")

        ' Test E: Concise cast wrapping a function call dereference: UInt64(*GetZeroArgPtr())
        Dim valE As UInt64 = UInt64(*GetZeroArgPtr())
        If valE <> 60 Then ' val was modified to 60 in Test D
            puts CPtr(Pointer To Byte, "[FAIL] Test E: UInt64(*GetZeroArgPtr()) failed")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test E: UInt64(*GetZeroArgPtr()) concise cast wrapping dereference passed")

        ' Test F: Dereferencing a call whose argument contains a concise cast: *GetDoublePtr(Int32(CULng(5)))
        Dim valF As Int32 = **GetDoublePtr(Int32(CULng(5)))
        If valF <> 60 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test F: Cast in argument failed")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test F: Call dereference with concise casts in arguments passed")

        ' Test G: Struct pointer dereference and field access
        Dim pCoord As Pointer To TestCoord = GetCoordPtr(111, 222)
        If pCoord.X <> 111 Or pCoord.Y <> 222 Then
            puts CPtr(Pointer To Byte, "[FAIL] Test G: Struct pointer member access failed")
            Main = 1
            Exit Function
        End If
        puts CPtr(Pointer To Byte, "[PASS] Test G: Struct pointer returned from function and accessed correctly")

        puts CPtr(Pointer To Byte, "=== ALL ADVERSARIAL CHALLENGER STRESS TESTS PASSED (100%) ===")
        Main = 0
    End Function

End Module

