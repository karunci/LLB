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

End Module
