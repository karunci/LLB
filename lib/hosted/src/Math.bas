' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/Math.bas
' Summary: Core integer math, bounds clamping, alignment and rounding helpers for hosted runtime.

Module Math

    ''
    ' @brief Computes absolute value of a signed 64-bit integer.
    ' @param val Input signed value.
    ' @return Absolute value.
    ''
    Public Function Abs(ByVal val As Int64) As Int64
        If val < 0 Then
            Abs = 0 - val
        Else
            Abs = val
        End If
    End Function

    ''
    ' @brief Returns the minimum of two signed 64-bit integers.
    ' @param a First value.
    ' @param b Second value.
    ' @return Lesser value.
    ''
    Public Function Min(ByVal a As Int64, ByVal b As Int64) As Int64
        If a < b Then
            Min = a
        Else
            Min = b
        End If
    End Function

    ''
    ' @brief Returns the maximum of two signed 64-bit integers.
    ' @param a First value.
    ' @param b Second value.
    ' @return Greater value.
    ''
    Public Function Max(ByVal a As Int64, ByVal b As Int64) As Int64
        If a > b Then
            Max = a
        Else
            Max = b
        End If
    End Function

    ''
    ' @brief Clamps a value within an inclusive range [lowVal, highVal].
    ' @param val Input value.
    ' @param lowVal Minimum allowed value.
    ' @param highVal Maximum allowed value.
    ' @return Clamped value.
    ''
    Public Function Clamp(ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64
        If val < lowVal Then
            Clamp = lowVal
        ElseIf val > highVal Then
            Clamp = highVal
        Else
            Clamp = val
        End If
    End Function

    ''
    ' @brief Rounds an integer division upwards to the next multiple.
    ' @param numerator Dividend value.
    ' @param denominator Divisor value.
    ' @return Ceiled quotient.
    ''
    Public Function DivRoundUp(ByVal numerator As UInt64, ByVal denominator As UInt64) As UInt64
        If denominator = 0 Then
            DivRoundUp = 0
            Exit Function
        End If
        DivRoundUp = (numerator + denominator - 1) / denominator
    End Function

    ''
    ' @brief Aligns an address or size upwards to the nearest alignment boundary.
    ' @param value Unaligned value.
    ' @param alignment Power-of-two alignment boundary.
    ' @return Aligned value.
    ''
    Public Function AlignUp(ByVal value As UInt64, ByVal alignment As UInt64) As UInt64
        If alignment = 0 Then
            AlignUp = value
            Exit Function
        End If
        Dim mask As UInt64 = alignment - 1
        AlignUp = (value + mask) And (Not mask)
    End Function

    ''
    ' @brief Counts the number of set bits (1s) in a 64-bit integer (popcount).
    ' @param value Unsigned 64-bit integer.
    ' @return Number of 1 bits.
    ''
    Public Function PopCount(ByVal value As UInt64) As UInt32
        Dim count As UInt32 = 0
        Dim v As UInt64 = value
        Do While v <> 0
            v = v And (v - 1)
            count = count + 1
        Loop
        PopCount = count
    End Function

    ''
    ' @brief Counts the number of leading zero bits in a 64-bit integer (clz).
    ' @param value Unsigned 64-bit integer.
    ' @return Number of leading zero bits (0 to 64).
    ''
    Public Function CountLeadingZeros(ByVal value As UInt64) As UInt32
        If value = 0 Then
            CountLeadingZeros = 64
            Exit Function
        End If
        Dim zeros As UInt32 = 0
        Dim bit As UInt64 = &H8000000000000000
        Do While (value And bit) = 0
            zeros = zeros + 1
            bit = bit / 2
        Loop
        CountLeadingZeros = zeros
    End Function

    ''
    ' @brief Counts the number of trailing zero bits in a 64-bit integer (ctz).
    ' @param value Unsigned 64-bit integer.
    ' @return Number of trailing zero bits (0 to 64).
    ''
    Public Function CountTrailingZeros(ByVal value As UInt64) As UInt32
        If value = 0 Then
            CountTrailingZeros = 64
            Exit Function
        End If
        Dim zeros As UInt32 = 0
        Dim v As UInt64 = value
        Do While (v And 1) = 0
            zeros = zeros + 1
            v = v / 2
        Loop
        CountTrailingZeros = zeros
    End Function

End Module
