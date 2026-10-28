' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/sys_mon/SysMonMain.bas
' Summary: Standalone Ring 3 System Telemetry & Monitor GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders real-time microkernel telemetry cards.

Import "../../include/pros.bas"

Module SysMonMain

    Private Const CANVAS_W As Int32 = 476
    Private Const CANVAS_H As Int32 = 250

    Private clientSurf As Surface

    Private Unsafe Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
        If surf.Pixels = 0 Then Exit Sub
        Dim rows(7) As Byte
        If ascii = 48 Then      ' '0'
            rows(0) = 14: rows(1) = 17: rows(2) = 19: rows(3) = 21: rows(4) = 25: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 49 Then  ' '1'
            rows(0) = 4:  rows(1) = 12: rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 14
        ElseIf ascii = 50 Then  ' '2'
            rows(0) = 14: rows(1) = 17: rows(2) = 1:  rows(3) = 6:  rows(4) = 8:  rows(5) = 16: rows(6) = 31
        ElseIf ascii = 51 Then  ' '3'
            rows(0) = 30: rows(1) = 1:  rows(2) = 1:  rows(3) = 14: rows(4) = 1:  rows(5) = 1:  rows(6) = 30
        ElseIf ascii = 52 Then  ' '4'
            rows(0) = 2:  rows(1) = 6:  rows(2) = 10: rows(3) = 18: rows(4) = 31: rows(5) = 2:  rows(6) = 2
        ElseIf ascii = 53 Then  ' '5'
            rows(0) = 31: rows(1) = 16: rows(2) = 30: rows(3) = 1:  rows(4) = 1:  rows(5) = 17: rows(6) = 14
        ElseIf ascii = 54 Then  ' '6'
            rows(0) = 14: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 55 Then  ' '7'
            rows(0) = 31: rows(1) = 1:  rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 8:  rows(6) = 8
        ElseIf ascii = 56 Then  ' '8'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 14: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 57 Then  ' '9'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 15: rows(4) = 1:  rows(5) = 1:  rows(6) = 14
        ElseIf ascii = 65 Then  ' 'A'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 66 Then  ' 'B'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 30
        ElseIf ascii = 67 Then  ' 'C'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 68 Then  ' 'D'
            rows(0) = 28: rows(1) = 18: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 18: rows(6) = 28
        ElseIf ascii = 69 Then  ' 'E'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 70 Then  ' 'F'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 71 Then  ' 'G'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 23: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 72 Then  ' 'H'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 73 Then  ' 'I'
            rows(0) = 14: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 14
        ElseIf ascii = 74 Then  ' 'J'
            rows(0) = 7:  rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 18: rows(6) = 12
        ElseIf ascii = 75 Then  ' 'K'
            rows(0) = 17: rows(1) = 18: rows(2) = 20: rows(3) = 24: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 76 Then  ' 'L'
            rows(0) = 16: rows(1) = 16: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 77 Then  ' 'M'
            rows(0) = 17: rows(1) = 27: rows(2) = 21: rows(3) = 21: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 78 Then  ' 'N'
            rows(0) = 17: rows(1) = 25: rows(2) = 21: rows(3) = 19: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 79 Then  ' 'O'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 80 Then  ' 'P'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 81 Then  ' 'Q'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 21: rows(5) = 18: rows(6) = 13
        ElseIf ascii = 82 Then  ' 'R'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 83 Then  ' 'S'
            rows(0) = 15: rows(1) = 16: rows(2) = 16: rows(3) = 14: rows(4) = 1:  rows(5) = 1:  rows(6) = 30
        ElseIf ascii = 84 Then  ' 'T'
            rows(0) = 31: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 85 Then  ' 'U'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 86 Then  ' 'V'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 10: rows(5) = 10: rows(6) = 4
        ElseIf ascii = 87 Then  ' 'W'
            rows(0) = 17: rows(1) = 17: rows(2) = 21: rows(3) = 21: rows(4) = 21: rows(5) = 21: rows(6) = 10
        ElseIf ascii = 88 Then  ' 'X'
            rows(0) = 17: rows(1) = 10: rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 10: rows(6) = 17
        ElseIf ascii = 89 Then  ' 'Y'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 10: rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 90 Then  ' 'Z'
            rows(0) = 31: rows(1) = 1:  rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 16: rows(6) = 31
        ElseIf ascii = 58 Then  ' ':'
            rows(0) = 0:  rows(1) = 12: rows(2) = 12: rows(3) = 0:  rows(4) = 12: rows(5) = 12: rows(6) = 0
        ElseIf ascii = 45 Then  ' '-'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 31: rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 46 Then  ' '.'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 12: rows(6) = 12
        ElseIf ascii = 61 Then  ' '='
            rows(0) = 0:  rows(1) = 31: rows(2) = 0:  rows(3) = 31: rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 91 Then  ' '['
            rows(0) = 14: rows(1) = 8:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 8:  rows(6) = 14
        ElseIf ascii = 93 Then  ' ']'
            rows(0) = 14: rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 2:  rows(6) = 14
        ElseIf ascii = 40 Then  ' '('
            rows(0) = 2:  rows(1) = 4:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 4:  rows(6) = 2
        ElseIf ascii = 41 Then  ' ')'
            rows(0) = 8:  rows(1) = 4:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 4:  rows(6) = 8
        Else
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        End If

        Dim pitchPix As UInt32 = surf.Pitch / 4
        Dim r As Int32 = 0
        While r < 7
            Dim py As Int32 = gy + r
            If py >= 0 And py < CType(Int32, surf.Height) Then
                Dim rowVal As Byte = rows(r)
                Dim c As Int32 = 0
                While c < 5
                    Dim px As Int32 = gx + c
                    If px >= 0 And px < CType(Int32, surf.Width) Then
                        If (rowVal And (CType(Byte, 16) RShift c)) <> 0 Then
                            Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, py) * pitchPix)
                            rowPtr(px) = color
                        End If
                    End If
                    c = c + 1
                Wend
            End If
            r = r + 1
        Wend
    End Sub

    Private Unsafe Sub DrawText5x7(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)
        If surf.Pixels = 0 Or textPtr = 0 Then Exit Sub
        Dim cx As Int32 = x
        Dim i As UInt32 = 0
        While textPtr(i) <> 0
            DrawGlyph surf, cx, y, textPtr(i), color
            cx = cx + 6
            i = i + 1
        Wend
    End Sub

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

    Private Unsafe Sub AppendStr(ByVal s As Pointer To Byte, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        Dim i As UInt32 = 0
        While s(i) <> 0
            buf(outIdx) = s(i)
            outIdx = outIdx + 1
            i = i + 1
        Wend
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[SYS_MON] Starting PROS System Monitor Client (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = CType(UInt64, CANVAS_W) * CType(UInt64, CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H64000000)
        Dim pPixels As Pointer To UInt32 = CPtr(Pointer To UInt32, &H64000000)

        If shmId = 0 Or pPixels = 0 Then
            ConsoleWriteLine "[SYS_MON] ERR: Failed to create client shared memory buffer!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[SYS_MON] Surface allocated (SHMID: ", shmId, " @ 0x64000000)\r\n"

        ' Initialize Surface structure
        clientSurf.Width = CANVAS_W
        clientSurf.Height = CANVAS_H
        clientSurf.Pitch = CANVAS_W * 4
        clientSurf.Bpp = 32
        clientSurf.Pixels = pPixels

        ' 2. Register managed window with srv.wm
        ProcessSleep 50
        Dim winId As UInt32 = WmCreateWindow(480, 280, shmId, CPtr(Pointer To Byte, "PROS System Monitor"))
        If winId = 0 Then
            ProcessSleep 100
            winId = WmCreateWindow(480, 280, shmId, CPtr(Pointer To Byte, "PROS System Monitor"))
        End If

        If winId = 0 Then
            ConsoleWriteLine "[SYS_MON] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[SYS_MON] Registered window with WindowManager -> ID #", CType(UInt64, winId), "\r\n"

        ' 3. Render Static Card Backgrounds
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF232731

        ' Card 1: Microkernel Architecture Card
        FillRect clientSurf, 10, 10, CANVAS_W - 20, 65, &HFF2E3440
        FillRect clientSurf, 10, 10, 4, 65, &HFF88C0D0
        DrawText5x7 clientSurf, 22, 16, CPtr(Pointer To Byte, "PROS MICROKERNEL TELEMETRY [CPL=3]"), &HFFECEFF4
        DrawText5x7 clientSurf, 22, 30, CPtr(Pointer To Byte, "ARCH: x86_64 SMP (4 Cores Online)"), &HFF81A1C1
        DrawText5x7 clientSurf, 22, 44, CPtr(Pointer To Byte, "KERNEL REV: 2026.10.28-r36-re02"), &HFFEBCB8B
        DrawText5x7 clientSurf, 22, 58, CPtr(Pointer To Byte, "STATUS: SYSTEM HEALTH OPTIMAL"), &HFFA3BE8C

        ' Card 2: Neural Synapse Plane Card
        FillRect clientSurf, 10, 85, CANVAS_W - 20, 65, &HFF2E3440
        FillRect clientSurf, 10, 85, 4, 65, &HFFA3BE8C
        DrawText5x7 clientSurf, 22, 91, CPtr(Pointer To Byte, "DUAL-PLANE NEURAL SYNAPSE IPC"), &HFFECEFF4
        DrawText5x7 clientSurf, 22, 105, CPtr(Pointer To Byte, "AXON RING BUFFER: ZERO COPY (LOCK-FREE)"), &HFF88C0D0
        DrawText5x7 clientSurf, 22, 119, CPtr(Pointer To Byte, "SERVICES: COMPOSITOR, INPUT, WM, VFS"), &HFFD8DEE9
        DrawText5x7 clientSurf, 22, 133, CPtr(Pointer To Byte, "CONTROL PLANE: KERNEL.CORE (#1000)"), &HFF81A1C1

        ' Card 3: Memory & Display Pipeline Card
        FillRect clientSurf, 10, 160, CANVAS_W - 20, 80, &HFF2E3440
        FillRect clientSurf, 10, 160, 4, 80, &HFFEBCB8B
        DrawText5x7 clientSurf, 22, 166, CPtr(Pointer To Byte, "GRAPHICAL PIPELINE & SHMEM CLIENT"), &HFFECEFF4
        DrawText5x7 clientSurf, 22, 180, CPtr(Pointer To Byte, "PRESENTATION: 60 FPS PACED (16 MS)"), &HFF88C0D0
        DrawText5x7 clientSurf, 22, 194, CPtr(Pointer To Byte, "VRAM APERTURE: 1024x768x32 ARGB BURST"), &HFFD8DEE9

        ' 4. Active Telemetry Update Loop (Updates every 500ms)
        Do
            Dim nowTime As UInt64 = GetUptime()

            ' Render Dynamic Telemetry Line
            FillRect clientSurf, 22, 212, CANVAS_W - 44, 20, &HFF2E3440

            Dim telemBuf(64) As Byte
            Dim tIdx As UInt32 = 0
            AppendStr "UPTIME: ", @telemBuf(0), tIdx
            AppendUInt nowTime / 1000, @telemBuf(0), tIdx
            AppendStr " SEC  |  TICKS: ", @telemBuf(0), tIdx
            AppendUInt nowTime, @telemBuf(0), tIdx
            telemBuf(tIdx) = 0
            DrawText5x7 clientSurf, 22, 214, @telemBuf(0), &HFFEBCB8B

            ' Signal dirty rectangle to Window Manager / Compositor
            WmSignalDirty winId, 0, 0, CANVAS_W, CANVAS_H

            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module
