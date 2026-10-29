' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestStarFn.bas
' Summary: Test star prefix behavior on function calls.

Module TestStarFn

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Function CalculateAddress(ByVal offset As Int32) As Pointer To Int32
        puts CPtr(Pointer To Byte, "Inside CalculateAddress!")
        CalculateAddress = CPtr(Pointer To Int32, 12345)
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "Calling CalculateAddress(42) directly:")
        Dim p As Pointer To Int32 = CalculateAddress(42)

        puts CPtr(Pointer To Byte, "Attempting *CalculateAddress(42):")
        Dim val As Int32 = *CalculateAddress(42)
        If val = 42 Then
            puts CPtr(Pointer To Byte, "BUG CONFIRMED: val was assigned 42 without calling CalculateAddress!")
        End If

        Main = 0
    End Function

End Module
