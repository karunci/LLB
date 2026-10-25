' Project Name: PROS (Personal Research Operating System)
' Filename: services/disp_srv/DispMain.bas
' Summary: Standalone Ring 3 Display Driver Service daemon.
'          Queries hardware display configuration, maps framebuffer aperture,
'          and exposes 'srv.display' device node to client applications.

Import "../../include/pros.bas"

Module DispServiceMain

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

    ''
    ' @brief Append 64-bit integer formatted in uppercase hexadecimal into buffer.
    ''
    Private Unsafe Sub AppendHex(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef idx As UInt32)
        If val = 0 Then
            buf(idx) = 48 ' '0'
            idx = idx + 1
            Exit Sub
        End If
        Dim hexDigits As Pointer To Byte = CPtr(Pointer To Byte, "0123456789ABCDEF")
        Dim tmp(16) As Byte
        Dim tIdx As Int32 = 0
        While val > 0
            tmp(tIdx) = hexDigits(CType(Byte, val And 15))
            val = val RShift 4
            tIdx = tIdx + 1
        Wend
        While tIdx > 0
            tIdx = tIdx - 1
            buf(idx) = tmp(tIdx)
            idx = idx + 1
        Wend
    End Sub

    ''
    ' @brief Draw a 5x7 ASCII glyph onto destination surface.
    ''
    Private Unsafe Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
        Dim rows(7) As Byte
        Dim valid As Boolean = True
        If ascii = 48 Then ' '0'
            rows(0) = 14: rows(1) = 17: rows(2) = 19: rows(3) = 21: rows(4) = 25: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 49 Then ' '1'
            rows(0) = 4: rows(1) = 12: rows(2) = 4: rows(3) = 4: rows(4) = 4: rows(5) = 4: rows(6) = 14
        ElseIf ascii = 50 Then ' '2'
            rows(0) = 14: rows(1) = 17: rows(2) = 1: rows(3) = 6: rows(4) = 8: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 51 Then ' '3'
            rows(0) = 30: rows(1) = 1: rows(2) = 1: rows(3) = 14: rows(4) = 1: rows(5) = 1: rows(6) = 30
        ElseIf ascii = 52 Then ' '4'
            rows(0) = 2: rows(1) = 6: rows(2) = 10: rows(3) = 18: rows(4) = 31: rows(5) = 2: rows(6) = 2
        ElseIf ascii = 53 Then ' '5'
            rows(0) = 31: rows(1) = 16: rows(2) = 30: rows(3) = 1: rows(4) = 1: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 54 Then ' '6'
            rows(0) = 14: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 55 Then ' '7'
            rows(0) = 31: rows(1) = 1: rows(2) = 2: rows(3) = 4: rows(4) = 8: rows(5) = 8: rows(6) = 8
        ElseIf ascii = 56 Then ' '8'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 14: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 57 Then ' '9'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 15: rows(4) = 1: rows(5) = 1: rows(6) = 14
        ElseIf ascii = 70 Then ' 'F'
            rows(0) = 31: rows(1) = 16: rows(2) = 30: rows(3) = 16: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 80 Then ' 'P'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 83 Then ' 'S'
            rows(0) = 15: rows(1) = 16: rows(2) = 16: rows(3) = 14: rows(4) = 1: rows(5) = 1: rows(6) = 30
        Else
            valid = False
        End If

        If Not valid Then Exit Sub

        Dim r As Int32 = 0
        While r < 7
            Dim b As Byte = rows(r)
            Dim c As Int32 = 0
            While c < 5
                Dim bitMask As Byte = CType(Byte, 16 RShift c)
                If (b And bitMask) <> 0 Then
                    FillRect surf, gx + c, gy + r, 1, 1, color
                End If
                c = c + 1
            Wend
            r = r + 1
        Wend
    End Sub

    ''
    ' @brief Render 5x7 FPS telemetry string ("<fps> FPS") onto badge surface.
    ''
    Private Unsafe Sub DrawFps(ByRef surf As Surface, ByVal startX As Int32, ByVal startY As Int32, ByVal fpsVal As UInt32, ByVal color As UInt32)
        FillRect surf, startX - 2, startY - 2, 44, 11, &HFF1B2028

        Dim d10 As Byte = CType(Byte, ((fpsVal / 10) Mod 10) + 48)
        Dim d1 As Byte = CType(Byte, (fpsVal Mod 10) + 48)
        DrawGlyph surf, startX, startY, d10, color
        DrawGlyph surf, startX + 6, startY, d1, color

        DrawGlyph surf, startX + 15, startY, 70, color ' 'F'
        DrawGlyph surf, startX + 22, startY, 80, color ' 'P'
        DrawGlyph surf, startX + 29, startY, 83, color ' 'S'
    End Sub

    ''
    ' @brief Main application entry point for PROS Display Driver Service.
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit code (0 for success).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DISP_SRV] ======================================================="
        ConsoleWriteLine "[DISP_SRV] PROS Display Driver Service Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DISP_SRV] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.display' (Kind: Device = 2, Caps: RWN = 7)
        Dim srvName(32) As Byte
        srvName(0) = 115 ' 's'
        srvName(1) = 114 ' 'r'
        srvName(2) = 118 ' 'v'
        srvName(3) = 46  ' '.'
        srvName(4) = 100 ' 'd'
        srvName(5) = 105 ' 'i'
        srvName(6) = 115 ' 's'
        srvName(7) = 112 ' 'p'
        srvName(8) = 108 ' 'l'
        srvName(9) = 97  ' 'a'
        srvName(10) = 121' 'y'
        srvName(11) = 0
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, @srvName(0), 7)
        ConsolePrintWithUInt "[DISP_SRV] Registered Node 'srv.display' -> Node #", srvNodeId, "\r\n"

        ' 3. Query Hardware Display Geometry
        Dim disp As DisplayInfo
        If GetDisplayInfo(disp) Then
            Dim resBuf(64) As Byte
            Dim rIdx As UInt32 = 0
            AppendStr "[DISP_SRV] Resolution: ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, disp.Width), @resBuf(0), rIdx
            AppendStr "x", @resBuf(0), rIdx
            AppendUInt CType(UInt64, disp.Height), @resBuf(0), rIdx
            AppendStr " @ ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, disp.Bpp), @resBuf(0), rIdx
            AppendStr " BPP", @resBuf(0), rIdx
            resBuf(rIdx) = 0
            ConsoleWriteLine @resBuf(0)
            ConsolePrintWithUInt "[DISP_SRV] Framebuffer Pitch: ", CType(UInt64, disp.Pitch), " bytes\r\n"
            Dim apBuf(64) As Byte
            Dim aIdx As UInt32 = 0
            AppendStr "[DISP_SRV] Physical Aperture: 0x", @apBuf(0), aIdx
            AppendHex disp.PhysAddr, @apBuf(0), aIdx
            apBuf(aIdx) = 0
            ConsoleWriteLine @apBuf(0)
        Else
            ConsoleWriteLine "[DISP_SRV] WARN: Could not query display information"
        End If

        ' 4. Allocate Compositor Command Queue (64 KB at 0x68000000)
        Dim shmId As UInt64 = ShmemCreate(65536, &H68000000)
        ConsolePrintWithUInt "[DISP_SRV] Compositor Command Queue allocated -> ShmID #", shmId, "\r\n"

        ' 5. Daemon event loop: service hardware display requests and yield CPU
        ConsoleWriteLine "[DISP_SRV] Display Driver Service online. Entering active daemon loop..."

        Do
            ProcessYield
        Loop

        user_main = 0
    End Function

End Module
