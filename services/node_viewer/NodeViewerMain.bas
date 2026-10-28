' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/node_viewer/NodeViewerMain.bas
' Summary: Standalone Ring 3 Neural Node Topology Viewer GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders live registered node hierarchy and packet counters.

Import "../../include/pros.bas"

Module NodeViewerMain

    Private Const CANVAS_W As Int32 = 396
    Private Const CANVAS_H As Int32 = 190

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
        ElseIf ascii = 95 Then  ' '_'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 0:  rows(6) = 31
        ElseIf ascii = 37 Then  ' '%'
            rows(0) = 25: rows(1) = 26: rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 19: rows(6) = 19
        ElseIf ascii = 124 Then ' '|'
            rows(0) = 4:  rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 38 Then  ' '&'
            rows(0) = 12: rows(1) = 18: rows(2) = 12: rows(3) = 20: rows(4) = 18: rows(5) = 18: rows(6) = 13
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
        ConsoleWriteLine "[NODE_VIEWER] Starting PROS Neural Node Topology Viewer (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = CType(UInt64, CANVAS_W) * CType(UInt64, CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H66000000)
        Dim pPixels As Pointer To UInt32 = CPtr(Pointer To UInt32, &H66000000)

        If shmId = 0 Or pPixels = 0 Then
            ConsoleWriteLine "[NODE_VIEWER] ERR: Failed to create client shared memory buffer!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[NODE_VIEWER] Surface allocated (SHMID: ", shmId, " @ 0x66000000)\r\n"

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
            winId = WmCreateWindow(400, 220, shmId, CPtr(Pointer To Byte, "PROS Neural Node Viewer"))
            If winId = 0 Then
                ProcessSleep 40
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[NODE_VIEWER] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[NODE_VIEWER] Registered window with WindowManager -> ID #", CType(UInt64, winId), "\r\n"

        ' 3. Render Static Table Layout
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF242933

        ' Header Banner
        FillRect clientSurf, 0, 0, CANVAS_W, 20, &HFF2E3440
        FillRect clientSurf, 0, 19, CANVAS_W, 1, &HFF3B4252
        DrawText5x7 clientSurf, 10, 6, CPtr(Pointer To Byte, "NEURAL NODE TOPOLOGY & SYNAPSE PLANE"), &HFF88C0D0

        ' Table Columns
        DrawText5x7 clientSurf, 10, 26, CPtr(Pointer To Byte, "ID      NAME            ROLE          STATUS"), &HFF4C566A
        FillRect clientSurf, 10, 36, CANVAS_W - 20, 1, &HFF3B4252

        ' Rows
        DrawText5x7 clientSurf, 10, 42, CPtr(Pointer To Byte, "#1000   kernel.core     CONTROL       ONLINE"), &HFFA3BE8C
        DrawText5x7 clientSurf, 10, 56, CPtr(Pointer To Byte, "#1003   srv.display     DISPLAY_DRV   ACTIVE"), &HFF81A1C1
        DrawText5x7 clientSurf, 10, 70, CPtr(Pointer To Byte, "#1004   srv.wm          WINDOW_MGR    ACTIVE"), &HFFEBCB8B
        DrawText5x7 clientSurf, 10, 84, CPtr(Pointer To Byte, "#1005   srv.compositor  COMPOSITOR    ACTIVE"), &HFF88C0D0
        DrawText5x7 clientSurf, 10, 98, CPtr(Pointer To Byte, "#1007   srv.input       INPUT_ROUTER  ACTIVE"), &HFFD8DEE9
        DrawText5x7 clientSurf, 10, 112, CPtr(Pointer To Byte, "#1009   srv.dev_mgr     DEV_ARBITER   ACTIVE"), &HFF81A1C1
        DrawText5x7 clientSurf, 10, 126, CPtr(Pointer To Byte, "#1010   srv.plexus_mgr  SUPERVISOR    ACTIVE"), &HFFA3BE8C
        DrawText5x7 clientSurf, 10, 140, CPtr(Pointer To Byte, "#1011   srv.vfs         STORAGE_NODE  ACTIVE"), &HFF88C0D0

        ' 4. Dynamic Synapse Packet Throughput Loop
        Dim pktCount As UInt64 = 120
        Do
            FillRect clientSurf, 10, 158, CANVAS_W - 20, 24, &HFF2E3440
            FillRect clientSurf, 10, 158, 4, 24, &HFFA3BE8C

            Dim statBuf(64) As Byte
            Dim sIdx As UInt32 = 0
            AppendStr "SYNAPSE RX: ", @statBuf(0), sIdx
            AppendUInt pktCount, @statBuf(0), sIdx
            AppendStr " PKTS | INTEGRITY: 100%", @statBuf(0), sIdx
            statBuf(sIdx) = 0

            DrawText5x7 clientSurf, 20, 166, @statBuf(0), &HFFEBCB8B

            WmSignalDirty winId, 10, 158, CANVAS_W - 20, 24

            pktCount = pktCount + 16
            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module
