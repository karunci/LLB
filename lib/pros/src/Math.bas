' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Math.bas
' Summary: Pure Low-Level Basic mathematical, integer clamping, and geometric primitives.

Namespace Pros.Math

    <Packed>
    Public Structure Rect
        Public X      As Int32
        Public Y      As Int32
        Public Width  As Int32
        Public Height As Int32
    End Structure

    Public Module MathUtil

        ''
        ' @brief Compute the minimum of two signed 64-bit integers.
        ' @param a First value.
        ' @param b Second value.
        ' @return The smaller value.
        ''
        Public Function Min(ByVal a As Int64, ByVal b As Int64) As Int64
            If a < b Then
                Min = a
            Else
                Min = b
            End If
        End Function

        ''
        ' @brief Compute the maximum of two signed 64-bit integers.
        ' @param a First value.
        ' @param b Second value.
        ' @return The larger value.
        ''
        Public Function Max(ByVal a As Int64, ByVal b As Int64) As Int64
            If a > b Then
                Max = a
            Else
                Max = b
            End If
        End Function

        ''
        ' @brief Clamp a signed 64-bit integer within inclusive boundaries [lowVal, highVal].
        ' @param val Value to clamp.
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
        ' @brief Compute the absolute value of a signed 64-bit integer.
        ' @param val Input value.
        ' @return Non-negative absolute value.
        ''
        Public Function Abs(ByVal val As Int64) As Int64
            If val < 0 Then
                Abs = -val
            Else
                Abs = val
            End If
        End Function

        ''
        ' @brief Determine if a 2D point lies within a rectangle.
        ' @param r Target rectangle.
        ' @param px Point X coordinate.
        ' @param py Point Y coordinate.
        ' @return True if point is inside rectangle, False otherwise.
        ''
        Public Function RectContains(ByRef r As Rect, ByVal px As Int32, ByVal py As Int32) As Boolean
            If r.Width <= 0 Or r.Height <= 0 Then
                RectContains = False
                Exit Function
            End If
            If px >= r.X And px < (r.X + r.Width) And py >= r.Y And py < (r.Y + r.Height) Then
                RectContains = True
            Else
                RectContains = False
            End If
        End Function

        ''
        ' @brief Compute the minimal union bounding box of two rectangles.
        '        Safe against in-place aliasing where outRect is also r1 or r2.
        ' @param outRect Destination rectangle receiving bounding box.
        ' @param r1 First source rectangle.
        ' @param r2 Second source rectangle.
        ''
        Public Sub UnionRect(ByRef outRect As Rect, ByRef r1 As Rect, ByRef r2 As Rect)
            Dim empty1 As Boolean = (r1.Width <= 0 Or r1.Height <= 0)
            Dim empty2 As Boolean = (r2.Width <= 0 Or r2.Height <= 0)

            If empty1 And empty2 Then
                outRect.X = 0
                outRect.Y = 0
                outRect.Width = 0
                outRect.Height = 0
                Exit Sub
            ElseIf empty1 Then
                outRect.X = r2.X
                outRect.Y = r2.Y
                outRect.Width = r2.Width
                outRect.Height = r2.Height
                Exit Sub
            ElseIf empty2 Then
                outRect.X = r1.X
                outRect.Y = r1.Y
                outRect.Width = r1.Width
                outRect.Height = r1.Height
                Exit Sub
            End If

            Dim x0 As Int32 = r1.X
            If r2.X < x0 Then x0 = r2.X

            Dim y0 As Int32 = r1.Y
            If r2.Y < y0 Then y0 = r2.Y

            Dim r1Right As Int32 = r1.X + r1.Width
            Dim r2Right As Int32 = r2.X + r2.Width
            Dim x1 As Int32 = r1Right
            If r2Right > x1 Then x1 = r2Right

            Dim r1Bottom As Int32 = r1.Y + r1.Height
            Dim r2Bottom As Int32 = r2.Y + r2.Height
            Dim y1 As Int32 = r1Bottom
            If r2Bottom > y1 Then y1 = r2Bottom

            outRect.X = x0
            outRect.Y = y0
            outRect.Width = x1 - x0
            outRect.Height = y1 - y0
        End Sub

    End Module

End Namespace

