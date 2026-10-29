' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestParenDeref.bas
' Summary: Test parenthesized dereference of function calls.

Module TestParenDeref

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Function CalculateAddress(ByVal offset As Int32) As Pointer To Int32
        puts CPtr(Pointer To Byte, "Inside CalculateAddress!")
        CalculateAddress = CPtr(Pointer To Int32, 12345)
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "Attempting *(CalculateAddress(42)):")
        Dim val As Int32 = *(CalculateAddress(42))
        Main = 0
    End Function

End Module
