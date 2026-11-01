' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: services/compositor/DamageTracker.bas
' Summary: High-performance discrete damage tracking engine inspired by wlroots/tinywl.
'          Tracks, clips, coalesces, and bounds dirty screen regions for optimal
'          PCIe MMIO burst transfers in freestanding display compositing.

Import "../../include/pros.bas"

Module DamageTracker

    ' =========================================================================
    ' 1. Damage Structures & Capacity Constraints
    ' =========================================================================
    Public Const MAX_DAMAGE_RECTS As UInt32 = 16

    <Packed>
    Public Structure DamageRect
        Public X As Int32
        Public Y As Int32
        Public Width As Int32
        Public Height As Int32
    End Structure

    Public Structure DamageRegion
        Public Count As UInt32
        Public Rects(16) As DamageRect
    End Structure

    ' =========================================================================
    ' 2. Geometric Primitives & Intersection Operations
    ' =========================================================================

    ''
    ' @brief Check if two rectangles intersect.
    ' @param ax First rect left coordinate.
    ' @param ay First rect top coordinate.
    ' @param aw First rect width.
    ' @param ah First rect height.
    ' @param bx Second rect left coordinate.
    ' @param by Second rect top coordinate.
    ' @param bw Second rect width.
    ' @param bh Second rect height.
    ' @return True if rectangles overlap; False otherwise.
    ''
    Public Function RectIntersects(ByVal ax As Int32, ByVal ay As Int32, ByVal aw As Int32, ByVal ah As Int32, _
                                   ByVal bx As Int32, ByVal by As Int32, ByVal bw As Int32, ByVal bh As Int32) As Boolean
        If (ax + aw) <= bx Or ax >= (bx + bw) Then
            RectIntersects = False
            Exit Function
        End If
        If (ay + ah) <= by Or ay >= (by + bh) Then
            RectIntersects = False
            Exit Function
        End If
        RectIntersects = True
    End Function

    ''
    ' @brief Compute the clipped intersection between two rectangles.
    ' @param ax First rect left coordinate.
    ' @param ay First rect top coordinate.
    ' @param aw First rect width.
    ' @param ah First rect height.
    ' @param bx Second rect left coordinate.
    ' @param by Second rect top coordinate.
    ' @param bw Second rect width.
    ' @param bh Second rect height.
    ' @param outX Receives intersection left coordinate.
    ' @param outY Receives intersection top coordinate.
    ' @param outW Receives intersection width.
    ' @param outH Receives intersection height.
    ' @return True if intersection is non-empty; False otherwise.
    ''
    Public Function RectIntersect(ByVal ax As Int32, ByVal ay As Int32, ByVal aw As Int32, ByVal ah As Int32, _
                                  ByVal bx As Int32, ByVal by As Int32, ByVal bw As Int32, ByVal bh As Int32, _
                                  ByRef outX As Int32, ByRef outY As Int32, _
                                  ByRef outW As Int32, ByRef outH As Int32) As Boolean
        Dim x0 As Int32 = ax
        If bx > x0 Then x0 = bx
        Dim y0 As Int32 = ay
        If by > y0 Then y0 = by

        Dim x1 As Int32 = ax + aw
        If (bx + bw) < x1 Then x1 = bx + bw
        Dim y1 As Int32 = ay + ah
        If (by + bh) < y1 Then y1 = by + bh

        If x1 > x0 And y1 > y0 Then
            outX = x0
            outY = y0
            outW = x1 - x0
            outH = y1 - y0
            RectIntersect = True
        Else
            outX = 0
            outY = 0
            outW = 0
            outH = 0
            RectIntersect = False
        End If
    End Function

    ' =========================================================================
    ' 3. Damage Region Accumulation & Coalescing
    ' =========================================================================

    ''
    ' @brief Reset all tracked damage rectangles to empty state.
    ' @param region Target damage region to clear.
    ''
    Public Sub DamageReset(ByRef region As DamageRegion)
        region.Count = 0
    End Sub

    ''
    ' @brief Mark the entire display surface as damaged (full frame invalidation).
    ' @param region Target damage region.
    ' @param screenW Display width in pixels.
    ' @param screenH Display height in pixels.
    ''
    Public Sub DamageAddFull(ByRef region As DamageRegion, ByVal screenW As Int32, ByVal screenH As Int32)
        region.Count = 1
        region.Rects(0).X = 0
        region.Rects(0).Y = 0
        region.Rects(0).Width = screenW
        region.Rects(0).Height = screenH
    End Sub

    ''
    ' @brief Add a damaged rectangle to the region with screen clipping, containment filtering, and bounded coalescing.
    ' @param region Target damage region.
    ' @param x Left coordinate of damaged box.
    ' @param y Top coordinate of damaged box.
    ' @param w Width of damaged box.
    ' @param h Height of damaged box.
    ' @param screenW Display width in pixels.
    ' @param screenH Display height in pixels.
    ''
    Public Unsafe Sub DamageAdd(ByRef region As DamageRegion, ByVal x As Int32, ByVal y As Int32, _
                                ByVal w As Int32, ByVal h As Int32, _
                                ByVal screenW As Int32, ByVal screenH As Int32)
        ' 1. Screen bounds clipping
        Dim x0 As Int32 = x
        Dim y0 As Int32 = y
        Dim x1 As Int32 = x + w
        Dim y1 As Int32 = y + h

        If x0 < 0 Then x0 = 0
        If y0 < 0 Then y0 = 0
        If x1 > screenW Then x1 = screenW
        If y1 > screenH Then y1 = screenH

        If x1 <= x0 Or y1 <= y0 Then Exit Sub

        Dim clipW As Int32 = x1 - x0
        Dim clipH As Int32 = y1 - y0

        ' 2. If already damaged full screen, drop any sub-rectangles
        If region.Count = 1 Then
            If region.Rects(0).X = 0 And region.Rects(0).Y = 0 And _
               region.Rects(0).Width >= screenW And region.Rects(0).Height >= screenH Then
                Exit Sub
            End If
        End If

        ' 3. Inspect existing damage rectangles for containment or potential coalescing
        Dim i As UInt32 = 0
        While i < region.Count
            Dim rx0 As Int32 = region.Rects(i).X
            Dim ry0 As Int32 = region.Rects(i).Y
            Dim rx1 As Int32 = rx0 + region.Rects(i).Width
            Dim ry1 As Int32 = ry0 + region.Rects(i).Height

            ' Check if candidate rect is entirely enclosed by existing rect
            If x0 >= rx0 And y0 >= ry0 And x1 <= rx1 And y1 <= ry1 Then
                Exit Sub ' Already fully covered by existing damage
            End If

            ' Check if existing rect is entirely enclosed by candidate rect
            If rx0 >= x0 And ry0 >= y0 And rx1 <= x1 And ry1 <= y1 Then
                ' Expand existing rect to match new candidate
                region.Rects(i).X = x0
                region.Rects(i).Y = y0
                region.Rects(i).Width = clipW
                region.Rects(i).Height = clipH
                Exit Sub
            End If

            ' Check if rects overlap or touch (within 2 pixels)
            If RectIntersects(x0 - 2, y0 - 2, clipW + 4, clipH + 4, rx0, ry0, region.Rects(i).Width, region.Rects(i).Height) Then
                ' Compute union bounds
                Dim ux0 As Int32 = x0
                If rx0 < ux0 Then ux0 = rx0
                Dim uy0 As Int32 = y0
                If ry0 < uy0 Then uy0 = ry0
                Dim ux1 As Int32 = x1
                If rx1 > ux1 Then ux1 = rx1
                Dim uy1 As Int32 = y1
                If ry1 > uy1 Then uy1 = ry1

                Dim uW As Int32 = ux1 - ux0
                Dim uH As Int32 = uy1 - uy0

                ' Area heuristic: Only merge if dead space is less than 25% of combined area
                Dim areaUnion As Int64 = Int64(uW) * Int64(uH)
                Dim areaSum As Int64 = (Int64(clipW) * Int64(clipH)) + (Int64(region.Rects(i).Width) * Int64(region.Rects(i).Height))
                If areaUnion <= (areaSum + (areaSum RShift 2)) Then
                    region.Rects(i).X = ux0
                    region.Rects(i).Y = uy0
                    region.Rects(i).Width = uW
                    region.Rects(i).Height = uH
                    Exit Sub
                End If
            End If

            i = i + 1
        Wend

        ' 4. Append as a new discrete damage rect if capacity remains
        If region.Count < MAX_DAMAGE_RECTS Then
            Dim slot As UInt32 = region.Count
            region.Rects(slot).X = x0
            region.Rects(slot).Y = y0
            region.Rects(slot).Width = clipW
            region.Rects(slot).Height = clipH
            region.Count = region.Count + 1
            Exit Sub
        End If

        ' 5. Region capacity overflow (>= 16 rects): Merge with closest rect to preserve bounded slots
        Dim bestIdx As UInt32 = 0
        Dim minPenalty As Int64 = &H7FFFFFFFFFFFFFFF
        Dim bestUx0 As Int32 = 0
        Dim bestUy0 As Int32 = 0
        Dim bestUW As Int32 = 0
        Dim bestUH As Int32 = 0

        Dim j As UInt32 = 0
        While j < region.Count
            Dim jx0 As Int32 = region.Rects(j).X
            Dim jy0 As Int32 = region.Rects(j).Y
            Dim jx1 As Int32 = jx0 + region.Rects(j).Width
            Dim jy1 As Int32 = jy0 + region.Rects(j).Height

            Dim cx0 As Int32 = x0
            If jx0 < cx0 Then cx0 = jx0
            Dim cy0 As Int32 = y0
            If jy0 < cy0 Then cy0 = jy0
            Dim cx1 As Int32 = x1
            If jx1 > cx1 Then cx1 = jx1
            Dim cy1 As Int32 = y1
            If jy1 > cy1 Then cy1 = jy1

            Dim cW As Int32 = cx1 - cx0
            Dim cH As Int32 = cy1 - cy0
            Dim uArea As Int64 = Int64(cW) * Int64(cH)
            Dim separateArea As Int64 = (Int64(clipW) * Int64(clipH)) + (Int64(region.Rects(j).Width) * Int64(region.Rects(j).Height))
            Dim penalty As Int64 = uArea - separateArea

            If penalty < minPenalty Then
                minPenalty = penalty
                bestIdx = j
                bestUx0 = cx0
                bestUy0 = cy0
                bestUW = cW
                bestUH = cH
            End If
            j = j + 1
        Wend

        region.Rects(bestIdx).X = bestUx0
        region.Rects(bestIdx).Y = bestUy0
        region.Rects(bestIdx).Width = bestUW
        region.Rects(bestIdx).Height = bestUH
    End Sub

End Module
