Module TestStarFnValid
    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public g_val As Int32 = 999

    Public Function CalculateAddress(ByVal offset As Int32) As Pointer To Int32
        puts CPtr(Pointer To Byte, "Inside CalculateAddress!")
        CalculateAddress = AddressOf g_val
    End Function

    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "Calling CalculateAddress(42) directly:")
        Dim p As Pointer To Int32 = CalculateAddress(42)

        puts CPtr(Pointer To Byte, "Attempting *CalculateAddress(42):")
        Dim val As Int32 = *CalculateAddress(42)
        If val = 999 Then
            puts CPtr(Pointer To Byte, "SUCCESS: val correctly equals 999 from dereferencing CalculateAddress(42)!")
        Else
            puts CPtr(Pointer To Byte, "FAILURE: val does not equal 999!")
        End If

        Main = 0
    End Function
End Module
