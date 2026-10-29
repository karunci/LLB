' Project Name: Low-Level Basic / Stress Cast Test Suite
' Filename: tests/stress_cast_test/src/TestTwoArgDeref.bas
' Summary: Test dereference of 2-argument function call.

Module TestTwoArgDeref

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Function CalculateAddress2(ByVal a As Int32, ByVal b As Int32) As Pointer To Int32
        puts CPtr(Pointer To Byte, "Inside CalculateAddress2 (SUCCESS)!")
        CalculateAddress2 = CPtr(Pointer To Int32, 12345)
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "Attempting *CalculateAddress2(42, 10):")
        ' Notice: 12345 is an invalid pointer address to dereference, but the function CALL will be executed before dereferencing!
        ' To avoid segfault, return a pointer to a real variable:
        Dim realVal As Int32 = 777
        Dim pReal As Pointer To Int32 = AddressOf realVal
        CalculateAddress2Dummy pReal
        Main = 0
    End Function

    Public Function CalculateAddress2Real(ByVal p As Pointer To Int32, ByVal dummy As Int32) As Pointer To Int32
        puts CPtr(Pointer To Byte, "Inside CalculateAddress2Real (SUCCESS)!")
        CalculateAddress2Real = p
    End Function

    Public Unsafe Sub CalculateAddress2Dummy(ByVal p As Pointer To Int32)
        Dim derefVal As Int32 = *CalculateAddress2Real(p, 0)
        If derefVal = 777 Then
            puts CPtr(Pointer To Byte, "2-arg function dereferenced successfully!")
        End If
    End Sub

End Module
