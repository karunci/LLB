' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/terminal/TerminalMain.bas
' Summary: Standalone Ring 3 Interactive Terminal Shell GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders terminal shell prompt and blinking block cursor.

Import "../../../include/pros.bas"

Module TerminalMain

    Private Const CANVAS_W As Int32 = 416
    Private Const CANVAS_H As Int32 = 210

    Private clientSurf As Surface

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[TERMINAL] Starting PROS Terminal Console Shell (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
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
        While regTries < 60 And winId = 0
            winId = WmCreateWindow(420, 240, shmId, "PROS Terminal Console")
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
        ConsolePrintWithUInt "[TERMINAL] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' 3. Render Static Terminal Layout
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF1E222A

        ' Status Bar Header
        FillRect clientSurf, 0, 0, CANVAS_W, 20, &HFF232731
        FillRect clientSurf, 0, 19, CANVAS_W, 1, &HFF3B4252
        DrawText5x7 clientSurf, 10, 6, "PROS TERMINAL CONSOLE  [TTY 1]  CPL=3", &HFF88C0D0

        ' Terminal Output History
        DrawText5x7 clientSurf, 12, 28, "PRK-LLB Interactive Diagnostic Shell v1.0", &HFFD8DEE9
        DrawText5x7 clientSurf, 12, 42, "Type 'help' for built-in diagnostic routines", &HFF4C566A
        
        DrawText5x7 clientSurf, 12, 62, "pros:\> sys.status", &HFFEBCB8B
        DrawText5x7 clientSurf, 12, 76, "  KERNEL  : PRK-LLB Microkernel SMP 4 Cores", &HFFA3BE8C
        DrawText5x7 clientSurf, 12, 90, "  PIPELINE: Zero-Copy Shared Memory Framebuffer", &HFF81A1C1
        DrawText5x7 clientSurf, 12, 104, "  SYNAPSE : Axon Inter-Process Router Active", &HFF88C0D0
        DrawText5x7 clientSurf, 12, 118, "  MEMORY  : Lower-Half Canonical Space Isolated", &HFFECEFF4

        DrawText5x7 clientSurf, 12, 138, "pros:\> ps -e", &HFFEBCB8B
        DrawText5x7 clientSurf, 12, 152, "  PID 1: genesis  PID 4: compositor  PID 7: wm", &HFFD8DEE9

        DrawText5x7 clientSurf, 12, 174, "pros:\> ", &HFFEBCB8B

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
