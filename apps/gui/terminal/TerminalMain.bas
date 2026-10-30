' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: apps/gui/terminal/TerminalMain.bas
' Summary: Standalone Ring 3 Interactive Terminal Shell GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and provides an 80x24 character grid, ANSI-compatible
'          scrolling, multi-line cursor traversing, and built-in diagnostic commands.

Import "../../../include/pros.bas"
Import "../../../include/Version.bas"

Module TerminalMain

    Private Const CANVAS_W As Int32 = 640
    Private Const CANVAS_H As Int32 = 400

    Private Const GRID_COLS As Int32 = 80
    Private Const GRID_ROWS As Int32 = 24
    Private Const TOTAL_CELLS As Int32 = 1920

    ' Nord & System Color Palette
    Private Const COLOR_TERM_BG   As UInt32 = &HFF1E222A
    Private Const COLOR_HEADER_BG As UInt32 = &HFF2E3440
    Private Const COLOR_HEADER_LN As UInt32 = &HFF3B4252
    Private Const COLOR_TEXT      As UInt32 = &HFFECEFF4
    Private Const COLOR_PROMPT    As UInt32 = &HFFEBCB8B
    Private Const COLOR_INFO      As UInt32 = &HFFA3BE8C
    Private Const COLOR_CYAN      As UInt32 = &HFF88C0D0
    Private Const COLOR_WARN      As UInt32 = &HFFBF616A
    Private Const COLOR_MUTED     As UInt32 = &HFF4C566A

    Private clientSurf As Surface
    Private g_winId As UInt32 = 0
    Private g_termNodeId As NodeId = 0

    ' Character Grid Buffers
    Private gridChar(2048) As Byte
    Private gridFg(2048) As UInt32
    Private cursorCol As Int32 = 0
    Private cursorRow As Int32 = 0

    ' Multi-Line Interactive Line Editor & Directory Navigation State
    Private promptStartRow As Int32 = 0
    Private promptLen As Int32 = 8
    Private cmdBuf(1024) As Byte
    Private cmdLen As UInt32 = 0
    Private cursorIdx As UInt32 = 0
    Private currentDirBuf(128) As Byte
    Private currentDir As String = "X:\\"

    ' Command Output Data Plane Buffers
    Private termLsBuf(65536) As Byte
    Private termCatBuf(65536) As Byte

    ''
    ' @brief Test equality of two null-terminated ASCII strings.
    ' @param s1 Pointer to first string.
    ' @param s2 Pointer to second string.
    ' @return True if strings are identical, False otherwise.
    ''
    Private Unsafe Function StrEquals(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Boolean
        If s1 = 0 Or s2 = 0 Then
            StrEquals = (s1 = s2)
            Exit Function
        End If
        Dim i As UInt32 = 0
        While s1(i) <> 0 And s2(i) <> 0
            If s1(i) <> s2(i) Then
                StrEquals = False
                Exit Function
            End If
            i = i + 1
        Wend
        StrEquals = (s1(i) = s2(i))
    End Function

    ''
    ' @brief Check if string starts with a specified prefix.
    ' @param s1 Pointer to target string.
    ' @param prefix Pointer to prefix string.
    ' @return True if target begins with prefix.
    ''
    Private Unsafe Function StrStartsWith(ByVal s1 As Pointer To Byte, ByVal prefix As Pointer To Byte) As Boolean
        If s1 = 0 Or prefix = 0 Then
            StrStartsWith = False
            Exit Function
        End If
        Dim i As UInt32 = 0
        While prefix(i) <> 0
            If s1(i) <> prefix(i) Then
                StrStartsWith = False
                Exit Function
            End If
            i = i + 1
        Wend
        StrStartsWith = True
    End Function

    ''
    ' @brief Render an individual 8x16 glyph cell onto client surface and signal dirty.
    ' @param col Grid column (0..79).
    ' @param row Grid row (0..23).
    ''
    Private Unsafe Sub RenderCell(ByVal col As Int32, ByVal row As Int32)
        If col < 0 Or col >= GRID_COLS Or row < 0 Or row >= GRID_ROWS Then Exit Sub
        Dim x As Int32 = col * 8
        Dim y As Int32 = 16 + (row * 16)
        Dim idx As Int32 = (row * GRID_COLS) + col
        Dim ch As Byte = gridChar(idx)
        Dim fg As UInt32 = gridFg(idx)

        FillRect clientSurf, x, y, 8, 16, COLOR_TERM_BG
        If ch > 32 And ch <= 126 Then
            DrawGlyph8x16 clientSurf, x, y, ch, fg
        End If
        WmSignalDirty g_winId, x, y, 8, 16
    End Sub

    ''
    ' @brief Draw or clear horizontal underline cursor at current cursor coordinates.
    ' @param visible True to draw cursor accent bar, False to erase.
    ''
    Private Unsafe Sub DrawCursor(ByVal visible As Boolean)
        If cursorCol < 0 Or cursorCol >= GRID_COLS Or cursorRow < 0 Or cursorRow >= GRID_ROWS Then Exit Sub
        Dim cx As Int32 = cursorCol * 8
        Dim cy As Int32 = 16 + (cursorRow * 16)
        If visible Then
            FillRect clientSurf, cx, cy + 14, 8, 2, COLOR_CYAN
        Else
            FillRect clientSurf, cx, cy + 14, 8, 2, COLOR_TERM_BG
        End If
        WmSignalDirty g_winId, cx, cy + 14, 8, 2
    End Sub

    ''
    ' @brief Scroll text grid up by one line, discarding top row and clearing bottom row.
    ''
    Private Unsafe Sub ScrollUp()
        Dim r As Int32 = 0
        While r < (GRID_ROWS - 1)
            Dim c As Int32 = 0
            While c < GRID_COLS
                Dim dst As Int32 = (r * GRID_COLS) + c
                Dim src As Int32 = ((r + 1) * GRID_COLS) + c
                gridChar(dst) = gridChar(src)
                gridFg(dst) = gridFg(src)
                c = c + 1
            Wend
            r = r + 1
        Wend

        ' Blank out bottom row
        Dim c2 As Int32 = 0
        While c2 < GRID_COLS
            Dim lastIdx As Int32 = ((GRID_ROWS - 1) * GRID_COLS) + c2
            gridChar(lastIdx) = 32
            gridFg(lastIdx) = COLOR_TEXT
            c2 = c2 + 1
        Wend

        ' Repaint full text area
        FillRect clientSurf, 0, 16, CANVAS_W, CANVAS_H - 16, COLOR_TERM_BG
        Dim r2 As Int32 = 0
        While r2 < GRID_ROWS
            Dim c3 As Int32 = 0
            While c3 < GRID_COLS
                Dim idx2 As Int32 = (r2 * GRID_COLS) + c3
                Dim ch2 As Byte = gridChar(idx2)
                If ch2 > 32 And ch2 <= 126 Then
                    DrawGlyph8x16 clientSurf, c3 * 8, 16 + (r2 * 16), ch2, gridFg(idx2)
                End If
                c3 = c3 + 1
            Wend
            r2 = r2 + 1
        Wend
        WmSignalDirty g_winId, 0, 16, CANVAS_W, CANVAS_H - 16
    End Sub

    ''
    ' @brief Reset entire grid buffer to blank spaces and redraw client banner.
    ''
    Private Unsafe Sub ClearGrid()
        Dim i As Int32 = 0
        While i < TOTAL_CELLS
            gridChar(i) = 32
            gridFg(i) = COLOR_TEXT
            i = i + 1
        Wend

        ' Status Bar Header
        FillRect clientSurf, 0, 0, CANVAS_W, 16, COLOR_HEADER_BG
        FillRect clientSurf, 0, 15, CANVAS_W, 1, COLOR_HEADER_LN
        DrawText5x7 clientSurf, 8, 4, "PROS TERMINAL CONSOLE  [TTY 1]  80x24  CPL=3", COLOR_CYAN

        ' Clear Body Area
        FillRect clientSurf, 0, 16, CANVAS_W, CANVAS_H - 16, COLOR_TERM_BG

        cursorCol = 0
        cursorRow = 0
        WmSignalDirty g_winId, 0, 0, CANVAS_W, CANVAS_H
    End Sub

    ''
    ' @brief Synchronize on-screen cursor position with cursorIdx and promptStartRow.
    ''
    Private Unsafe Sub UpdateCursorPos()
        Dim curOff As Int32 = promptLen + Int32(cursorIdx)
        cursorCol = curOff Mod GRID_COLS
        cursorRow = promptStartRow + (curOff / GRID_COLS)
    End Sub

    ''
    ' @brief Ensure that a command line of target length fits on screen, scrolling if necessary.
    ' @param targetLen Expected total length of the command line in characters.
    ''
    Private Unsafe Sub EnsureLineVisible(ByVal targetLen As UInt32)
        Dim maxOff As Int32 = promptLen + Int32(targetLen)
        Dim maxRow As Int32 = promptStartRow + (maxOff / GRID_COLS)
        While maxRow >= GRID_ROWS
            ScrollUp
            promptStartRow = promptStartRow - 1
            maxRow = promptStartRow + (maxOff / GRID_COLS)
        Wend
    End Sub

    ''
    ' @brief Re-render active multi-line command line starting after the prompt, clearing stale cells.
    ' @param clearOldLen Previous length to clear leftover cells from backspace/deletion.
    ''
    Private Unsafe Sub RedrawCommandLine(ByVal clearOldLen As UInt32)
        ' 1. Redraw all characters from 0 to cmdLen - 1
        Dim i As UInt32 = 0
        While i < cmdLen
            Dim off As Int32 = promptLen + Int32(i)
            Dim c As Int32 = off Mod GRID_COLS
            Dim r As Int32 = promptStartRow + (off / GRID_COLS)
            If r < GRID_ROWS Then
                Dim idx As Int32 = (r * GRID_COLS) + c
                gridChar(idx) = cmdBuf(i)
                gridFg(idx) = COLOR_TEXT
                RenderCell c, r
            End If
            i = i + 1
        Wend

        ' 2. Clear leftover characters up to clearOldLen
        While i < clearOldLen
            Dim offC As Int32 = promptLen + Int32(i)
            Dim cC As Int32 = offC Mod GRID_COLS
            Dim rC As Int32 = promptStartRow + (offC / GRID_COLS)
            If rC < GRID_ROWS Then
                Dim idxC As Int32 = (rC * GRID_COLS) + cC
                gridChar(idxC) = 32
                gridFg(idxC) = COLOR_TEXT
                RenderCell cC, rC
            End If
            i = i + 1
        Wend

        ' 3. Synchronize cursor position
        UpdateCursorPos
    End Sub

    ''
    ' @brief Emit single ASCII character to terminal grid with automatic cursor wrapping.
    ' @param ch ASCII character code.
    ' @param fgColor 32-bit ARGB text color.
    ''
    Public Unsafe Sub PutChar(ByVal ch As Byte, ByVal fgColor As UInt32)
        ' Carriage return (\r)
        If ch = 13 Then
            cursorCol = 0
            Exit Sub
        End If

        ' Newline (\n)
        If ch = 10 Then
            cursorCol = 0
            cursorRow = cursorRow + 1
            If cursorRow >= GRID_ROWS Then
                ScrollUp
                cursorRow = GRID_ROWS - 1
            End If
            Exit Sub
        End If

        ' Backspace (\b)
        If ch = 8 Then
            If cursorCol > 0 Then
                cursorCol = cursorCol - 1
                Dim bIdx As Int32 = (cursorRow * GRID_COLS) + cursorCol
                gridChar(bIdx) = 32
                RenderCell cursorCol, cursorRow
            ElseIf cursorRow > 0 Then
                ' Wrap back to end of previous line
                cursorRow = cursorRow - 1
                cursorCol = GRID_COLS - 1
                Dim bIdx2 As Int32 = (cursorRow * GRID_COLS) + cursorCol
                gridChar(bIdx2) = 32
                RenderCell cursorCol, cursorRow
            End If
            Exit Sub
        End If

        ' Tab (\t)
        If ch = 9 Then
            PutChar 32, fgColor
            While (cursorCol Mod 4) <> 0
                PutChar 32, fgColor
            Wend
            Exit Sub
        End If

        ' Printable character
        If ch >= 32 And ch <= 126 Then
            Dim cIdx As Int32 = (cursorRow * GRID_COLS) + cursorCol
            gridChar(cIdx) = ch
            gridFg(cIdx) = fgColor
            RenderCell cursorCol, cursorRow

            cursorCol = cursorCol + 1
            If cursorCol >= GRID_COLS Then
                cursorCol = 0
                cursorRow = cursorRow + 1
                If cursorRow >= GRID_ROWS Then
                    ScrollUp
                    cursorRow = GRID_ROWS - 1
                End If
            End If
        End If
    End Sub

    ''
    ' @brief Emit null-terminated ASCII string to terminal grid.
    ' @param strPtr Pointer to null-terminated string.
    ' @param fgColor 32-bit ARGB text color.
    ''
    Public Unsafe Sub PutString(ByVal strPtr As Pointer To Byte, ByVal fgColor As UInt32)
        If strPtr = 0 Then Exit Sub
        Dim i As UInt32 = 0
        While strPtr(i) <> 0
            PutChar strPtr(i), fgColor
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Emit null-terminated ASCII string followed by newline to terminal grid.
    ' @param strPtr Pointer to null-terminated string.
    ' @param fgColor 32-bit ARGB text color.
    ''
    Public Unsafe Sub PutLine(ByVal strPtr As Pointer To Byte, ByVal fgColor As UInt32)
        PutString strPtr, fgColor
        PutChar 10, fgColor
    End Sub

    ''
    ' @brief Print interactive shell prompt showing compact leaf directory or root with trailing slash.
    ''
    Private Unsafe Sub PrintPrompt()
        If cursorRow >= GRID_ROWS Then
            ScrollUp
            cursorRow = GRID_ROWS - 1
        End If
        cursorCol = 0
        promptStartRow = cursorRow

        Dim promptBuf(128) As Byte
        If StrEquals(currentDir, "X:\\") Or StrEquals(currentDir, "X:") Then
            ' Root directory ("X:\") -> "pros::\> "
            SprintF @promptBuf(0), 128, "pros::\\> "
        Else
            Dim leaf(64) As Byte
            PathGetLeaf currentDir, @leaf(0), 64
            SprintF @promptBuf(0), 128, "pros::%s\\> ", @leaf(0)
        End If

        PutString @promptBuf(0), COLOR_PROMPT
        promptLen = Int32(StrLen(@promptBuf(0)))

        cursorIdx = 0
        cmdLen = 0
        cmdBuf(0) = 0
    End Sub

    ''
    ' @brief Resolve relative or absolute path against base directory with canonicalization.
    ' @param baseDir Current working directory (e.g. "X:\" or "X:\System\").
    ' @param inPath Input path (e.g. "System", "..\Apps", "X:\Users").
    ' @param outBuf Destination buffer receiving resolved canonical path (e.g. "X:\System").
    ' @param maxLen Maximum byte size of destination buffer.
    ' @return Length of resolved path.
    ''
    Private Unsafe Function PathResolve(ByVal baseDir As Pointer To Byte, ByVal inPath As Pointer To Byte, ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
        If outBuf = 0 Or maxLen < 4 Then
            PathResolve = 0
            Exit Function
        End If

        Dim defBase As String = "X:\\"
        Dim bPtr As Pointer To Byte = baseDir
        If bPtr = 0 Or bPtr(0) = 0 Then bPtr = Pointer To Byte(defBase)

        If inPath = 0 Or inPath(0) = 0 Then
            StrCopy outBuf, maxLen, bPtr
            PathResolve = UInt32(StrLen(outBuf))
            Exit Function
        End If

        If inPath(0) = 126 And (inPath(1) = 0 Or inPath(1) = 32) Then
            outBuf(0) = 88 ' 'X'
            outBuf(1) = 58 ' ':'
            outBuf(2) = 92 ' '\'
            outBuf(3) = 0
            PathResolve = 3
            Exit Function
        End If

        Dim raw(256) As Byte
        Dim hasDrive As Boolean = False
        If (inPath(0) >= 65 And inPath(0) <= 90) Or (inPath(0) >= 97 And inPath(0) <= 122) Then
            If inPath(1) = 58 Then
                hasDrive = True
            End If
        End If

        If hasDrive Then
            StrCopy @raw(0), 256, inPath
        ElseIf inPath(0) = 92 Or inPath(0) = 47 Then
            raw(0) = bPtr(0)
            raw(1) = 58
            raw(2) = 0
            Dim rawLenRoot As UInt32 = 2
            Dim ri As UInt32 = 0
            While inPath(ri) <> 0 And rawLenRoot + 1 < 255
                raw(rawLenRoot) = inPath(ri)
                rawLenRoot = rawLenRoot + 1
                ri = ri + 1
            Wend
            raw(rawLenRoot) = 0
        Else
            StrCopy @raw(0), 256, bPtr
            Dim rawLen As UInt32 = UInt32(StrLen(@raw(0)))
            If rawLen > 0 And raw(rawLen - 1) <> 92 And raw(rawLen - 1) <> 47 Then
                If rawLen + 1 < 255 Then
                    raw(rawLen) = 92
                    rawLen = rawLen + 1
                    raw(rawLen) = 0
                End If
            End If
            Dim pi As UInt32 = 0
            While inPath(pi) <> 0 And rawLen + 1 < 255
                raw(rawLen) = inPath(pi)
                rawLen = rawLen + 1
                pi = pi + 1
            Wend
            raw(rawLen) = 0
        End If

        If raw(0) >= 97 And raw(0) <= 122 Then
            raw(0) = raw(0) - 32
        End If
        Dim si As UInt32 = 0
        While raw(si) <> 0
            If raw(si) = 47 Then raw(si) = 92
            si = si + 1
        Wend

        outBuf(0) = raw(0)
        outBuf(1) = 58
        outBuf(2) = 0
        Dim outLen As UInt32 = 2

        Dim rIdx As UInt32 = 2
        While raw(rIdx) <> 0
            While raw(rIdx) = 92
                rIdx = rIdx + 1
            Wend
            If raw(rIdx) = 0 Then Exit While

            Dim token(64) As Byte
            Dim tLen As UInt32 = 0
            While raw(rIdx) <> 0 And raw(rIdx) <> 92 And tLen + 1 < 64
                token(tLen) = raw(rIdx)
                tLen = tLen + 1
                rIdx = rIdx + 1
            Wend
            token(tLen) = 0

            If tLen = 0 Or (tLen = 1 And token(0) = 46) Then
                ' Current dir "." -> skip
            ElseIf tLen = 2 And token(0) = 46 And token(1) = 46 Then
                ' Parent ".." -> pop previous segment
                If outLen > 2 Then
                    Dim pIdx As Int32 = Int32(outLen) - 1
                    While pIdx >= 2 And outBuf(pIdx) <> 92
                        pIdx = pIdx - 1
                    Wend
                    If pIdx >= 2 Then
                        outLen = UInt32(pIdx)
                        outBuf(outLen) = 0
                    End If
                End If
            Else
                If outLen + tLen + 2 < maxLen Then
                    outBuf(outLen) = 92
                    outLen = outLen + 1
                    Dim ti As UInt32
                    For ti = 0 To tLen - 1
                        outBuf(outLen) = token(ti)
                        outLen = outLen + 1
                    Next ti
                    outBuf(outLen) = 0
                End If
            End If
        Wend

        If outLen <= 2 Then
            outBuf(2) = 92
            outBuf(3) = 0
            outLen = 3
        End If

        PathResolve = outLen
    End Function

    ''
    ' @brief Parse and execute built-in interactive shell command.
    ' @param cmd Null-terminated command line buffer.
    ''
    Private Unsafe Sub ExecuteCommand(ByVal cmd As Pointer To Byte)
        If cmd = 0 Or cmd(0) = 0 Then Exit Sub

        ' Tokenize into verb and arguments
        Dim verb(32) As Byte
        Dim vIdx As UInt32 = 0
        Dim cIdx As UInt32 = 0

        While cmd(cIdx) = 32
            cIdx = cIdx + 1
        Wend

        While cmd(cIdx) <> 0 And cmd(cIdx) <> 32 And vIdx + 1 < 32
            verb(vIdx) = cmd(cIdx)
            vIdx = vIdx + 1
            cIdx = cIdx + 1
        Wend
        verb(vIdx) = 0

        If vIdx = 0 Then Exit Sub

        While cmd(cIdx) = 32
            cIdx = cIdx + 1
        Wend
        Dim args As Pointer To Byte = cmd + cIdx

        ' 1. help command
        If StrEquals(@verb(0), "help") Then
            PutLine "PROS Shell Diagnostic Utilities:", COLOR_CYAN
            PutLine "  help      - Display this list of shell commands", COLOR_TEXT
            PutLine "  ver       - Display system version and architecture", COLOR_TEXT
            PutLine "  nodes     - Query active neural nodes", COLOR_TEXT
            PutLine "  ps        - List running system services & processes", COLOR_TEXT
            PutLine "  mem       - Query physical and shared memory info", COLOR_TEXT
            PutLine "  ls / dir  - List installed applications and files", COLOR_TEXT
            PutLine "  uptime    - Display elapsed system running time", COLOR_TEXT
            PutLine "  clear     - Clear terminal screen", COLOR_TEXT
            PutLine "  echo <str>- Print text argument to terminal", COLOR_TEXT
            Exit Sub
        End If

        ' 2. ver command
        If StrEquals(@verb(0), "ver") Then
            Dim verBuf(128) As Byte
            SprintF @verBuf(0), 128, "%s - %s", SYSTEM_NAME, SYSTEM_VERSION_TAG
            PutLine @verBuf(0), COLOR_INFO
            PutLine "Architecture: x86_64 Long Mode (SMP Cores: 4)", COLOR_TEXT
            PutLine "Kernel ABI  : Native Microkernel Syscall (SCE/STAR/LSTAR)", COLOR_TEXT
            Exit Sub
        End If

        ' 3. nodes command
        If StrEquals(@verb(0), "nodes") Then
            PutLine "Active Registered Neural Nodes:", COLOR_CYAN
            PutLine "  Node 1000: kernel.core     (Kind: System)  Caps: R/W/Notify", COLOR_TEXT
            PutLine "  Node 1001: srv.compositor  (Kind: System)  Caps: R/W/Notify", COLOR_TEXT
            PutLine "  Node 1002: srv.input       (Kind: Device)  Caps: R/W/Notify", COLOR_TEXT
            PutLine "  Node 1003: srv.wm          (Kind: System)  Caps: R/W/Notify", COLOR_TEXT
            PutLine "  Node 1004: srv.vfs         (Kind: Storage) Caps: R/W/Notify", COLOR_TEXT
            PutLine "  Node 1005: apps.terminal   (Kind: Client)  Caps: R/W/Notify", COLOR_TEXT
            Exit Sub
        End If

        ' 4. ps command
        If StrEquals(@verb(0), "ps") Then
            PutLine "Running System Tasks & Services:", COLOR_CYAN
            PutLine "  PID  NAME            STATE     RING  PRIORITY", COLOR_TEXT
            PutLine "  ---  --------------  --------  ----  --------", COLOR_TEXT
            PutLine "  1    srv.genesis     RUNNABLE  CPL=3 Normal", COLOR_TEXT
            PutLine "  2    srv.compositor  RUNNABLE  CPL=3 High", COLOR_TEXT
            PutLine "  3    srv.input       RUNNABLE  CPL=3 High", COLOR_TEXT
            PutLine "  4    srv.wm          RUNNABLE  CPL=3 Normal", COLOR_TEXT
            PutLine "  5    srv.vfs         RUNNABLE  CPL=3 Normal", COLOR_TEXT
            PutLine "  6    apps.sysmon     RUNNABLE  CPL=3 Low", COLOR_TEXT
            PutLine "  7    apps.terminal   RUNNING   CPL=3 Interactive", COLOR_TEXT
            Exit Sub
        End If

        ' 5. mem command
        If StrEquals(@verb(0), "mem") Then
            PutLine "Physical & Virtual Memory Status:", COLOR_CYAN
            PutLine "  Total Physical RAM: 1024 MB (Buddy Allocator Active)", COLOR_TEXT
            PutLine "  Lower-Half Space  : 0x000000000000 .. 0x00007FFFFFFFFFFF", COLOR_TEXT
            PutLine "  Terminal Surface  : 0x65000000 (SHM 1024000 Bytes)", COLOR_TEXT
            PutLine "  Framebuffer Apert : 1024x768x32 ARGB (Paced 60 FPS)", COLOR_TEXT
            Exit Sub
        End If

        ' 6. ls / dir command
        If StrEquals(@verb(0), "ls") Or StrEquals(@verb(0), "dir") Then
            Dim targetDir(128) As Byte
            If args(0) <> 0 Then
                PathResolve currentDir, args, @targetDir(0), 128
            Else
                StrCopy @targetDir(0), 128, currentDir
            End If

            Dim lsHdr(160) As Byte
            SprintF @lsHdr(0), 160, "Directory Listing of %s:", @targetDir(0)
            PutLine @lsHdr(0), COLOR_CYAN

            Dim fileCount As UInt32 = DirectoryList(@targetDir(0), @termLsBuf(0), 65536)
            If fileCount = 0 Then
                PutLine "  (empty directory or not found)", COLOR_WARN
            Else
                Dim eIdx As UInt32 = 0
                Dim ei As UInt32
                For ei = 0 To fileCount - 1
                    PutLine @termLsBuf(eIdx), COLOR_TEXT
                    While termLsBuf(eIdx) <> 0 And eIdx < 65530
                        eIdx = eIdx + 1
                    Wend
                    eIdx = eIdx + 1
                Next ei
            End If
            Exit Sub
        End If

        ' 7. cat command
        If StrEquals(@verb(0), "cat") Then
            If args(0) = 0 Then
                PutLine "cat: missing file argument", COLOR_WARN
                Exit Sub
            End If

            Dim catPath(128) As Byte
            PathResolve currentDir, args, @catPath(0), 128

            Dim readLen As UInt32 = ReadAllText(@catPath(0), @termCatBuf(0), 65535)
            If readLen > 0 Then
                termCatBuf(readLen) = 0
                PutLine @termCatBuf(0), COLOR_TEXT
            Else
                PutLine "cat: file not found or empty", COLOR_WARN
            End If
            Exit Sub
        End If

        ' 8. cd command
        If StrEquals(@verb(0), "cd") Then
            If args(0) = 0 Or StrEquals(args, "~") Then
                currentDir = "X:\\"
                Exit Sub
            End If

            Dim cdTarget(128) As Byte
            PathResolve currentDir, args, @cdTarget(0), 128

            If DirectoryExists(@cdTarget(0)) Then
                Dim tLen As UInt32 = UInt32(StrLen(@cdTarget(0)))
                If tLen > 3 And cdTarget(tLen - 1) <> 92 And tLen + 1 < 128 Then
                    cdTarget(tLen) = 92
                    cdTarget(tLen + 1) = 0
                End If
                StrCopy @currentDirBuf(0), 128, @cdTarget(0)
                currentDir = Pointer To Byte(@currentDirBuf(0))
                Exit Sub
            Else
                Dim cdErr(160) As Byte
                SprintF @cdErr(0), 160, "cd: directory not found: %s", args
                PutLine @cdErr(0), COLOR_WARN
                Exit Sub
            End If
        End If

        ' 9. pwd command
        If StrEquals(@verb(0), "pwd") Then
            PutLine currentDir, COLOR_INFO
            Exit Sub
        End If

        ' 10. uptime command
        If StrEquals(@verb(0), "uptime") Then
            Dim upMs As UInt64 = GetUptime()
            Dim upBuf(96) As Byte
            SprintF @upBuf(0), 96, "Uptime: %u seconds (%u ms)", upMs / 1000, upMs
            PutLine @upBuf(0), COLOR_INFO
            Exit Sub
        End If

        ' 11. ver command
        If StrEquals(@verb(0), "ver") Then
            PutLine "Personal Research Operating System [PRK-OS / PROS]", COLOR_INFO
            PutLine Sys.Version.SYSTEM_VERSION_TAG, COLOR_CYAN
            Exit Sub
        End If

        ' 12. clear command
        If StrEquals(@verb(0), "clear") Then
            ClearGrid
            Exit Sub
        End If

        ' 13. echo command
        If StrEquals(@verb(0), "echo") Then
            PutLine args, COLOR_TEXT
            Exit Sub
        End If

        ' Unknown command fallback
        Dim errBuf(160) As Byte
        SprintF @errBuf(0), 160, "pros: command not found: %s", @verb(0)
        PutLine @errBuf(0), COLOR_WARN
    End Sub

    ''
    ' @brief Main entry point for standalone Ring 3 Terminal application.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[TERMINAL] Starting PROS Terminal Console Shell (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H65000000)
        Dim pPixels As Pointer To UInt32 = *UInt32(&H65000000)

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
        While regTries < 60 And winId = 0
            winId = WmCreateWindow(644, 430, shmId, "PROS Terminal Console")
            If winId = 0 Then
                ProcessSleep 50
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[TERMINAL] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        g_winId = winId
        ConsolePrintWithUInt "[TERMINAL] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' 3. Register apps.terminal Neural Node for incoming TTY streams
        g_termNodeId = NodeRegister(NODE_KIND_CLIENT, "apps.terminal", CAP_SYNAPSE_READ Or CAP_SYNAPSE_WRITE)
        If g_termNodeId <> 0 Then
            ConsolePrintWithUInt "[TERMINAL] Registered Neural Node 'apps.terminal' -> Node #", g_termNodeId, "\r\n"
        End If

        ' 4. Initialize Terminal Grid and display boot banner
        ClearGrid
        PutLine "Personal Research Operating System - Interactive Terminal Shell", COLOR_CYAN
        PutLine "Type 'help' for available diagnostic commands.", COLOR_INFO
        PutChar 10, COLOR_TEXT
        PrintPrompt
        DrawCursor True

        ' 5. Event and Keystroke Polling Loop
        Dim blinkCounter As UInt32 = 0
        Dim cursorState As Boolean = True

        Do
            ' Poll microkernel keyboard ring buffer (SYS_GET_KEY)
            Dim key As Byte = GetKey()
            If key <> 0 Then
                If key = 27 Then
                    ' ANSI Escape Sequence (\x1B[...)
                    Dim b2 As Byte = GetKey()
                    Dim tries2 As UInt32 = 0
                    While b2 = 0 And tries2 < 200
                        b2 = GetKey()
                        tries2 = tries2 + 1
                    Wend

                    If b2 = 91 Then ' '['
                        Dim b3 As Byte = GetKey()
                        Dim tries3 As UInt32 = 0
                        While b3 = 0 And tries3 < 200
                            b3 = GetKey()
                            tries3 = tries3 + 1
                        Wend

                        If b3 = 68 Then ' Left Arrow (\x1B[D)
                            If cursorIdx > 0 Then
                                DrawCursor False
                                cursorIdx = cursorIdx - 1
                                UpdateCursorPos
                                DrawCursor True
                            End If
                        ElseIf b3 = 67 Then ' Right Arrow (\x1B[C)
                            If cursorIdx < cmdLen Then
                                DrawCursor False
                                cursorIdx = cursorIdx + 1
                                UpdateCursorPos
                                DrawCursor True
                            End If
                        ElseIf b3 = 72 Then ' Home (\x1B[H)
                            DrawCursor False
                            cursorIdx = 0
                            UpdateCursorPos
                            DrawCursor True
                        ElseIf b3 = 70 Then ' End (\x1B[F)
                            DrawCursor False
                            cursorIdx = cmdLen
                            UpdateCursorPos
                            DrawCursor True
                        End If
                    End If

                ElseIf key = 10 Or key = 13 Then
                    ' Enter key -> Submit command
                    DrawCursor False

                    ' Advance cursor past any wrapped lines of the current command
                    Dim endOff As Int32 = promptLen + Int32(cmdLen)
                    Dim endRow As Int32 = promptStartRow + (endOff / GRID_COLS)
                    cursorRow = endRow + 1
                    cursorCol = 0
                    While cursorRow >= GRID_ROWS
                        ScrollUp
                        cursorRow = cursorRow - 1
                    Wend

                    ExecuteCommand @cmdBuf(0)

                    PrintPrompt
                    DrawCursor True

                ElseIf key = 8 Then
                    ' Backspace key -> Delete character before cursor (with multi-line wrap-back)
                    If cursorIdx > 0 Then
                        DrawCursor False
                        Dim oldLenBk As UInt32 = cmdLen

                        ' Shift subsequent characters left
                        Dim bi As UInt32 = cursorIdx - 1
                        While bi < (cmdLen - 1)
                            cmdBuf(bi) = cmdBuf(bi + 1)
                            bi = bi + 1
                        Wend

                        cursorIdx = cursorIdx - 1
                        cmdLen = cmdLen - 1
                        cmdBuf(cmdLen) = 0

                        RedrawCommandLine oldLenBk
                        DrawCursor True
                    End If

                ElseIf key = 127 Then
                    ' Delete key -> Delete character directly under cursor
                    If cursorIdx < cmdLen Then
                        DrawCursor False
                        Dim oldLenDel As UInt32 = cmdLen

                        ' Shift characters after cursor left
                        Dim di As UInt32 = cursorIdx
                        While di < (cmdLen - 1)
                            cmdBuf(di) = cmdBuf(di + 1)
                            di = di + 1
                        Wend

                        cmdLen = cmdLen - 1
                        cmdBuf(cmdLen) = 0

                        RedrawCommandLine oldLenDel
                        DrawCursor True
                    End If

                ElseIf key >= 32 And key <= 126 Then
                    ' Printable ASCII character -> Insert at cursorIdx (with multi-line wrapping)
                    If cmdLen < 1000 Then
                        DrawCursor False

                        ' Ensure room on screen for line expansion
                        EnsureLineVisible cmdLen + 1

                        ' Shift subsequent characters right
                        Dim si As UInt32 = cmdLen
                        While si > cursorIdx
                            cmdBuf(si) = cmdBuf(si - 1)
                            si = si - 1
                        Wend

                        cmdBuf(cursorIdx) = key
                        cursorIdx = cursorIdx + 1
                        cmdLen = cmdLen + 1
                        cmdBuf(cmdLen) = 0

                        RedrawCommandLine cmdLen
                        DrawCursor True
                    End If
                End If
            End If

            ' Poll incoming Synapse TTY packets from other processes
            If g_termNodeId <> 0 Then
                Dim rxPkt As AxonPacket
                If SynapsePop(g_termNodeId, rxPkt) Then
                    If rxPkt.PacketType = MSG_TTY_WRITE Then
                        DrawCursor False
                        Dim p As UInt32 = 0
                        While p < rxPkt.PayloadLength
                            PutChar rxPkt.Payload(p), COLOR_TEXT
                            p = p + 1
                        Wend
                        DrawCursor True
                    End If
                End If
            End If

            ' 500ms Cursor Blink Management
            blinkCounter = blinkCounter + 20
            If blinkCounter >= 500 Then
                blinkCounter = 0
                cursorState = Not cursorState
                DrawCursor cursorState
            End If

            ProcessSleep 20
        Loop

        user_main = 0
    End Function

End Module
