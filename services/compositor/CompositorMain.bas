' Project Name: PROS (Personal Research Operating System)
' Filename: services/compositor/CompositorMain.bas
' Summary: Standalone Ring 3 Display Compositor and Window Engine daemon.
'          Features pixel-perfect PRK cursor sprite (16x18), zero-ghost cursor
'          via strict erase-before-draw ordering, real-time dynamic FPS measurement,
'          smooth half-speed telemetry pulse, and minimalist Nord window decorations.

Import "../../include/pros.bas"
Import "DamageTracker.bas"
Import "CursorTheme.bas"
Import "../wm/WindowTheme.bas"

Module CompositorMain

    Public Declare Sub fast_blit32 Lib "libc" (ByVal dst As Pointer To UInt32, ByVal src As Pointer To UInt32, ByVal count As UInt64)

    ' -------------------------------------------------------------------------
    ' Internal Data & State
    ' -------------------------------------------------------------------------
    Private dispInfo As DisplayInfo
    Private backSurf As Surface
    Private backSurfShmId As UInt64 = 0
    Private hasDisplay As Boolean = False

    ' PRK 16x18 Decoupled Cursor State
    Private currentCursor As UInt32 = CURSOR_ARROW

    ' Shared Memory Window Pipeline State
    Private pWindowTable As Pointer To WindowTable = 0
    Private lastRenderedRevision As UInt32 = 0
    Private clientSurfaces(32) As Pointer To UInt32
    Private clientShmIds(32) As UInt64
    Private synWm As UInt64 = 0
    Private wmNodeId As UInt64 = 0

    ' PRK Wallpaper & Background Buffer State (0x55000000 in PDPT[1])
    Public Const WALLPAPER_NORD     As UInt32 = 0
    Public Const WALLPAPER_GRADIENT As UInt32 = 1
    Public Const WALLPAPER_CHECKER  As UInt32 = 2

    Private bgSurf As Surface
    Private currentWallpaper As UInt32 = WALLPAPER_GRADIENT

    ' Discrete Damage Region State (tinywl / wlroots philosophy)
    Private damage As DamageRegion

    Private cursorX As Int32 = 512
    Private cursorY As Int32 = 384
    Private oldCursorX As Int32 = 512
    Private oldCursorY As Int32 = 384
    Private cursorSavedX As Int32 = 512
    Private cursorSavedY As Int32 = 384
    Private cursorSavedBg(320) As UInt32 ' 16 x 18 = 288 pixels background backup
    Private cursorInitialized As Boolean = False
    Private cursorOnBackSurf As Boolean = False

    ' Telemetry Badge State
    Private badgeX As Int32 = 0
    Private badgeY As Int32 = 0
    Private badgeActive As Boolean = False
    Private animPos As Int32 = 0
    Private animDir As Int32 = 2

    ' Real Dynamic FPS Measurement State
    Private frameCount As UInt32 = 0
    Private lastFpsFrame As UInt32 = 0
    Private lastFpsTime As UInt64 = 0
    Private currentFps As UInt32 = 60
    Private lastRenderedFps As UInt32 = &HFFFFFFFF
    Private nextAnimTime As UInt64 = 0

    ' Dirty Bounding Box Optimization State (Indexed strictly by Window ID: 1..16)
    Private winTrackKnown(32) As Boolean
    Private winTrackX(32) As Int32
    Private winTrackY(32) As Int32
    Private winTrackW(32) As Int32
    Private winTrackH(32) As Int32
    Private winTrackState(32) As Int32

    ''
    ' @brief Zero-copy blit of client surface pixels directly into window client area,
    '        with strict screen boundary clipping for windows positioned partially off-screen.
    ''
    Private Unsafe Sub BlitClientArea(ByVal dstX As Int32, ByVal dstY As Int32, _
                                      ByVal clientW As Int32, ByVal clientH As Int32, _
                                      ByVal surfW As Int32, ByVal surfH As Int32, _
                                      ByVal pSrcPixels As Pointer To UInt32)
        If backSurf.Pixels = 0 Or pSrcPixels = 0 Then Exit Sub
        If clientW <= 0 Or clientH <= 0 Then Exit Sub

        If clientW > surfW Or clientH > surfH Then
            FillRect backSurf, dstX, dstY, clientW, clientH, COLOR_WIN_CLIENT_BG
        End If

        Dim blitW As Int32 = clientW
        If blitW > surfW Then blitW = surfW
        Dim blitH As Int32 = clientH
        If blitH > surfH Then blitH = surfH

        ' 1. Horizontal clipping against screen bounds
        Dim clipDstX0 As Int32 = dstX
        Dim clipDstX1 As Int32 = dstX + blitW
        Dim srcOffX As Int32 = 0

        If clipDstX0 < 0 Then
            srcOffX = -clipDstX0
            clipDstX0 = 0
        End If
        If clipDstX1 > backSurf.Width Then
            clipDstX1 = backSurf.Width
        End If
        Dim copyW As Int32 = clipDstX1 - clipDstX0
        If copyW <= 0 Then Exit Sub

        ' 2. Vertical clipping against screen bounds
        Dim clipDstY0 As Int32 = dstY
        Dim clipDstY1 As Int32 = dstY + blitH
        Dim srcOffY As Int32 = 0

        If clipDstY0 < 0 Then
            srcOffY = -clipDstY0
            clipDstY0 = 0
        End If
        If clipDstY1 > backSurf.Height Then
            clipDstY1 = backSurf.Height
        End If
        Dim copyH As Int32 = clipDstY1 - clipDstY0
        If copyH <= 0 Then Exit Sub

        ' 3. Source surface boundary clamping
        If srcOffX >= surfW Or srcOffY >= surfH Then Exit Sub
        If (srcOffX + copyW) > surfW Then copyW = surfW - srcOffX
        If (srcOffY + copyH) > surfH Then copyH = surfH - srcOffY
        If copyW <= 0 Or copyH <= 0 Then Exit Sub

        ' 4. Scanline blit of visible rectangle
        Dim pitchPix As UInt32 = backSurf.Pitch / 4
        Dim row As Int32 = 0
        While row < copyH
            Dim curY As Int32 = clipDstY0 + row
            Dim curSrcY As Int32 = srcOffY + row
            Dim baseDstRow As Pointer To UInt32 = backSurf.Pixels + (UInt32(curY) * pitchPix) + UInt32(clipDstX0)
            Dim srcRow As Pointer To UInt32 = pSrcPixels + (UInt32(curSrcY) * UInt32(surfW)) + UInt32(srcOffX)
            fast_blit32 baseDstRow, srcRow, UInt32(copyW)
            row = row + 1
        Wend
    End Sub

    ''
    ' @brief Zero-copy scanline blit of client surface pixels directly into window client area,
    '        clipped strictly to the active damage rectangle intersection.
    ' @param outX Left screen coordinate of clipped blit rectangle.
    ' @param outY Top screen coordinate of clipped blit rectangle.
    ' @param outW Width of clipped blit rectangle.
    ' @param outH Height of clipped blit rectangle.
    ' @param clX Left screen coordinate of full window client area.
    ' @param clY Top screen coordinate of full window client area.
    ' @param clientW Width of window client area.
    ' @param clientH Height of window client area.
    ' @param surfW Width of allocated client surface.
    ' @param surfH Height of allocated client surface.
    ' @param pSrcPixels Pointer to client surface pixel array in shared memory.
    ''
    Private Unsafe Sub BlitClientAreaClipped(ByVal outX As Int32, ByVal outY As Int32, _
                                            ByVal outW As Int32, ByVal outH As Int32, _
                                            ByVal clX As Int32, ByVal clY As Int32, _
                                            ByVal clientW As Int32, ByVal clientH As Int32, _
                                            ByVal surfW As Int32, ByVal surfH As Int32, _
                                            ByVal pSrcPixels As Pointer To UInt32)
        If backSurf.Pixels = 0 Or pSrcPixels = 0 Then Exit Sub
        If outW <= 0 Or outH <= 0 Then Exit Sub

        ' 1. If client window resized larger than client surface, fill margin with background
        If clientW > surfW Or clientH > surfH Then
            FillRect backSurf, outX, outY, outW, outH, COLOR_WIN_CLIENT_BG
        End If

        ' 2. Client relative source offsets
        Dim srcX0 As Int32 = outX - clX
        Dim srcY0 As Int32 = outY - clY

        Dim pitchPix As UInt32 = backSurf.Pitch / 4
        Dim row As Int32 = 0
        While row < outH
            Dim curY As Int32 = outY + row
            Dim curSrcY As Int32 = srcY0 + row
            If curY >= 0 And curY < backSurf.Height And curSrcY >= 0 And curSrcY < surfH Then
                Dim baseDstRow As Pointer To UInt32 = backSurf.Pixels + (UInt32(curY) * pitchPix)
                Dim srcRow As Pointer To UInt32 = pSrcPixels + (UInt32(curSrcY) * UInt32(surfW))

                If srcX0 < surfW Then
                    Dim copyW As Int32 = outW
                    If (srcX0 + copyW) > surfW Then copyW = surfW - srcX0
                    If copyW > 0 Then
                        Dim dstScanPtr As Pointer To UInt32 = baseDstRow + UInt32(outX)
                        Dim srcScanPtr As Pointer To UInt32 = srcRow + UInt32(srcX0)
                        fast_blit32 dstScanPtr, srcScanPtr, copyW
                    End If
                End If
            End If
            row = row + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Zero-Copy Hardware Presentation Engine (RAM Backbuffer -> Display Service)
    ' -------------------------------------------------------------------------
    ''
    ' @brief Forward damaged rectangular bounding box to Display Port Server (srv.display).
    '        Eliminates direct MMIO mapping in Compositor; hardware driver daemon blits
    '        directly from shared memory to VRAM aperture.
    ''
    Private Unsafe Sub FlushDirtyRegion(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32)
        If backSurf.Pixels = 0 Or backSurfShmId = 0 Then Exit Sub
        If rw <= 0 Or rh <= 0 Then Exit Sub

        ' Bounds clipping
        Dim x0 As Int32 = rx
        Dim y0 As Int32 = ry
        Dim x1 As Int32 = rx + rw
        Dim y1 As Int32 = ry + rh

        If x0 < 0 Then x0 = 0
        If y0 < 0 Then y0 = 0
        If x1 > dispInfo.Width Then x1 = dispInfo.Width
        If y1 > dispInfo.Height Then y1 = dispInfo.Height

        If x0 >= x1 Or y0 >= y1 Then Exit Sub

        Dim clipW As Int32 = x1 - x0
        Dim clipH As Int32 = y1 - y0

        ' Forward presentation flush request to Display Port Server (srv.display)
        DispPresentRect x0, y0, clipW, clipH, backSurfShmId
    End Sub

    ' -------------------------------------------------------------------------
    ' PRK Standard Arrow Cursor Engine (16x18 Sprite matching gui/main.c)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub SaveCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If backSurf.Pixels = 0 Then Exit Sub
        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0

        If backSurf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < backSurf.Height Then
                    Dim rawRow As Pointer To Byte = *Byte(backSurf.Pixels) + (UInt32(curY) * backSurf.Pitch)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < backSurf.Width Then
                            Dim bOff As UInt32 = UInt32(curX) * 3
                            Dim b As UInt32 = rawRow(bOff)
                            Dim g As UInt32 = rawRow(bOff + 1)
                            Dim r As UInt32 = rawRow(bOff + 2)
                            cursorSavedBg((cy * CURSOR_W) + cx) = &HFF000000 Or (r LShift 16) Or (g LShift 8) Or b
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        Else
            Dim pitchPix As UInt32 = backSurf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < backSurf.Height Then
                    Dim rowPtr As Pointer To UInt32 = backSurf.Pixels + (UInt32(curY) * pitchPix)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < backSurf.Width Then
                            cursorSavedBg((cy * CURSOR_W) + cx) = rowPtr(curX)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        End If
    End Sub

    Private Unsafe Sub RestoreCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If backSurf.Pixels = 0 Then Exit Sub
        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0

        If backSurf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < backSurf.Height Then
                    Dim rawRow As Pointer To Byte = *Byte(backSurf.Pixels) + (UInt32(curY) * backSurf.Pitch)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < backSurf.Width Then
                            Dim col As UInt32 = cursorSavedBg((cy * CURSOR_W) + cx)
                            Dim bOff As UInt32 = UInt32(curX) * 3
                            rawRow(bOff) = Byte(col And &HFF)
                            rawRow(bOff + 1) = Byte((col RShift 8) And &HFF)
                            rawRow(bOff + 2) = Byte((col RShift 16) And &HFF)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        Else
            Dim pitchPix As UInt32 = backSurf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < backSurf.Height Then
                    Dim rowPtr As Pointer To UInt32 = backSurf.Pixels + (UInt32(curY) * pitchPix)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < backSurf.Width Then
                            rowPtr(curX) = cursorSavedBg((cy * CURSOR_W) + cx)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        End If
    End Sub

    Private Unsafe Sub DrawCursorArrow(ByVal x As Int32, ByVal y As Int32)
        CursorTheme.DrawCursor backSurf, x, y, currentCursor
    End Sub

    ''
    ' @brief Restore pristine background under active cursor on backbuffer.
    ''
    Private Unsafe Sub EraseCursor()
        If cursorOnBackSurf And backSurf.Pixels <> 0 Then
            RestoreCursorBackground cursorSavedX, cursorSavedY
            cursorOnBackSurf = False
        End If
    End Sub

    ''
    ' @brief Save background and paint cursor sprite onto backbuffer.
    ''
    Private Unsafe Sub PaintCursor()
        If cursorInitialized And backSurf.Pixels <> 0 Then
            SaveCursorBackground cursorX, cursorY
            cursorSavedX = cursorX
            cursorSavedY = cursorY
            DrawCursorArrow cursorX, cursorY
            cursorOnBackSurf = True
        End If
    End Sub

    ''
    ' @brief Dynamically change active cursor variant with zero-lag restoration.
    ''
    Private Unsafe Sub SetActiveCursor(ByVal newCursor As UInt32)
        If newCursor = currentCursor Then Exit Sub
        currentCursor = newCursor
    End Sub

    ''
    ' @brief Check if a candidate bounding box intersects the current cursor rectangle.
    ''
    Private Function CursorIntersects(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32) As Boolean
        If (cursorX + CURSOR_W) <= rx Or cursorX >= (rx + rw) Then
            CursorIntersects = False
            Exit Function
        End If
        If (cursorY + CURSOR_H) <= ry Or cursorY >= (ry + rh) Then
            CursorIntersects = False
            Exit Function
        End If
        CursorIntersects = True
    End Function

    ' -------------------------------------------------------------------------
    ' Telemetry Status Badge Renderer (Paced at half-speed with Dynamic FPS)
    ' NOTE: Cursor erase/redraw is handled ONLY by the main render loop.
    '       This routine NEVER touches cursor state to prevent ghost artifacts.
    ' -------------------------------------------------------------------------
    Private Unsafe Sub RenderTelemetryBadge(ByVal flushToScreen As Boolean)
        If Not badgeActive Then Exit Sub

        ' 0. Draw Badge Container Card Background & Border (Nord Theme)
        FillRect backSurf, badgeX, badgeY, 200, 26, &HFF232731
        FillRect backSurf, badgeX, badgeY, 200, 1, &HFF3B4252
        FillRect backSurf, badgeX, badgeY + 25, 200, 1, &HFF2E3440
        FillRect backSurf, badgeX, badgeY, 1, 26, &HFF3B4252
        FillRect backSurf, badgeX + 199, badgeY, 1, 26, &HFF2E3440

        ' 1. Cycle status LED color (breathing green -> cyan -> mint -> emerald)
        Dim ledColor As UInt32 = &HFF00C853
        Dim colorPhase As UInt32 = (frameCount / 12) Mod 4
        If colorPhase = 0 Then
            ledColor = &HFF00E676
        ElseIf colorPhase = 1 Then
            ledColor = &HFF00E5FF
        ElseIf colorPhase = 2 Then
            ledColor = &HFF69F0AE
        Else
            ledColor = &HFF00C853
        End If
        FillRect backSurf, badgeX + 4, badgeY + 4, 8, 18, ledColor

        ' 2. Redraw recessed dark channel for scanner pulse
        Dim trackX As Int32 = badgeX + 16
        Dim trackY As Int32 = badgeY + 5
        Dim trackW As Int32 = 120
        Dim trackH As Int32 = 16
        Dim pulseW As Int32 = 28
        FillRect backSurf, trackX, trackY, trackW, trackH, &HFF1B2028

        ' 3. Ping-pong animated scanner pulse with multi-layer glow
        Dim pulseX As Int32 = trackX + animPos
        If pulseX < trackX Then pulseX = trackX
        If (pulseX + pulseW) > (trackX + trackW) Then
            pulseX = (trackX + trackW) - pulseW
        End If

        FillRect backSurf, pulseX, trackY + 1, pulseW, trackH - 2, &HFF00897B
        FillRect backSurf, pulseX + 4, trackY + 3, pulseW - 8, trackH - 6, &HFF00E5FF
        FillRect backSurf, pulseX + 9, trackY + 5, pulseW - 18, trackH - 10, &HFFFFFFFF

        ' Advance animation at half-speed (2 pixels per frame)
        animPos = animPos + animDir
        If animPos >= (trackW - pulseW) Then
            animPos = trackW - pulseW
            animDir = -2
        ElseIf animPos <= 0 Then
            animPos = 0
            animDir = 2
        End If

        ' 4. Real-time dynamic FPS counter text
        Dim fpsBuf(16) As Byte
        Dim fIdx As UInt32 = 0
        AppendUInt currentFps, @fpsBuf(0), fIdx
        AppendStr " FPS", @fpsBuf(0), fIdx
        fpsBuf(fIdx) = 0

        FillRect backSurf, badgeX + 138, badgeY + 6, 60, 16, &HFF2E3440
        DrawText5x7 backSurf, badgeX + 140, badgeY + 10, @fpsBuf(0), &HFF88C0D0

        If flushToScreen Then
            FlushDirtyRegion badgeX, badgeY, 200, 26
        End If
    End Sub

    ''
    ' @brief Render live mouse coordinates text on top system menu bar.
    '        Rendered exclusively to backSurf; flushed to display service.
    ''
    Private Unsafe Sub RenderMouseCoordinates(ByVal flushToScreen As Boolean)
        If backSurf.Pixels = 0 Then Exit Sub

        Dim coordBuf(32) As Byte
        Dim cIdx As UInt32 = 0
        AppendStr "MOUSE: X=", @coordBuf(0), cIdx
        AppendUInt cursorX, @coordBuf(0), cIdx
        AppendStr " Y=", @coordBuf(0), cIdx
        AppendUInt cursorY, @coordBuf(0), cIdx
        coordBuf(cIdx) = 0

        FillRect backSurf, 430, 6, 180, 14, &HFF232731
        DrawText5x7 backSurf, 434, 10, @coordBuf(0), &HFFEBCB8B

        If flushToScreen Then
            FlushDirtyRegion 430, 6, 180, 14
        End If
    End Sub

    ' -------------------------------------------------------------------------
    ' PRK Procedural Desktop Wallpaper Engine (Pre-rendered into bgSurf)
    ' -------------------------------------------------------------------------
    ''
    ' @brief Pre-render active desktop wallpaper into dedicated RAM background buffer.
    '        Supports Nord Dark (0), Smooth Diagonal Gradient (1), and 32x32 Checkerboard (2).
    ''
    Private Unsafe Sub GenerateWallpaper(ByVal mode As UInt32)
        If bgSurf.Pixels = 0 Then Exit Sub
        Dim w As Int32 = dispInfo.Width
        Dim h As Int32 = dispInfo.Height
        Dim pitchPix As UInt32 = bgSurf.Pitch / 4

        Dim y As Int32 = 0
        While y < h
            Dim rowPtr As Pointer To UInt32 = bgSurf.Pixels + (UInt32(y) * pitchPix)
            Dim x As Int32 = 0
            While x < w
                Dim color As UInt32
                If mode = WALLPAPER_GRADIENT Then
                    ' Smooth Nord Diagonal Gradient (Deep Midnight -> Royal Indigo -> Dark Teal)
                    Dim r As UInt32 = 15 + ((UInt32(x) * 20) / UInt32(w))
                    Dim g As UInt32 = 23 + ((UInt32(y) * 35) / UInt32(h)) + ((UInt32(x) * 15) / UInt32(w))
                    Dim b As UInt32 = 42 + ((UInt32(x) * 55) / UInt32(w)) + ((UInt32(y) * 25) / UInt32(h))
                    color = &HFF000000 Or (r LShift 16) Or (g LShift 8) Or b
                ElseIf mode = WALLPAPER_CHECKER Then
                    ' 32x32 Retro Workstation Checkerboard
                    Dim cellX As Int32 = x / 32
                    Dim cellY As Int32 = y / 32
                    If ((cellX + cellY) And 1) = 0 Then
                        color = &HFF222731 ' Lighter Nord slate
                    Else
                        color = &HFF191D24 ' Darker Nord slate
                    End If
                    ' Subtle 1px grid borders
                    If (x Mod 32) = 0 Or (y Mod 32) = 0 Then
                        color = &HFF15181E
                    End If
                Else
                    ' Standard Minimalist Nord Dark
                    color = &HFF191D24
                End If

                rowPtr(x) = color
                x = x + 1
            Wend
            y = y + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Double-Buffered Compositing Pass (wlroots / tinywl Core Rendering Engine)
    ' -------------------------------------------------------------------------
    ''
    ' @brief Double-buffered compositing pass for a single discrete damage rectangle.
    '        Renders desktop background, top menu bar, Z-ordered window stack,
    '        HUD overlays, and cursor glyph into RAM backbuffer, then presents
    '        directly to physical Linear Framebuffer aperture via `fast_blit32_nt`.
    ''
    Private Unsafe Sub CompositeDamageRect(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32)
        If backSurf.Pixels = 0 Then Exit Sub
        If rw <= 0 Or rh <= 0 Then Exit Sub

        ' 1. Restore background on backbuffer from PRK Dedicated Background Buffer (bgSurf)
        If bgSurf.Pixels <> 0 Then
            Dim pitchPix As UInt32 = dispInfo.Pitch / 4
            Dim py As Int32 = ry
            While py < (ry + rh)
                If py >= 0 And py < dispInfo.Height Then
                    Dim off As UInt64 = (UInt64(py) * UInt64(pitchPix)) + UInt64(rx)
                    fast_blit32 backSurf.Pixels + off, bgSurf.Pixels + off, rw
                End If
                py = py + 1
            Wend
        Else
            FillRect backSurf, rx, ry, rw, rh, &HFF191D24
        End If

        ' 2. If top menu bar intersects damage rectangle (ry < 26), redraw menu bar
        If ry < 26 Then
            Dim topH As Int32 = 26 - ry
            If topH > rh Then topH = rh
            FillRect backSurf, rx, ry, rw, topH, &HFF232731
            If (ry + rh) >= 25 Then
                FillRect backSurf, rx, 25, rw, 1, &HFF4C566A
            End If
            If rx < 4 Then
                Dim cyanW As Int32 = 4 - rx
                If cyanW > rw Then cyanW = rw
                FillRect backSurf, rx, ry, cyanW, topH, &HFF88C0D0
            End If

            ' System Title
            If RectIntersects(rx, ry, rw, rh, 16, 10, 380, 10) Then
                DrawText5x7 backSurf, 16, 10, "PROS WORKSTATION  |  APPLICATIONS  NODES  SERVICES", &HFFECEFF4
            End If
            ' Mouse Coordinates
            If RectIntersects(rx, ry, rw, rh, 430, 6, 170, 14) Then
                RenderMouseCoordinates False
            End If
            ' Interactive Wallpaper Switcher Button at X=540, Y=5, W=115, H=16
            If RectIntersects(rx, ry, rw, rh, 540, 5, 115, 16) Then
                FillRect backSurf, 540, 5, 115, 16, &HFF2E3440
                FillRect backSurf, 540, 5, 115, 1, &HFF434C5E
                If currentWallpaper = WALLPAPER_GRADIENT Then
                    DrawText5x7 backSurf, 546, 9, "BG: GRADIENT", &HFF88C0D0
                ElseIf currentWallpaper = WALLPAPER_CHECKER Then
                    DrawText5x7 backSurf, 546, 9, "BG: CHECKER", &HFFEBCB8B
                Else
                    DrawText5x7 backSurf, 546, 9, "BG: NORD DARK", &HFFD8DEE9
                End If
            End If
            ' Version Tag
            If RectIntersects(rx, ry, rw, rh, dispInfo.Width - 340, 10, 180, 10) Then
                DrawText5x7 backSurf, dispInfo.Width - 340, 10, SYSTEM_VERSION_TAG, &HFF88C0D0
            End If
            ' SMP Status
            If RectIntersects(rx, ry, rw, rh, dispInfo.Width - 170, 10, 160, 10) Then
                DrawText5x7 backSurf, dispInfo.Width - 170, 10, "SMP 4 CORES  ONLINE", &HFFA3BE8C
            End If
        End If

        ' 3. Render all visible desktop windows in strict Z-order (bottom to top)
        If pWindowTable <> 0 And pWindowTable.Count > 0 Then
            Dim wi As UInt32 = 0
            While wi < pWindowTable.Count
                Dim win As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(wi)
                If win.State <> WIN_STATE_MINIMIZED Then
                    Dim winOuterW As Int32 = win.Width
                    Dim winOuterH As Int32 = win.Height
                    If win.State = WIN_STATE_NORMAL Then
                        winOuterW = winOuterW + 4
                        winOuterH = winOuterH + 4
                    End If

                    ' Check outer intersection (including shadow)
                    If RectIntersects(win.X, win.Y, winOuterW, winOuterH, rx, ry, rw, rh) Then
                        ' 3a. Draw window frame decorations
                        DrawWindowFrame backSurf, win.X, win.Y, win.Width, win.Height, win.Focused, win.State, 0

                        ' 3b. Draw window title text
                        Dim titleColor As UInt32 = COLOR_WIN_INACTIVE_TEXT
                        If win.Focused Then titleColor = COLOR_WIN_ACTIVE_TEXT
                        DrawText5x7 backSurf, win.X + 16, win.Y + 10, @win.Title(0), titleColor

                        ' 3c. Blit client surface if present
                        If win.ShmId <> 0 Then
                            Dim wId As UInt32 = win.WinId
                            If wId > 0 And wId <= 16 Then
                                If clientSurfaces(wId) = 0 Or clientShmIds(wId) <> win.ShmId Then
                                    Dim clientVaddr As UInt64 = &H68000000 + (UInt64(wId) * &H00400000)
                                    If ShmemAttach(win.ShmId, clientVaddr) <> 0 Then
                                        clientSurfaces(wId) = *UInt32(clientVaddr)
                                        clientShmIds(wId) = win.ShmId
                                    End If
                                End If

                                If clientSurfaces(wId) <> 0 Then
                                    Dim clientW As Int32 = win.Width - 4
                                    Dim clientH As Int32 = (win.Height - TITLEBAR_HEIGHT) - 4
                                    Dim surfW As Int32 = win.SurfaceWidth
                                    Dim surfH As Int32 = win.SurfaceHeight
                                    If surfW <= 0 Then surfW = clientW
                                    If surfH <= 0 Then surfH = clientH
                                    BlitClientArea win.X + 2, win.Y + TITLEBAR_HEIGHT + 2, clientW, clientH, surfW, surfH, clientSurfaces(wId)
                                End If
                            End If
                        End If
                    End If
                End If
                wi = wi + 1
            Wend
        End If

        ' 4. Render telemetry badge container if intersecting damage rect
        If badgeActive Then
            If RectIntersects(badgeX, badgeY, 200, 26, rx, ry, rw, rh) Then
                RenderTelemetryBadge False
            End If
        End If
    End Sub

    Private Unsafe Sub DrawDesktopScene()
        EraseCursor
        CompositeDamageRect 0, 0, dispInfo.Width, dispInfo.Height
        PaintCursor
        FlushDirtyRegion 0, 0, dispInfo.Width, dispInfo.Height
    End Sub

    ' -------------------------------------------------------------------------
    ' Main Application Entry Point
    ' -------------------------------------------------------------------------
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[COMPOSITOR] ======================================================="
        ConsoleWriteLine "[COMPOSITOR] PROS Display Compositor Service Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[COMPOSITOR] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.compositor' (Kind: Device/Compositor = 2, Caps: RWN = 7)
        Dim srvName As String = "srv.compositor"
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, srvName, 7)
        ConsolePrintWithUInt "[COMPOSITOR] Registered Node 'srv.compositor' -> Node #", srvNodeId, "\r\n"

        ' 3. Query Hardware Display Geometry
        If GetDisplayInfo(dispInfo) Then
            Dim resBuf(64) As Byte
            Dim rIdx As UInt32 = 0
            AppendStr "[COMPOSITOR] Discovered Display: ", @resBuf(0), rIdx
            AppendUInt dispInfo.Width, @resBuf(0), rIdx
            AppendStr "x", @resBuf(0), rIdx
            AppendUInt dispInfo.Height, @resBuf(0), rIdx
            AppendStr " @ ", @resBuf(0), rIdx
            AppendUInt dispInfo.Bpp, @resBuf(0), rIdx
            AppendStr " BPP", @resBuf(0), rIdx
            resBuf(rIdx) = 0
            ConsoleWriteLine @resBuf(0)
            ConsolePrintWithUInt "[COMPOSITOR] Framebuffer Pitch: ", dispInfo.Pitch, " bytes\r\n"
        Else
            ConsoleWriteLine "[COMPOSITOR] WARN: Could not query display information"
        End If

        ' 4. Connect to Display Port Server (srv.display)
        ConsoleWriteLine "[COMPOSITOR] Connecting to Display Port Server (srv.display)..."
        While Not DispConnect()
            ProcessSleep 20
        Wend
        ConsoleWriteLine "[COMPOSITOR] Connected to Display Port Server successfully."

        ' Query Driver Capabilities
        Dim dispCaps As DriverDispCaps
        If DispGetCaps(dispCaps) Then
            ConsolePrintWithUInt "[COMPOSITOR] Active Driver Caps: 0x", UInt64(dispCaps.CapsFlags), "\r\n"
        End If

        ' 4b. Allocate Zero-Copy Shared Memory Backbuffer at 0x54000000
        Dim bufferBytes As UInt64 = UInt64(dispInfo.Height) * UInt64(dispInfo.Pitch)
        backSurfShmId = ShmemCreate(bufferBytes, &H54000000)
        If backSurfShmId <> 0 Then
            ConsolePrintWithUInt "[COMPOSITOR] Zero-Copy Shared Backbuffer allocated -> ShmID #", backSurfShmId, " at 0x54000000\r\n"
            backSurf.Width = dispInfo.Width
            backSurf.Height = dispInfo.Height
            backSurf.Pitch = dispInfo.Pitch
            backSurf.Bpp = dispInfo.Bpp
            backSurf.Pixels = CPtr(Pointer To UInt32, &H54000000)
            hasDisplay = True
        Else
            ConsoleWriteLine "[COMPOSITOR] ERR: Failed to allocate Shared Memory Backbuffer!"
            user_main = 1
            Exit Function
        End If

        ' 4c. Allocate Dedicated In-RAM Background Buffer (PRK Architecture) at 0x55000000
        Dim pagesNeeded As UInt64 = ((bufferBytes + 4095) / 4096) + 1
        Dim bgPtr As Pointer To UInt32 = AllocatePages(pagesNeeded, &H55000000)
        If bgPtr <> 0 Then
            ConsoleWriteLine "[COMPOSITOR] Dedicated RAM Background Buffer allocated at 0x55000000"
            bgSurf.Width = dispInfo.Width
            bgSurf.Height = dispInfo.Height
            bgSurf.Pitch = dispInfo.Pitch
            bgSurf.Bpp = dispInfo.Bpp
            bgSurf.Pixels = bgPtr
            GenerateWallpaper currentWallpaper
        Else
            ConsoleWriteLine "[COMPOSITOR] WARN: Could not allocate background buffer; fallback to solid fill"
            bgSurf.Pixels = 0
        End If

        ' 5. Initialize Live Telemetry Status Badge Container
        If dispInfo.Width > 220 And dispInfo.Height > 60 Then
            badgeX = dispInfo.Width - 210
            badgeY = dispInfo.Height - 34
            badgeActive = True
        End If

        ' 6. Initial cursor placement at screen center
        cursorX = dispInfo.Width / 2
        cursorY = dispInfo.Height / 2
        oldCursorX = cursorX
        oldCursorY = cursorY
        cursorInitialized = True

        ' Transition from Boot Splash to Graphical Desktop Canvas
        ConsoleWriteLine "[COMPOSITOR] Boot splash completed. Transitioning to PROS Desktop..."
        RenderMouseCoordinates False
        RenderTelemetryBadge False
        DrawDesktopScene
        ConsoleWriteLine "[COMPOSITOR] In-RAM software cursor plane initialized at screen center."

        ' 7. Active Presentation & Event Loop (Strictly Paced 60 FPS)
        ConsoleWriteLine "[COMPOSITOR] Compositor online. Entering presentation loop..."

        ' Lookup Window Manager node 'srv.wm'
        wmNodeId = NodeLookup("srv.wm")
        If wmNodeId <> 0 Then
            synWm = SynapseConnect(srvNodeId, wmNodeId, 7)
            If synWm <> 0 Then
                ConsolePrintWithUInt "[COMPOSITOR] Connected to Window Manager -> Channel #", synWm, "\r\n"
                Dim reqTablePkt As AxonPacket
                reqTablePkt.Sequence = 1
                reqTablePkt.PacketType = WM_CMD_REGISTER_TABLE
                reqTablePkt.SourceNode = srvNodeId
                reqTablePkt.TargetNode = wmNodeId
                reqTablePkt.PayloadLength = 0
                SynapsePush synWm, reqTablePkt
            End If
        End If

        Dim mState As MouseState
        Dim targetMx As Int32 = cursorX
        Dim targetMy As Int32 = cursorY
        Dim lastButtons As Byte = 0
        Dim inPkt As AxonPacket
        Dim nextFrameTime As UInt64 = GetUptime()
        lastFpsTime = nextFrameTime

        Do
            Dim mouseMoved As Boolean = False
            Dim nowTime As UInt64 = GetUptime()

            ' 0. Service incoming Synapse control packets on srv.compositor node
            While SynapsePop(srvNodeId, inPkt)
                If inPkt.PacketType = WM_CMD_REGISTER_TABLE Then
                    Dim pShmId As Pointer To UInt64 = *UInt64(@inPkt.Payload(0))
                    Dim tableVaddr As UInt64 = &H62000000
                    If pWindowTable = 0 Then
                        If ShmemAttach(pShmId(0), tableVaddr) <> 0 Then
                            pWindowTable = Pointer To WindowTable(tableVaddr)
                            ConsolePrintWithUInt "[COMPOSITOR] Attached WindowTable (SHMID: ", pShmId(0), ")\r\n"
                        End If
                    End If
                    DamageAddFull damage, dispInfo.Width, dispInfo.Height
                ElseIf inPkt.PacketType = WM_CMD_WINDOW_DIRTY Then
                    If inPkt.PayloadLength >= 20 Then
                        Dim pDirtyPayload As Pointer To Int32 = *Int32(@inPkt.Payload(0))
                        Dim dWinId As UInt32 = UInt32(pDirtyPayload(0))
                        Dim dRx As Int32 = pDirtyPayload(1)
                        Dim dRy As Int32 = pDirtyPayload(2)
                        Dim dRw As Int32 = pDirtyPayload(3)
                        Dim dRh As Int32 = pDirtyPayload(4)

                        If pWindowTable <> 0 And pWindowTable.Count > 0 Then
                            Dim di As UInt32 = 0
                            While di < pWindowTable.Count
                                Dim dWin As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(di)
                                If dWin.WinId = dWinId And dWin.State <> WIN_STATE_MINIMIZED Then
                                    Dim dgX As Int32 = dWin.X + 2 + dRx
                                    Dim dgY As Int32 = dWin.Y + TITLEBAR_HEIGHT + 2 + dRy
                                    DamageAdd damage, dgX, dgY, dRw, dRh, dispInfo.Width, dispInfo.Height
                                    Exit While
                                End If
                                di = di + 1
                            Wend
                        End If
                    Else
                        ' Parameterless dirty signal: damage all visible windows
                        If pWindowTable <> 0 And pWindowTable.Count > 0 Then
                            Dim fwi As UInt32 = 0
                            While fwi < pWindowTable.Count
                                Dim fWin As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(fwi)
                                If fWin.State <> WIN_STATE_MINIMIZED Then
                                    DamageAdd damage, fWin.X - 4, fWin.Y - 4, fWin.Width + 16, fWin.Height + 16, dispInfo.Width, dispInfo.Height
                                End If
                                fwi = fwi + 1
                            Wend
                        End If
                    End If
                ElseIf inPkt.PacketType = WM_CMD_SET_CURSOR Then
                    Dim pCurType As Pointer To UInt32 = *UInt32(@inPkt.Payload(0))
                    If pCurType(0) <> currentCursor Then
                        currentCursor = pCurType(0)
                        If cursorInitialized Then
                            DamageAdd damage, cursorX, cursorY, CURSOR_W, CURSOR_H, dispInfo.Width, dispInfo.Height
                        End If
                    End If
                End If
            Wend

            ' Retry connecting to srv.wm or requesting table if not attached
            If pWindowTable = 0 Then
                If synWm = 0 Then
                    wmNodeId = NodeLookup("srv.wm")
                    If wmNodeId <> 0 Then
                        synWm = SynapseConnect(srvNodeId, wmNodeId, 7)
                    End If
                End If
                If synWm <> 0 Then
                    Dim reqTablePkt2 As AxonPacket
                    reqTablePkt2.Sequence = frameCount
                    reqTablePkt2.PacketType = WM_CMD_REGISTER_TABLE
                    reqTablePkt2.SourceNode = srvNodeId
                    reqTablePkt2.TargetNode = wmNodeId
                    reqTablePkt2.PayloadLength = 0
                    SynapsePush synWm, reqTablePkt2
                End If
            End If

            ' A. Read live hardware PS/2 mouse state and update cursor position with zero lag
            If GetMouseState(mState) Then
                Dim newMx As Int32 = mState.X
                Dim newMy As Int32 = mState.Y

                ' Allow natural desktop overflow: cursor hotspot tip (0,0) reaches every boundary pixel
                If newMx < 0 Then newMx = 0
                If newMx >= dispInfo.Width Then newMx = dispInfo.Width - 1
                If newMy < 0 Then newMy = 0
                If newMy >= dispInfo.Height Then newMy = dispInfo.Height - 1

                Dim lastBtnState As Byte = lastButtons
                If newMx <> targetMx Or newMy <> targetMy Or mState.Buttons <> lastButtons Then
                    targetMx = newMx
                    targetMy = newMy
                    lastButtons = mState.Buttons

                    ' Check for click on Wallpaper Switcher Button at X=540, Y=5, W=115, H=16
                    If (mState.Buttons And 1) <> 0 And (lastBtnState And 1) = 0 Then
                        If targetMy >= 4 And targetMy <= 22 And targetMx >= 540 And targetMx <= 655 Then
                            currentWallpaper = (currentWallpaper + 1) Mod 3
                            GenerateWallpaper currentWallpaper
                            DamageAddFull damage, dispInfo.Width, dispInfo.Height
                        End If
                    End If

                    ' Forward mouse event to Window Manager
                    If synWm <> 0 Then
                        Dim mEvtPkt As AxonPacket
                        mEvtPkt.Sequence = frameCount
                        mEvtPkt.PacketType = WM_CMD_MOUSE_EVENT
                        mEvtPkt.SourceNode = srvNodeId
                        mEvtPkt.TargetNode = wmNodeId
                        Dim pMx As Pointer To Int32 = *Int32(@mEvtPkt.Payload(0))
                        Dim pMy As Pointer To Int32 = *Int32(@mEvtPkt.Payload(4))
                        Dim pBtn As Pointer To Int32 = *Int32(@mEvtPkt.Payload(8))
                        pMx(0) = targetMx
                        pMy(0) = targetMy
                        pBtn(0) = Int32(mState.Buttons)
                        mEvtPkt.PayloadLength = 12
                        SynapsePush synWm, mEvtPkt
                    End If

                    ' Instant local hover hit-testing for dynamic cursor variant
                    Dim nextCursor As UInt32 = CURSOR_ARROW
                    If pWindowTable <> 0 And pWindowTable.Count > 0 Then
                        Dim wi As Int32 = pWindowTable.Count - 1
                        While wi >= 0
                            Dim wdesc As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(wi)
                            If wdesc.State <> WIN_STATE_MINIMIZED Then
                                Dim hit As UInt32 = HitTestWindow(targetMx, targetMy, wdesc.X, wdesc.Y, wdesc.Width, wdesc.Height)
                                If hit <> HIT_NONE Then
                                    If hit = HIT_RESIZE_BR Then
                                        nextCursor = CURSOR_RESIZE_NWSE
                                    ElseIf hit = HIT_BORDER_EW Then
                                        nextCursor = CURSOR_RESIZE_EW
                                    ElseIf hit = HIT_BORDER_NS Then
                                        nextCursor = CURSOR_RESIZE_NS
                                    ElseIf hit = HIT_CLIENT Then
                                        ' If window title contains 'T' (Terminal), switch to IBeam
                                        If wdesc.Title(0) = 80 And (wdesc.Title(5) = 84 Or wdesc.Title(14) = 67) Then
                                             nextCursor = CURSOR_IBEAM
                                        Else
                                             nextCursor = CURSOR_ARROW
                                        End If
                                    Else
                                        nextCursor = CURSOR_ARROW
                                    End If
                                    Exit While
                                End If
                            End If
                            wi = wi - 1
                        Wend
                    End If
                    If nextCursor <> currentCursor Then
                        currentCursor = nextCursor
                    End If

                    ' In-RAM zero-flicker cursor update using DamageTracker / Hardware Cursor:
                    If cursorInitialized Then
                        cursorX = targetMx
                        cursorY = targetMy
                        mouseMoved = True

                        DamageAdd damage, oldCursorX, oldCursorY, CURSOR_W, CURSOR_H, dispInfo.Width, dispInfo.Height
                        DamageAdd damage, cursorX, cursorY, CURSOR_W, CURSOR_H, dispInfo.Width, dispInfo.Height
                        DamageAdd damage, 430, 6, 180, 14, dispInfo.Width, dispInfo.Height
                        oldCursorX = cursorX
                        oldCursorY = cursorY
                    End If
                End If
            End If

            ' B. Check for WindowTable geometry/Z-order updates and closed windows
            If pWindowTable <> 0 Then
                ' 1. Check for closed / destroyed windows
                Dim wIdCheck As UInt32 = 1
                While wIdCheck <= 16
                    If winTrackKnown(wIdCheck) Then
                        Dim stillExists As Boolean = False
                        Dim k As UInt32 = 0
                        While k < pWindowTable.Count
                            If pWindowTable.Windows(k).WinId = wIdCheck Then
                                stillExists = True
                                Exit While
                            End If
                            k = k + 1
                        Wend

                        If Not stillExists Then
                            ' Window was closed / destroyed! Damage its entire old bounds to erase it and restore background!
                            DamageAdd damage, winTrackX(wIdCheck) - 4, winTrackY(wIdCheck) - 4, winTrackW(wIdCheck) + 16, winTrackH(wIdCheck) + 16, dispInfo.Width, dispInfo.Height
                            winTrackKnown(wIdCheck) = False
                            clientSurfaces(wIdCheck) = 0
                            clientShmIds(wIdCheck) = 0
                        End If
                    End If
                    wIdCheck = wIdCheck + 1
                Wend

                ' 2. Check for created or moved/resized windows
                If pWindowTable.Revision <> lastRenderedRevision Then
                    Dim twi As UInt32 = 0
                    While twi < pWindowTable.Count
                        Dim twdesc As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(twi)
                        Dim wId As UInt32 = twdesc.WinId
                        If wId > 0 And wId <= 16 Then
                            If Not winTrackKnown(wId) Then
                                DamageAdd damage, twdesc.X - 4, twdesc.Y - 4, twdesc.Width + 16, twdesc.Height + 16, dispInfo.Width, dispInfo.Height
                                winTrackKnown(wId) = True
                            ElseIf twdesc.X <> winTrackX(wId) Or twdesc.Y <> winTrackY(wId) Or twdesc.Width <> winTrackW(wId) Or twdesc.Height <> winTrackH(wId) Or twdesc.State <> winTrackState(wId) Then
                                DamageAdd damage, winTrackX(wId) - 4, winTrackY(wId) - 4, winTrackW(wId) + 16, winTrackH(wId) + 16, dispInfo.Width, dispInfo.Height
                                DamageAdd damage, twdesc.X - 4, twdesc.Y - 4, twdesc.Width + 16, twdesc.Height + 16, dispInfo.Width, dispInfo.Height
                            End If
                            winTrackX(wId) = twdesc.X
                            winTrackY(wId) = twdesc.Y
                            winTrackW(wId) = twdesc.Width
                            winTrackH(wId) = twdesc.Height
                            winTrackState(wId) = twdesc.State
                        End If
                        twi = twi + 1
                    Wend
                    lastRenderedRevision = pWindowTable.Revision
                End If
            End If

            ' C. 60 FPS Presentation Gate (strictly paced to 16ms intervals)
            If nowTime >= nextFrameTime Then
                ' Telemetry scanner pulse animation
                If badgeActive Then
                    DamageAdd damage, badgeX, badgeY, 200, 26, dispInfo.Width, dispInfo.Height
                End If

                ' Composite and present all accumulated discrete damaged rectangles
                If damage.Count > 0 Then
                    Dim flushX0 As Int32 = dispInfo.Width
                    Dim flushY0 As Int32 = dispInfo.Height
                    Dim flushX1 As Int32 = 0
                    Dim flushY1 As Int32 = 0

                    ' 1. Erase cursor from backbuffer before modifying dirty scanlines
                    EraseCursor

                    ' 2. Composite all damaged rects onto backbuffer
                    Dim dIdx As UInt32 = 0
                    While dIdx < damage.Count
                        Dim dr As Pointer To DamageRect = AddressOf damage.Rects(dIdx)
                        If dr.X < flushX0 Then flushX0 = dr.X
                        If dr.Y < flushY0 Then flushY0 = dr.Y
                        If (dr.X + dr.Width) > flushX1 Then flushX1 = dr.X + dr.Width
                        If (dr.Y + dr.Height) > flushY1 Then flushY1 = dr.Y + dr.Height

                        CompositeDamageRect dr.X, dr.Y, dr.Width, dr.Height
                        dIdx = dIdx + 1
                    Wend
                    DamageReset damage

                    ' 3. Paint cursor onto backbuffer and compute consolidated presentation bounds
                    If cursorInitialized Then
                        If cursorX < flushX0 Then flushX0 = cursorX
                        If cursorY < flushY0 Then flushY0 = cursorY
                        If (cursorX + CURSOR_W) > flushX1 Then flushX1 = cursorX + CURSOR_W
                        If (cursorY + CURSOR_H) > flushY1 Then flushY1 = cursorY + CURSOR_H

                        PaintCursor
                    End If

                    ' 4. Bounds clipping against display limits
                    If flushX0 < 0 Then flushX0 = 0
                    If flushY0 < 0 Then flushY0 = 0
                    If flushX1 > dispInfo.Width Then flushX1 = dispInfo.Width
                    If flushY1 > dispInfo.Height Then flushY1 = dispInfo.Height

                    ' 5. ATOMIC PRESENTATION: Single VRAM burst blit per frame!
                    If flushX1 > flushX0 And flushY1 > flushY0 Then
                        FlushDirtyRegion flushX0, flushY0, flushX1 - flushX0, flushY1 - flushY0
                    End If
                End If

                If (nowTime - nextFrameTime) > 32 Then
                    nextFrameTime = nowTime + 16
                Else
                    nextFrameTime = nextFrameTime + 16
                End If
                frameCount = frameCount + 1
            End If

            ' D. Dynamic FPS calculation every 1000 ms
            If nowTime >= (lastFpsTime + 1000) Then
                Dim elapsedSec As UInt64 = nowTime - lastFpsTime
                If elapsedSec > 0 Then
                    currentFps = UInt32(((UInt64(frameCount - lastFpsFrame) * 1000) / elapsedSec))
                End If
                lastFpsFrame = frameCount
                lastFpsTime = nowTime
            End If

            ' E. Pacing: Adaptive Event-Driven Presentation Pacing (Zero 100% CPU lockup)
            nowTime = GetUptime()
            If mouseMoved Then
                ProcessYield
            Else
                If nextFrameTime > nowTime Then
                    Dim waitRemaining As UInt64 = nextFrameTime - nowTime
                    If waitRemaining >= 2 Then
                        ProcessSleep (waitRemaining - 1)
                    Else
                        ProcessYield
                    End If
                Else
                    nextFrameTime = nowTime + 16
                    ProcessYield
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
