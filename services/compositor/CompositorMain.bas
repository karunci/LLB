' Project Name: PROS (Personal Research Operating System)
' Filename: services/compositor/CompositorMain.bas
' Summary: Standalone Ring 3 Display Compositor and Window Engine daemon.
'          Features pixel-perfect PRK cursor sprite (16x18), responsive zero-lag
'          mouse hardware tracking, real-time dynamic FPS measurement,
'          smooth half-speed telemetry pulse, and restored minimalist Nord window.

Import "../../include/pros.bas"
Import "CursorTheme.bas"
Import "../wm/WindowTheme.bas"

Module CompositorMain

    Public Declare Sub fast_blit32 Lib "libc" (ByVal dst As Pointer To UInt32, ByVal src As Pointer To UInt32, ByVal count As UInt64)

    ' -------------------------------------------------------------------------
    ' Internal Data & State
    ' -------------------------------------------------------------------------
    Private dispInfo As DisplayInfo
    Private frontSurf As Surface
    Private backSurf As Surface
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
    Private desktopDirty As Boolean = False

    Private cursorX As Int32 = 512
    Private cursorY As Int32 = 384
    Private oldCursorX As Int32 = 512
    Private oldCursorY As Int32 = 384
    Private cursorSavedBg(320) As UInt32 ' 16 x 18 = 288 pixels background backup
    Private cursorInitialized As Boolean = False

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
    ' @brief Zero-copy blit of client surface pixels directly into window client area.
    ''
    Private Unsafe Sub BlitClientArea(ByVal dstX As Int32, ByVal dstY As Int32, _
                                      ByVal clientW As Int32, ByVal clientH As Int32, _
                                      ByVal surfW As Int32, ByVal surfH As Int32, _
                                      ByVal pSrcPixels As Pointer To UInt32)
        If backSurf.Pixels = 0 Or pSrcPixels = 0 Then Exit Sub
        If clientW <= 0 Or clientH <= 0 Then Exit Sub

        ' 1. If window was resized larger than client surface, fill margin with window background
        If clientW > surfW Or clientH > surfH Then
            FillRect backSurf, dstX, dstY, clientW, clientH, COLOR_WIN_CLIENT_BG
        End If

        ' 2. Clamp blit dimensions so we NEVER read beyond the client's allocated surface
        Dim blitW As Int32 = clientW
        If blitW > surfW Then blitW = surfW
        Dim blitH As Int32 = clientH
        If blitH > surfH Then blitH = surfH

        Dim pitchPix As UInt32 = backSurf.Pitch / 4
        Dim row As Int32 = 0
        While row < blitH
            Dim curY As Int32 = dstY + row
            If curY >= 0 And curY < backSurf.Height Then
                Dim baseDstRow As Pointer To UInt32 = backSurf.Pixels + (UInt32(curY) * pitchPix)
                Dim srcRow As Pointer To UInt32 = pSrcPixels + (UInt32(row) * UInt32(surfW))
                If dstX >= 0 And (dstX + blitW) <= backSurf.Width Then
                    Dim dstScanPtr As Pointer To UInt32 = baseDstRow + UInt32(dstX)
                    fast_blit32 dstScanPtr, srcRow, blitW
                Else
                    Dim col As Int32 = 0
                    While col < blitW
                        Dim curX As Int32 = dstX + col
                        If curX >= 0 And curX < backSurf.Width Then
                            baseDstRow(curX) = srcRow(col)
                        End If
                        col = col + 1
                    Wend
                End If
            End If
            row = row + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Zero-Copy Hardware Presentation Engine (RAM Backbuffer -> VRAM Burst Blit)
    ' -------------------------------------------------------------------------
    ''
    ' @brief Burst-blit a dirty bounding box from RAM backbuffer to physical VRAM aperture.
    '        Uses 64-bit aligned memory writes and sfence barrier for maximum PCIe throughput.
    ''
    Private Unsafe Sub FlushDirtyRegion(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32)
        If frontSurf.Pixels = 0 Or backSurf.Pixels = 0 Then Exit Sub
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

        Dim pitchPixels As UInt32 = dispInfo.Pitch / 4
        Dim py As Int32 = y0
        While py < y1
            Dim pixOff As UInt64 = (UInt64(py) * UInt64(pitchPixels)) + UInt64(x0)
            Dim dstPtr As Pointer To UInt32 = frontSurf.Pixels + pixOff
            Dim srcPtr As Pointer To UInt32 = backSurf.Pixels + pixOff
            fast_blit32 dstPtr, srcPtr, clipW
            py = py + 1
        Wend

        Asm "sfence" : : : "memory"
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
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, backSurf.Pixels) + (UInt32(curY) * backSurf.Pitch)
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
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, backSurf.Pixels) + (UInt32(curY) * backSurf.Pitch)
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
    ' -------------------------------------------------------------------------
    Private Unsafe Sub RenderTelemetryBadge(ByVal flushToScreen As Boolean)
        If Not badgeActive Then Exit Sub

        Dim restoreCursor As Boolean = False
        If flushToScreen Then
            restoreCursor = (cursorInitialized And CursorIntersects(badgeX, badgeY, 200, 26))
            If restoreCursor Then
                RestoreCursorBackground cursorX, cursorY
            End If
        End If

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

        ' 4. Real-time dynamic FPS counter text measured from system timer (rendered every frame for permanent stability)
        Dim fpsBuf(16) As Byte
        Dim fIdx As UInt32 = 0
        AppendUInt currentFps, @fpsBuf(0), fIdx
        AppendStr " FPS", @fpsBuf(0), fIdx
        fpsBuf(fIdx) = 0

        FillRect backSurf, badgeX + 138, badgeY + 6, 60, 16, &HFF2E3440
        DrawText5x7 backSurf, badgeX + 140, badgeY + 10, @fpsBuf(0), &HFF88C0D0

        If flushToScreen Then
            FlushDirtyRegion badgeX, badgeY, 200, 26

            If restoreCursor Then
                SaveCursorBackground cursorX, cursorY
                DrawCursorArrow cursorX, cursorY
                FlushDirtyRegion cursorX, cursorY, CURSOR_W, CURSOR_H
            End If
        End If
    End Sub

    ''
    ' @brief Render live mouse coordinates text on top system menu bar.
    ''
    Private Unsafe Sub RenderMouseCoordinates(ByVal flushToScreen As Boolean)
        If frontSurf.Pixels = 0 Then Exit Sub

        Dim restoreCursor As Boolean = False
        If flushToScreen Then
            restoreCursor = (cursorInitialized And CursorIntersects(430, 6, 180, 14))
            If restoreCursor Then
                RestoreCursorBackground cursorX, cursorY
            End If
        End If

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

            If restoreCursor Then
                SaveCursorBackground cursorX, cursorY
                DrawCursorArrow cursorX, cursorY
                FlushDirtyRegion cursorX, cursorY, CURSOR_W, CURSOR_H
            End If
        End If
    End Sub

    ''
    ' @brief Rasterize all active desktop windows in Z-order with decoupled frames and client surfaces.
    ''
    Private Unsafe Sub RenderDesktopWindows()
        If backSurf.Pixels = 0 Then Exit Sub
        If pWindowTable = 0 Or pWindowTable.Count = 0 Then Exit Sub

        Dim i As UInt32 = 0
        While i < pWindowTable.Count
            Dim win As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(i)
            If win.State <> WIN_STATE_MINIMIZED Then
                ' 1. Draw window frame decorations
                DrawWindowFrame backSurf, win.X, win.Y, win.Width, win.Height, win.Focused, win.State, 0

                ' 2. Draw title text
                Dim titleColor As UInt32 = COLOR_WIN_INACTIVE_TEXT
                If win.Focused Then titleColor = COLOR_WIN_ACTIVE_TEXT
                DrawText5x7 backSurf, win.X + 16, win.Y + 10, @win.Title(0), titleColor

                ' 3. Attach and Blit Client Buffer if present
                If win.ShmId <> 0 Then
                    Dim wId As UInt32 = win.WinId
                    If wId > 0 And wId <= 16 Then
                        If clientSurfaces(wId) = 0 Or clientShmIds(wId) <> win.ShmId Then
                            Dim clientVaddr As UInt64 = &H68000000 + (UInt64(wId) * &H00400000)
                            If ShmemAttach(win.ShmId, clientVaddr) <> 0 Then
                                clientSurfaces(wId) = CPtr(Pointer To UInt32, clientVaddr)
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
            i = i + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Desktop Background & Initial Window Canvas Pre-Renderer
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawDesktopScene()
        If backSurf.Pixels = 0 Then Exit Sub

        ' 1. Clear desktop to Nord Dark Background (#191D24)
        FillRect backSurf, 0, 0, dispInfo.Width, dispInfo.Height, &HFF191D24

        ' 2. Top System Menu Bar (y: 0..26)
        FillRect backSurf, 0, 0, dispInfo.Width, 26, &HFF232731
        FillRect backSurf, 0, 25, dispInfo.Width, 1, &HFF4C566A
        FillRect backSurf, 0, 0, 4, 25, &HFF88C0D0

        DrawText5x7 backSurf, 16, 10, "PROS WORKSTATION  |  APPLICATIONS  NODES  SERVICES", &HFFECEFF4
        RenderMouseCoordinates False
        DrawText5x7 backSurf, dispInfo.Width - 360, 10, "REV: 2026.10.30-r38-re01", &HFF88C0D0
        DrawText5x7 backSurf, dispInfo.Width - 170, 10, "SMP 4 CORES  ONLINE", &HFFA3BE8C

        ' 3. Render all active desktop windows from shared memory
        RenderDesktopWindows

        ' 4. Initialize Telemetry Status Badge Container
        If dispInfo.Width > 220 And dispInfo.Height > 60 Then
            badgeX = dispInfo.Width - 210
            badgeY = dispInfo.Height - 34
            FillRect backSurf, badgeX, badgeY, 200, 26, &HFF2E3440
            FillRect backSurf, badgeX, badgeY, 200, 1, &HFF434C5E
            badgeActive = True
        End If
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

        ' 4. Map Linear Framebuffer Aperture to User Space at 0x78000000
        Dim fbPtr As Pointer To UInt32 = MapFramebuffer(&H78000000)
        If fbPtr <> 0 Then
            ConsoleWriteLine "[COMPOSITOR] Linear Framebuffer Aperture mapped at 0x78000000"
            frontSurf.Width = dispInfo.Width
            frontSurf.Height = dispInfo.Height
            frontSurf.Pitch = dispInfo.Pitch
            frontSurf.Bpp = dispInfo.Bpp
            frontSurf.Pixels = fbPtr
            hasDisplay = True
        Else
            ConsoleWriteLine "[COMPOSITOR] ERR: Failed to map linear framebuffer aperture!"
            user_main = 1
            Exit Function
        End If

        ' 4b. Allocate Private In-RAM Backbuffer at 0x54000000 (PDPT[1] isolated user space)
        Dim bufferBytes As UInt64 = UInt64(dispInfo.Height) * UInt64(dispInfo.Pitch)
        Dim pagesNeeded As UInt64 = ((bufferBytes + 4095) / 4096) + 1 ' +1 safety guard page
        Dim backPtr As Pointer To UInt32 = AllocatePages(pagesNeeded, &H54000000)
        If backPtr <> 0 Then
            ConsoleWriteLine "[COMPOSITOR] Private RAM Backbuffer allocated at 0x54000000"
            backSurf.Width = dispInfo.Width
            backSurf.Height = dispInfo.Height
            backSurf.Pitch = dispInfo.Pitch
            backSurf.Bpp = dispInfo.Bpp
            backSurf.Pixels = backPtr
        Else
            ConsoleWriteLine "[COMPOSITOR] WARN: Fallback to direct VRAM (AllocatePages returned null)"
            backSurf = frontSurf
        End If

        ' 5. Transition from Boot Splash to Graphical Desktop Canvas
        ConsoleWriteLine "[COMPOSITOR] Boot splash completed. Transitioning to PROS Desktop..."
        DrawDesktopScene

        ' 6. Initial cursor placement at screen center
        cursorX = dispInfo.Width / 2
        cursorY = dispInfo.Height / 2
        oldCursorX = cursorX
        oldCursorY = cursorY
        cursorInitialized = True

        ' Pre-render dynamic elements onto backbuffer before first screen presentation
        RenderMouseCoordinates False
        RenderTelemetryBadge False
        SaveCursorBackground cursorX, cursorY
        DrawCursorArrow cursorX, cursorY
        FlushDirtyRegion 0, 0, dispInfo.Width, dispInfo.Height
        ConsoleWriteLine "[COMPOSITOR] Hardware software cursor plane initialized at screen center."

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
        Dim mouseDirty As Boolean = False
        Dim inPkt As AxonPacket
        Dim nextFrameTime As UInt64 = GetUptime()
        lastFpsTime = nextFrameTime

        Do
            Dim nowTime As UInt64 = GetUptime()

            ' 0. Service incoming Synapse control packets on srv.compositor node
            While SynapsePop(srvNodeId, inPkt)
                If inPkt.PacketType = WM_CMD_REGISTER_TABLE Then
                    Dim pShmId As Pointer To UInt64 = CPtr(Pointer To UInt64, @inPkt.Payload(0))
                    Dim tableVaddr As UInt64 = &H62000000
                    If pWindowTable = 0 Then
                        If ShmemAttach(pShmId(0), tableVaddr) <> 0 Then
                            pWindowTable = CPtr(Pointer To WindowTable, tableVaddr)
                            ConsolePrintWithUInt "[COMPOSITOR] Attached WindowTable (SHMID: ", pShmId(0), ")\r\n"
                        End If
                    End If
                    desktopDirty = True
                ElseIf inPkt.PacketType = WM_CMD_WINDOW_DIRTY Then
                    desktopDirty = True
                ElseIf inPkt.PacketType = WM_CMD_SET_CURSOR Then
                    Dim pCurType As Pointer To UInt32 = CPtr(Pointer To UInt32, @inPkt.Payload(0))
                    If pCurType(0) <> currentCursor Then
                        currentCursor = pCurType(0)
                        mouseDirty = True
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
                    Dim reqPkt2 As AxonPacket
                    reqPkt2.Sequence = frameCount
                    reqPkt2.PacketType = WM_CMD_REGISTER_TABLE
                    reqPkt2.SourceNode = srvNodeId
                    reqPkt2.TargetNode = wmNodeId
                    reqPkt2.PayloadLength = 0
                    SynapsePush synWm, reqPkt2
                End If
            End If

            ' A. Poll live hardware PS/2 mouse state (pure state update, zero VRAM blitting)
            If GetMouseState(mState) Then
                Dim newMx As Int32 = mState.X
                Dim newMy As Int32 = mState.Y

                ' Allow natural desktop overflow: cursor hotspot tip (0,0) reaches every boundary pixel
                If newMx < 0 Then newMx = 0
                If newMx >= dispInfo.Width Then newMx = dispInfo.Width - 1
                If newMy < 0 Then newMy = 0
                If newMy >= dispInfo.Height Then newMy = dispInfo.Height - 1

                If newMx <> targetMx Or newMy <> targetMy Or mState.Buttons <> lastButtons Then
                    targetMx = newMx
                    targetMy = newMy
                    lastButtons = mState.Buttons
                    mouseDirty = True

                    ' Forward mouse event to Window Manager
                    If synWm <> 0 Then
                        Dim mEvtPkt As AxonPacket
                        mEvtPkt.Sequence = frameCount
                        mEvtPkt.PacketType = WM_CMD_MOUSE_EVENT
                        mEvtPkt.SourceNode = srvNodeId
                        mEvtPkt.TargetNode = wmNodeId
                        Dim pMx As Pointer To Int32 = CPtr(Pointer To Int32, @mEvtPkt.Payload(0))
                        Dim pMy As Pointer To Int32 = CPtr(Pointer To Int32, @mEvtPkt.Payload(4))
                        Dim pBtn As Pointer To Int32 = CPtr(Pointer To Int32, @mEvtPkt.Payload(8))
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
                        mouseDirty = True
                    End If
                End If
            End If

            ' B. Check for WindowTable geometry/Z-order updates or dirty client surfaces
            If pWindowTable <> 0 Then
                If pWindowTable.Revision <> lastRenderedRevision Then
                    desktopDirty = True
                End If
            End If

            ' C. 60 FPS Presentation Gate (strictly paced to 16ms intervals)
            If nowTime >= nextFrameTime Then
                If desktopDirty Then
                    cursorX = targetMx
                    cursorY = targetMy
                    RestoreCursorBackground oldCursorX, oldCursorY

                    ' 1. Determine Dirty Bounding Box across modified windows and cursor
                    Dim dirtyX0 As Int32 = dispInfo.Width
                    Dim dirtyY0 As Int32 = dispInfo.Height
                    Dim dirtyX1 As Int32 = 0
                    Dim dirtyY1 As Int32 = 0
                    Dim anyWindowMoved As Boolean = False

                    If pWindowTable <> 0 And pWindowTable.Count > 0 Then
                        Dim twi As UInt32 = 0
                        While twi < pWindowTable.Count
                            Dim twdesc As Pointer To WindowDescriptor = AddressOf pWindowTable.Windows(twi)
                            Dim wId As UInt32 = twdesc.WinId
                            If wId > 0 And wId <= 16 Then
                                If Not winTrackKnown(wId) Then
                                    anyWindowMoved = True
                                    dirtyX0 = 0
                                    dirtyY0 = 0
                                    dirtyX1 = dispInfo.Width
                                    dirtyY1 = dispInfo.Height
                                    winTrackKnown(wId) = True
                                ElseIf twdesc.X <> winTrackX(wId) Or twdesc.Y <> winTrackY(wId) Or twdesc.Width <> winTrackW(wId) Or twdesc.Height <> winTrackH(wId) Or twdesc.State <> winTrackState(wId) Then
                                    anyWindowMoved = True

                                    ' Old window bounds + shadow margin
                                    Dim r0X0 As Int32 = winTrackX(wId) - 4
                                    Dim r0Y0 As Int32 = winTrackY(wId) - 4
                                    Dim r0X1 As Int32 = winTrackX(wId) + winTrackW(wId) + 12
                                    Dim r0Y1 As Int32 = winTrackY(wId) + winTrackH(wId) + 12

                                    ' New window bounds + shadow margin
                                    Dim r1X0 As Int32 = twdesc.X - 4
                                    Dim r1Y0 As Int32 = twdesc.Y - 4
                                    Dim r1X1 As Int32 = twdesc.X + twdesc.Width + 12
                                    Dim r1Y1 As Int32 = twdesc.Y + twdesc.Height + 12

                                    If r0X0 < dirtyX0 Then dirtyX0 = r0X0
                                    If r0Y0 < dirtyY0 Then dirtyY0 = r0Y0
                                    If r0X1 > dirtyX1 Then dirtyX1 = r0X1
                                    If r0Y1 > dirtyY1 Then dirtyY1 = r0Y1

                                    If r1X0 < dirtyX0 Then dirtyX0 = r1X0
                                    If r1Y0 < dirtyY0 Then dirtyY0 = r1Y0
                                    If r1X1 > dirtyX1 Then dirtyX1 = r1X1
                                    If r1Y1 > dirtyY1 Then dirtyY1 = r1Y1
                                End If

                                ' Update tracked window geometry
                                winTrackX(wId) = twdesc.X
                                winTrackY(wId) = twdesc.Y
                                winTrackW(wId) = twdesc.Width
                                winTrackH(wId) = twdesc.Height
                                winTrackState(wId) = twdesc.State
                            End If
                            twi = twi + 1
                        Wend
                    End If

                    ' If no window moved, but desktopDirty is True (focus change, client redraw, telemetry)
                    ' flush full screen so 100% of screen updates reach VRAM
                    If Not anyWindowMoved Then
                        dirtyX0 = 0
                        dirtyY0 = 0
                        dirtyX1 = dispInfo.Width
                        dirtyY1 = dispInfo.Height
                    Else
                        ' Expand with cursor bounds
                        If oldCursorX < dirtyX0 Then dirtyX0 = oldCursorX
                        If oldCursorY < dirtyY0 Then dirtyY0 = oldCursorY
                        If (oldCursorX + CURSOR_W) > dirtyX1 Then dirtyX1 = oldCursorX + CURSOR_W
                        If (oldCursorY + CURSOR_H) > dirtyY1 Then dirtyY1 = oldCursorY + CURSOR_H

                        If cursorX < dirtyX0 Then dirtyX0 = cursorX
                        If cursorY < dirtyY0 Then dirtyY0 = cursorY
                        If (cursorX + CURSOR_W) > dirtyX1 Then dirtyX1 = cursorX + CURSOR_W
                        If (cursorY + CURSOR_H) > dirtyY1 Then dirtyY1 = cursorY + CURSOR_H
                    End If

                    DrawDesktopScene
                    If pWindowTable <> 0 Then
                        lastRenderedRevision = pWindowTable.Revision
                    End If
                    desktopDirty = False

                    RenderMouseCoordinates False
                    RenderTelemetryBadge False

                    SaveCursorBackground cursorX, cursorY
                    DrawCursorArrow cursorX, cursorY

                    ' 2. Flush ONLY the calculated dirty bounding box to VRAM
                    If dirtyX0 < 0 Then dirtyX0 = 0
                    If dirtyY0 < 0 Then dirtyY0 = 0
                    If dirtyX1 > dispInfo.Width Then dirtyX1 = dispInfo.Width
                    If dirtyY1 > dispInfo.Height Then dirtyY1 = dispInfo.Height
                    Dim dirtyW As Int32 = dirtyX1 - dirtyX0
                    Dim dirtyH As Int32 = dirtyY1 - dirtyY0
                    If dirtyW > 0 And dirtyH > 0 Then
                        FlushDirtyRegion dirtyX0, dirtyY0, dirtyW, dirtyH
                        FlushDirtyRegion 430, 6, 180, 14
                        If badgeActive Then
                            FlushDirtyRegion badgeX, badgeY, 200, 26
                        End If
                    End If

                    oldCursorX = cursorX
                    oldCursorY = cursorY
                    mouseDirty = False
                ElseIf mouseDirty Then
                    cursorX = targetMx
                    cursorY = targetMy
                    RestoreCursorBackground oldCursorX, oldCursorY
                    FlushDirtyRegion oldCursorX, oldCursorY, CURSOR_W, CURSOR_H
                    SaveCursorBackground cursorX, cursorY
                    DrawCursorArrow cursorX, cursorY
                    FlushDirtyRegion cursorX, cursorY, CURSOR_W, CURSOR_H
                    oldCursorX = cursorX
                    oldCursorY = cursorY
                    mouseDirty = False
                    RenderMouseCoordinates True
                    RenderTelemetryBadge True
                Else
                    RenderTelemetryBadge True
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

            ' E. Pacing: Sleep until the next 16ms presentation deadline (0% idle CPU)
            nowTime = GetUptime()
            If nextFrameTime > nowTime Then
                Dim waitRemaining As UInt64 = nextFrameTime - nowTime
                If waitRemaining >= 10 Then
                    ProcessSleep 10
                Else
                    ProcessYield
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
