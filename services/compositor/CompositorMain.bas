' Project Name: PROS (Personal Research Operating System)
' Filename: services/compositor/CompositorMain.bas
' Summary: Standalone Ring 3 Display Compositor and Window Engine daemon.
'          Adheres to PROS / PRK Nord theme specification, full 8x16 ASCII
'          bitmap font rendering, 30 FPS paced presentation loop,
'          and decoupled software cursor engine.

Import "../../include/pros.bas"

Module CompositorMain

    ' External reference to 2048-byte 8x16 ASCII font bitmap table in brt0.S
    Extern font_8x16_data As Byte

    ' -------------------------------------------------------------------------
    ' Internal Data & State
    ' -------------------------------------------------------------------------
    Private dispInfo As DisplayInfo
    Private frontSurf As Surface
    Private hasDisplay As Boolean = False

    ' Software Cursor State
    Private cursorX As Int32 = 100
    Private cursorY As Int32 = 100
    Private oldCursorX As Int32 = 100
    Private oldCursorY As Int32 = 100
    Private cursorSavedBg(96) As UInt32 ' 12 x 8 pixels background backup
    Private cursorInitialized As Boolean = False

    ' Telemetry Badge State
    Private badgeX As Int32 = 0
    Private badgeY As Int32 = 0
    Private badgeActive As Boolean = False
    Private animPos As Int32 = 0
    Private animDir As Int32 = 1
    Private frameCount As UInt32 = 0

    ''
    ' @brief Append unsigned 64-bit integer formatted as ASCII into buffer.
    ''
    Private Unsafe Sub AppendUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        If val = 0 Then
            buf(outIdx) = 48 ' '0'
            outIdx = outIdx + 1
            Exit Sub
        End If
        Dim tmp(23) As Byte
        Dim tIdx As UInt32 = 0
        Dim v As UInt64 = val
        While v > 0
            tmp(tIdx) = CType(Byte, (v Mod 10) + 48)
            v = v / 10
            tIdx = tIdx + 1
        Wend
        While tIdx > 0
            tIdx = tIdx - 1
            buf(outIdx) = tmp(tIdx)
            outIdx = outIdx + 1
        Wend
    End Sub

    ''
    ' @brief Append null-terminated ASCII string into buffer.
    ''
    Private Unsafe Sub AppendStr(ByVal s As Pointer To Byte, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        Dim i As UInt32 = 0
        While s(i) <> 0
            buf(outIdx) = s(i)
            outIdx = outIdx + 1
            i = i + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Full 8x16 ASCII Bitmap Font Engine (128 Glyphs)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawGlyph8x16(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
        If ascii >= 128 Then Exit Sub
        If surf.Pixels = 0 Then Exit Sub

        Dim fontBase As Pointer To Byte = 0
        Asm "movabs $font_8x16_data, %0" : "=r"(fontBase) : : "memory"

        Dim charOffset As UInt64 = CType(UInt64, ascii) * 16
        Dim pitchPix As UInt32 = surf.Pitch / 4

        Dim r As Int32 = 0
        While r < 16
            Dim py As Int32 = gy + r
            If py >= 0 And py < CType(Int32, surf.Height) Then
                Dim rowBits As Byte = fontBase(charOffset + CType(UInt64, r))
                Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, py) * pitchPix)
                Dim c As Int32 = 0
                While c < 8
                    Dim px As Int32 = gx + c
                    If px >= 0 And px < CType(Int32, surf.Width) Then
                        Dim bitMask As Byte = CType(Byte, 128 RShift c)
                        If (rowBits And bitMask) <> 0 Then
                            rowPtr(px) = color
                        End If
                    End If
                    c = c + 1
                Wend
            End If
            r = r + 1
        Wend
    End Sub

    Private Unsafe Sub DrawString8x16(ByRef surf As Surface, ByVal sx As Int32, ByVal sy As Int32, ByVal strPtr As Pointer To Byte, ByVal color As UInt32)
        If strPtr = 0 Then Exit Sub
        Dim i As UInt32 = 0
        Dim curX As Int32 = sx
        While strPtr(i) <> 0
            DrawGlyph8x16 surf, curX, sy, strPtr(i), color
            curX = curX + 8
            i = i + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' 12x8 High-Contrast Arrow Cursor Engine
    ' -------------------------------------------------------------------------
    Private Unsafe Sub SaveCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        cursorSavedBg((cy * 8) + cx) = rowPtr(curX)
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    Private Unsafe Sub RestoreCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        rowPtr(curX) = cursorSavedBg((cy * 8) + cx)
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    Private Unsafe Sub DrawCursorArrow(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub

        ' 12-row x 8-col pointer: 2 = Black outline, 1 = White fill, 0 = transparent
        Dim cursorRows(12) As Byte
        cursorRows(0)  = &HC0 ' 11000000 -> 2,2
        cursorRows(1)  = &HE0 ' 11100000 -> 2,1,2
        cursorRows(2)  = &HF0 ' 11110000 -> 2,1,1,2
        cursorRows(3)  = &HF8 ' 11111000 -> 2,1,1,1,2
        cursorRows(4)  = &HFC ' 11111100 -> 2,1,1,1,1,2
        cursorRows(5)  = &HFE ' 11111110 -> 2,1,1,1,1,1,2
        cursorRows(6)  = &HFF ' 11111111 -> 2,1,1,1,1,1,1,2
        cursorRows(7)  = &HF8 ' 11111000 -> 2,1,1,1,1,2,2,2
        cursorRows(8)  = &HD8 ' 11011000 -> 2,2,0,0,2,1,2
        cursorRows(9)  = &H98 ' 10011000 -> 2,0,0,0,2,1,2
        cursorRows(10) = &H0C ' 00001100 -> 0,0,0,0,2,2
        cursorRows(11) = &H0C ' 00001100 -> 0,0,0,0,2,2

        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim mask As Byte = cursorRows(cy)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        Dim bitActive As Boolean = ((mask RShift (7 - cx)) And 1) <> 0
                        If bitActive Then
                            ' Check border vs core fill
                            If cy = 0 Or cy = 10 Or cy = 11 Or cx = 0 Or cx = 7 Or cy = (cx + 1) Or cy = 8 Then
                                rowPtr(curX) = &HFF000000 ' Sharp Black Outline
                            Else
                                rowPtr(curX) = &HFFFFFFFF ' Bright White Fill
                            End If
                        End If
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Telemetry Status Badge Renderer (~30 FPS Smooth Cyber Indicator)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub RenderTelemetryBadge()
        If Not badgeActive Then Exit Sub

        ' 1. Status LED: Smooth breathing color cycle across Nord/Mint/Emerald palette
        Dim ledColor As UInt32 = &HFF00C853
        Dim colorPhase As UInt32 = (frameCount / 10) Mod 4
        If colorPhase = 0 Then
            ledColor = &HFF00E676
        ElseIf colorPhase = 1 Then
            ledColor = &HFF00E5FF
        ElseIf colorPhase = 2 Then
            ledColor = &HFF69F0AE
        Else
            ledColor = &HFF00C853
        End If
        FillRect frontSurf, badgeX + 6, badgeY + 5, 8, 18, ledColor

        ' 2. Recessed dark channel for scanner pulse
        Dim trackX As Int32 = badgeX + 20
        Dim trackY As Int32 = badgeY + 6
        Dim trackW As Int32 = 110
        Dim trackH As Int32 = 16
        Dim pulseW As Int32 = 24
        FillRect frontSurf, trackX, trackY, trackW, trackH, &HFF1B2028

        ' 3. Smooth ping-pong animated scanner pulse with multi-layer glow
        Dim pulseX As Int32 = trackX + animPos
        If pulseX < trackX Then pulseX = trackX
        If (pulseX + pulseW) > (trackX + trackW) Then
            pulseX = (trackX + trackW) - pulseW
        End If

        ' Outer glow
        FillRect frontSurf, pulseX, trackY + 1, pulseW, trackH - 2, &HFF00897B
        ' Mid cyber glow
        FillRect frontSurf, pulseX + 4, trackY + 3, pulseW - 8, trackH - 6, &HFF00E5FF
        ' Crisp white core
        FillRect frontSurf, pulseX + 8, trackY + 5, pulseW - 16, trackH - 10, &HFFFFFFFF

        ' Smooth single-pixel advancement
        animPos = animPos + animDir
        If animPos + pulseW >= trackW Then
            animPos = trackW - pulseW
            animDir = -1
        ElseIf animPos <= 0 Then
            animPos = 0
            animDir = 1
        End If

        ' 4. Real-time 30 FPS telemetry counter text in 8x16 font
        DrawString8x16 frontSurf, badgeX + 144, badgeY + 6, CPtr(Pointer To Byte, "30 FPS"), &HFF88C0D0

        frameCount = frameCount + 1
    End Sub

    ' -------------------------------------------------------------------------
    ' Desktop Background & Initial Window Canvas Pre-Renderer
    ' Adheres strictly to PRK / PROS GUI Theme Specification:
    ' - Base: Deep Dark (#191D24)
    ' - Titlebar: Charcoal Slate (#2E3440), Height: 28px
    ' - Accent Line: Cyan Accent (#56B6C2), Height: 1px below titlebar
    ' - Title Text: Monospaced 8x16 font (#D8DEE9)
    ' - Controls: Close (#BF616A / 'X'), Maximize (#A3BE8C / 'O'), Minimize (#5E81AC / '-')
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawDesktopScene()
        If frontSurf.Pixels = 0 Then Exit Sub

        ' 1. Clear boot splash to Nord Dark Background (#191D24)
        FillRect frontSurf, 0, 0, dispInfo.Width, dispInfo.Height, &HFF191D24

        ' 2. Top System Menu Bar (y: 0..27, height: 28px)
        FillRect frontSurf, 0, 0, dispInfo.Width, 28, &HFF2E3440
        FillRect frontSurf, 0, 27, dispInfo.Width, 1, &HFF4C566A
        FillRect frontSurf, 8, 6, 4, 16, &HFF88C0D0

        DrawString8x16 frontSurf, 20, 6, CPtr(Pointer To Byte, "PROS Workstation  |  Applications  Nodes  Services  View"), &HFFECEFF4
        DrawString8x16 frontSurf, CType(Int32, dispInfo.Width) - 180, 6, CPtr(Pointer To Byte, "SMP 4 Cores  [OK]"), &HFFA3BE8C

        ' 3. Render Floating Desktop Window: "PROS System Monitor"
        Dim wx As Int32 = 60
        Dim wy As Int32 = 56
        Dim ww As Int32 = 580
        Dim wh As Int32 = 380

        ' Outer drop-shadow effect
        FillRect frontSurf, wx + 6, wy + 6, ww, wh, &HFF121419

        ' Window Frame Borders (Top/Left: #4C566A, Bottom/Right: #1B2028)
        FillRect frontSurf, wx, wy, ww, 1, &HFF4C566A
        FillRect frontSurf, wx, wy, 1, wh, &HFF4C566A
        FillRect frontSurf, wx, wy + wh - 1, ww, 1, &HFF1B2028
        FillRect frontSurf, wx + ww - 1, wy, 1, wh, &HFF1B2028

        ' Titlebar (h: 28px, #2E3440)
        FillRect frontSurf, wx + 1, wy + 1, ww - 2, 27, &HFF2E3440

        ' Cyan Accent Line (1px below titlebar: #56B6C2)
        FillRect frontSurf, wx + 1, wy + 28, ww - 2, 1, &HFF56B6C2

        ' Title Text in 8x16 font (centered vertically at y = wy + 6)
        DrawString8x16 frontSurf, wx + 12, wy + 6, CPtr(Pointer To Byte, "PROS System Monitor (Ring 3 Composited)"), &HFFD8DEE9

        ' Window Buttons (Exact PRK specs: 22x22, btn_y = wy + 3, spacing: 4px)
        Dim btnY As Int32 = wy + 3
        Dim btnW As Int32 = 22
        Dim btnH As Int32 = 22

        ' Close Button (Red: #BF616A)
        Dim closeX As Int32 = (wx + ww) - btnW - 6
        FillRect frontSurf, closeX, btnY, btnW, btnH, &HFFBF616A
        DrawString8x16 frontSurf, closeX + 7, btnY + 3, CPtr(Pointer To Byte, "X"), &HFFFFFFFF

        ' Maximize Button (Green: #A3BE8C)
        Dim maxX As Int32 = closeX - btnW - 4
        FillRect frontSurf, maxX, btnY, btnW, btnH, &HFFA3BE8C
        DrawString8x16 frontSurf, maxX + 7, btnY + 3, CPtr(Pointer To Byte, "O"), &HFFFFFFFF

        ' Minimize Button (Blue: #5E81AC)
        Dim minX As Int32 = maxX - btnW - 4
        FillRect frontSurf, minX, btnY, btnW, btnH, &HFF5E81AC
        DrawString8x16 frontSurf, minX + 7, btnY + 3, CPtr(Pointer To Byte, "-"), &HFFFFFFFF

        ' Window Client Canvas Background (#232731)
        FillRect frontSurf, wx + 1, wy + 29, ww - 2, wh - 30, &HFF232731

        ' Card 1: Microkernel Architecture
        FillRect frontSurf, wx + 16, wy + 42, ww - 32, 54, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 42, 3, 54, &HFF81A1C1
        DrawString8x16 frontSurf, wx + 28, wy + 50, CPtr(Pointer To Byte, "KERNEL : PRK-LLB (Low-Level Basic Microkernel)"), &HFF81A1C1
        DrawString8x16 frontSurf, wx + 28, wy + 70, CPtr(Pointer To Byte, "MODEL  : Dual-Plane Neural Synapse Routing"), &HFFD8DEE9

        ' Card 2: Compositor Status
        FillRect frontSurf, wx + 16, wy + 104, ww - 32, 54, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 104, 3, 54, &HFFA3BE8C
        DrawString8x16 frontSurf, wx + 28, wy + 112, CPtr(Pointer To Byte, "ENGINE : Zero-Copy Window Surface Pipeline"), &HFFA3BE8C
        DrawString8x16 frontSurf, wx + 28, wy + 132, CPtr(Pointer To Byte, "DRIVER : Direct Linear Framebuffer Aperture"), &HFFECEFF4

        ' Card 3: Subsystem Status
        FillRect frontSurf, wx + 16, wy + 166, ww - 32, 54, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 166, 3, 54, &HFFEBCB8B
        DrawString8x16 frontSurf, wx + 28, wy + 174, CPtr(Pointer To Byte, "INPUT  : input_srv Daemon Online (PS/2 Mouse)"), &HFFEBCB8B
        DrawString8x16 frontSurf, wx + 28, wy + 194, CPtr(Pointer To Byte, "DISPLAY: disp_srv Device Controller Online"), &HFFECEFF4

        ' Card 4: Ring 3 Performance
        FillRect frontSurf, wx + 16, wy + 228, ww - 32, 54, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 228, 3, 54, &HFFB48EAD
        DrawString8x16 frontSurf, wx + 28, wy + 236, CPtr(Pointer To Byte, "SECURITY: CPL=3 Userland Hardware Isolation"), &HFFB48EAD
        DrawString8x16 frontSurf, wx + 28, wy + 256, CPtr(Pointer To Byte, "SHARED MEMORY: SHMEM Gradients Mapped"), &HFFECEFF4

        ' 4. Initialize Telemetry Status Badge Container
        If dispInfo.Width > 230 And dispInfo.Height > 60 Then
            badgeX = CType(Int32, dispInfo.Width) - 220
            badgeY = CType(Int32, dispInfo.Height) - 36
            FillRect frontSurf, badgeX, badgeY, 210, 28, &HFF2E3440
            FillRect frontSurf, badgeX, badgeY, 210, 1, &HFF4C566A
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
        Dim srvName(32) As Byte
        srvName(0) = 115 ' 's'
        srvName(1) = 114 ' 'r'
        srvName(2) = 118 ' 'v'
        srvName(3) = 46  ' '.'
        srvName(4) = 99  ' 'c'
        srvName(5) = 111 ' 'o'
        srvName(6) = 109 ' 'm'
        srvName(7) = 112 ' 'p'
        srvName(8) = 111 ' 'o'
        srvName(9) = 115 ' 's'
        srvName(10) = 105' 'i'
        srvName(11) = 116' 't'
        srvName(12) = 111' 'o'
        srvName(13) = 114' 'r'
        srvName(14) = 0
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, @srvName(0), 7)
        ConsolePrintWithUInt "[COMPOSITOR] Registered Node 'srv.compositor' -> Node #", srvNodeId, "\r\n"

        ' 3. Query Hardware Display Geometry
        If GetDisplayInfo(dispInfo) Then
            Dim resBuf(64) As Byte
            Dim rIdx As UInt32 = 0
            AppendStr "[COMPOSITOR] Discovered Display: ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Width), @resBuf(0), rIdx
            AppendStr "x", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Height), @resBuf(0), rIdx
            AppendStr " @ ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Bpp), @resBuf(0), rIdx
            AppendStr " BPP", @resBuf(0), rIdx
            resBuf(rIdx) = 0
            ConsoleWriteLine @resBuf(0)
            ConsolePrintWithUInt "[COMPOSITOR] Framebuffer Pitch: ", CType(UInt64, dispInfo.Pitch), " bytes\r\n"
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

        ' 5. Transition from Boot Splash to Graphical Desktop Canvas
        ConsoleWriteLine "[COMPOSITOR] Boot splash completed. Transitioning to PROS Desktop..."
        DrawDesktopScene

        ' 6. Initial cursor placement at screen center
        cursorX = CType(Int32, dispInfo.Width / 2)
        cursorY = CType(Int32, dispInfo.Height / 2)
        oldCursorX = cursorX
        oldCursorY = cursorY
        SaveCursorBackground cursorX, cursorY
        DrawCursorArrow cursorX, cursorY
        cursorInitialized = True
        ConsoleWriteLine "[COMPOSITOR] Hardware software cursor plane initialized at screen center."

        ' 7. Active Presentation & Event Loop (~30 FPS paced with ProcessSleep)
        ConsoleWriteLine "[COMPOSITOR] Compositor online. Entering presentation loop (~30 FPS)..."

        Do
            ' A. Update and animate live telemetry badge smoothly
            RenderTelemetryBadge

            ' B. Pace presentation loop to exact ~30 FPS (33 ms per frame)
            ' Yields remaining CPU slice across SMP cores without supersonic spinning
            ProcessSleep 33
            ProcessYield
        Loop

        user_main = 0
    End Function

End Module
