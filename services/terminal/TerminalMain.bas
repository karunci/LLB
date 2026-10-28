' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/terminal/TerminalMain.bas
' Summary: Standalone Ring 3 Interactive Terminal Shell GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders terminal shell prompt and blinking block cursor.

Import "../../include/pros.bas"

Module TerminalMain

    Private Const CANVAS_W As Int32 = 416
    Private Const CANVAS_H As Int32 = 210

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
        ElseIf ascii = 65 Or ascii = 97 Then  ' 'A'/'a'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 66 Or ascii = 98 Then  ' 'B'/'b'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 30
        ElseIf ascii = 67 Or ascii = 99 Then  ' 'C'/'c'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 68 Or ascii = 100 Then ' 'D'/'d'
            rows(0) = 28: rows(1) = 18: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 18: rows(6) = 28
        ElseIf ascii = 69 Or ascii = 101 Then ' 'E'/'e'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 70 Or ascii = 102 Then ' 'F'/'f'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 71 Or ascii = 103 Then ' 'G'/'g'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 23: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 72 Or ascii = 104 Then ' 'H'/'h'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 73 Or ascii = 105 Then ' 'I'/'i'
            rows(0) = 14: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 14
        ElseIf ascii = 74 Or ascii = 106 Then ' 'J'/'j'
            rows(0) = 7:  rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 18: rows(6) = 12
        ElseIf ascii = 75 Or ascii = 107 Then ' 'K'/'k'
            rows(0) = 17: rows(1) = 18: rows(2) = 20: rows(3) = 24: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 76 Or ascii = 108 Then ' 'L'/'l'
            rows(0) = 16: rows(1) = 16: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 77 Or ascii = 109 Then ' 'M'/'m'
            rows(0) = 17: rows(1) = 27: rows(2) = 21: rows(3) = 21: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 78 Or ascii = 110 Then ' 'N'/'n'
            rows(0) = 17: rows(1) = 25: rows(2) = 21: rows(3) = 19: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 79 Or ascii = 111 Then ' 'O'/'o'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 80 Or ascii = 112 Then ' 'P'/'p'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 81 Or ascii = 113 Then ' 'Q'/'q'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 21: rows(5) = 18: rows(6) = 13
        ElseIf ascii = 82 Or ascii = 114 Then ' 'R'/'r'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 83 Or ascii = 115 Then ' 'S'/'s'
            rows(0) = 15: rows(1) = 16: rows(2) = 16: rows(3) = 14: rows(4) = 1:  rows(5) = 1:  rows(6) = 30
        ElseIf ascii = 84 Or ascii = 116 Then ' 'T'/'t'
            rows(0) = 31: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 85 Or ascii = 117 Then ' 'U'/'u'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 86 Or ascii = 118 Then ' 'V'/'v'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 10: rows(5) = 10: rows(6) = 4
        ElseIf ascii = 87 Or ascii = 119 Then ' 'W'/'w'
            rows(0) = 17: rows(1) = 17: rows(2) = 21: rows(3) = 21: rows(4) = 21: rows(5) = 21: rows(6) = 10
        ElseIf ascii = 88 Or ascii = 120 Then ' 'X'/'x'
            rows(0) = 17: rows(1) = 10: rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 10: rows(6) = 17
        ElseIf ascii = 89 Or ascii = 121 Then ' 'Y'/'y'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 10: rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 90 Or ascii = 122 Then ' 'Z'/'z'
            rows(0) = 31: rows(1) = 1:  rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 16: rows(6) = 31
        ElseIf ascii = 58 Then  ' ':'
            rows(0) = 0:  rows(1) = 12: rows(2) = 12: rows(3) = 0:  rows(4) = 12: rows(5) = 12: rows(6) = 0
        ElseIf ascii = 45 Then  ' '-'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 31: rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 46 Then  ' '.'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 12: rows(6) = 12
        ElseIf ascii = 62 Then  ' '>'
            rows(0) = 16: rows(1) = 8:  rows(2) = 4:  rows(3) = 2:  rows(4) = 4:  rows(5) = 8:  rows(6) = 16
        ElseIf ascii = 92 Then  ' '\'
            rows(0) = 16: rows(1) = 16: rows(2) = 8:  rows(3) = 4:  rows(4) = 2:  rows(5) = 1:  rows(6) = 1
        ElseIf ascii = 39 Then  ' '\''
            rows(0) = 12: rows(1) = 12: rows(2) = 8:  rows(3) = 0:  rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 91 Then  ' '['
            rows(0) = 14: rows(1) = 8:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 8:  rows(6) = 14
        ElseIf ascii = 93 Then  ' ']'
            rows(0) = 14: rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 2:  rows(6) = 14
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

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[TERMINAL] Starting PROS Terminal Console Shell (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = CType(UInt64, CANVAS_W) * CType(UInt64, CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H65000000)
        Dim pPixels As Pointer To UInt32 = CPtr(Pointer To UInt32, &H65000000)

        If shmId = 0 Or pPixels = 0 Then
            ConsoleWriteLine "[TERMINAL] ERR: Failed to create client shared memory buffer!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[TERMINAL] Surface allocated (SHMID: ", shmId, " @ 0x65000000)\r\n"

        ' Initialize Surface structure
        clientSurf.Width = CANVAS_W
        clientSurf.Height = CANVAS_H
        clientSurf.Pitch = CANVAS_W * 4
        clientSurf.Bpp = 32
        clientSurf.Pixels = pPixels

        ' 2. Register managed window with srv.wm
        Dim winId As UInt32 = 0
        Dim regTries As UInt32 = 0
        While regTries < 25 And winId = 0
            winId = WmCreateWindow(420, 240, shmId, CPtr(Pointer To Byte, "PROS Terminal Console"))
            If winId = 0 Then
                ProcessSleep 40
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[TERMINAL] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[TERMINAL] Registered window with WindowManager -> ID #", CType(UInt64, winId), "\r\n"

        ' 3. Render Static Terminal Layout
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF1E222A

        ' Status Bar Header
        FillRect clientSurf, 0, 0, CANVAS_W, 20, &HFF232731
        FillRect clientSurf, 0, 19, CANVAS_W, 1, &HFF3B4252
        DrawText5x7 clientSurf, 10, 6, CPtr(Pointer To Byte, "PROS TERMINAL CONSOLE  [TTY 1]  CPL=3"), &HFF88C0D0

        ' Terminal Output History
        DrawText5x7 clientSurf, 12, 28, CPtr(Pointer To Byte, "PRK-LLB Interactive Diagnostic Shell v1.0"), &HFFD8DEE9
        DrawText5x7 clientSurf, 12, 42, CPtr(Pointer To Byte, "Type 'help' for built-in diagnostic routines"), &HFF4C566A
        
        DrawText5x7 clientSurf, 12, 62, CPtr(Pointer To Byte, "pros:\> sys.status"), &HFFEBCB8B
        DrawText5x7 clientSurf, 12, 76, CPtr(Pointer To Byte, "  KERNEL  : PRK-LLB Microkernel SMP 4 Cores"), &HFFA3BE8C
        DrawText5x7 clientSurf, 12, 90, CPtr(Pointer To Byte, "  PIPELINE: Zero-Copy Shared Memory Framebuffer"), &HFF81A1C1
        DrawText5x7 clientSurf, 12, 104, CPtr(Pointer To Byte, "  SYNAPSE : Axon Inter-Process Router Active"), &HFF88C0D0
        DrawText5x7 clientSurf, 12, 118, CPtr(Pointer To Byte, "  MEMORY  : Lower-Half Canonical Space Isolated"), &HFFECEFF4

        DrawText5x7 clientSurf, 12, 138, CPtr(Pointer To Byte, "pros:\> ps -e"), &HFFEBCB8B
        DrawText5x7 clientSurf, 12, 152, CPtr(Pointer To Byte, "  PID 1: genesis  PID 4: compositor  PID 7: wm"), &HFFD8DEE9

        DrawText5x7 clientSurf, 12, 174, CPtr(Pointer To Byte, "pros:\> "), &HFFEBCB8B

        ' 4. Blinking Cursor Loop (Toggles every 500ms)
        Dim cursorBlink As Boolean = True
        Do
            If cursorBlink Then
                FillRect clientSurf, 60, 174, 6, 8, &HFF88C0D0
            Else
                FillRect clientSurf, 60, 174, 6, 8, &HFF1E222A
            End If
            cursorBlink = Not cursorBlink

            ' Signal dirty rectangle
            WmSignalDirty winId, 60, 174, 6, 8

            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module
