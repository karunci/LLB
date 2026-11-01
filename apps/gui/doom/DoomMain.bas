' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: apps/gui/doom/DoomMain.bas
' Summary: Standalone Ring 3 DOOM Generic GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and drives the DOOM generic engine via Synapse IPC input.

Import "../../../include/pros.bas"

Module DoomMain

    Private Const CANVAS_W As Int32 = 640
    Private Const CANVAS_H As Int32 = 400

    ' C DOOM Generic Platform Bridge Declarations
    Public Declare Sub DoomSetCanvas Lib "libdoomgeneric" Alias "doom_platform_set_canvas" (ByVal canvas As Pointer To UInt32, ByVal width As Int32, ByVal height As Int32)
    Public Declare Sub DoomPushKey Lib "libdoomgeneric" Alias "doom_platform_push_key" (ByVal pressed As Int32, ByVal key As Byte)
    Public Declare Function DoomStart Lib "libdoomgeneric" Alias "doom_platform_start" () As Int32
    Public Declare Sub DoomTick Lib "libdoomgeneric" Alias "doom_platform_tick" ()
    Public Declare Function DoomIsDirty Lib "libdoomgeneric" Alias "doom_platform_is_dirty" () As Int32
    Public Declare Sub DoomClearDirty Lib "libdoomgeneric" Alias "doom_platform_clear_dirty" ()

    Private g_winId As UInt32 = 0

    ''
    ' @brief Main entry point for standalone Ring 3 DOOM application.
    ' @param argc Number of command line arguments.
    ' @param argv Vector of argument string pointers.
    ' @return Exit code (0 on success).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DOOM] Starting Personal Research Operating System DOOM Engine (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory (640x400x4 bytes)
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H65000000)
        If shmId = 0 Then
            ConsoleWriteLine "[DOOM] ERR: Failed to create shared memory surface!"
            user_main = 1
            Exit Function
        End If

        Dim pPixels As Pointer To UInt32 = CPtr(Pointer To UInt32, &H65000000)
        ConsolePrintWithUInt "[DOOM] Canvas surface allocated (SHMID: ", shmId, " @ 0x65000000)\r\n"

        ' 2. Register managed window with Window Manager (srv.wm)
        Dim winId As UInt32 = 0
        Dim regTries As UInt32 = 0
        While regTries < 60 And winId = 0
            winId = WmCreateWindow(CANVAS_W + 4, CANVAS_H + 30, shmId, "PROS DOOM")
            If winId = 0 Then
                ProcessSleep 50
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[DOOM] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If

        g_winId = winId
        ConsolePrintWithUInt "[DOOM] Registered window with WindowManager -> ID #", winId, "\r\n"
        WmRequestFocus g_winId

        ' 3. Connect canvas surface to C DOOM Generic Platform Bridge
        DoomSetCanvas pPixels, CANVAS_W, CANVAS_H

        ' 4. Initialize DOOM engine core
        ConsoleWriteLine "[DOOM] Initializing DOOM Generic core engine..."
        Dim startRes As Int32 = DoomStart()
        If startRes <> 0 Then
            ConsoleWriteLine "[DOOM] ERR: DOOM engine startup failed!"
            user_main = 3
            Exit Function
        End If
        ConsoleWriteLine "[DOOM] Core engine online. Entering primary frame loop."
        WmSignalDirty g_winId, 0, 0, CANVAS_W, CANVAS_H

        ' 5. Primary Game Execution & Input Event Loop
        Do
            Dim isFocused As Boolean = WmIsFocused(g_winId)

            ' Poll keystrokes only when window holds input focus
            If isFocused Then
                Dim key As Byte = GetKey()
                While key <> 0
                    If key = 27 Then
                        ' Check for ANSI escape sequences (\x1B[...)
                        Dim b2 As Byte = GetKey()
                        Dim tries2 As UInt32 = 0
                        While b2 = 0 And tries2 < 200
                            b2 = GetKey()
                            tries2 = tries2 + 1
                        Wend

                        If b2 = 91 Then
                            Dim b3 As Byte = GetKey()
                            Dim tries3 As UInt32 = 0
                            While b3 = 0 And tries3 < 200
                                b3 = GetKey()
                                tries3 = tries3 + 1
                            Wend

                            If b3 = 65 Then     ' Up Arrow (\x1B[A)
                                DoomPushKey 1, &HAD
                            ElseIf b3 = 66 Then ' Down Arrow (\x1B[B)
                                DoomPushKey 1, &HAF
                            ElseIf b3 = 67 Then ' Right Arrow (\x1B[C)
                                DoomPushKey 1, &HAE
                            ElseIf b3 = 68 Then ' Left Arrow (\x1B[D)
                                DoomPushKey 1, &HAC
                            End If
                        Else
                            ' Escape key
                            DoomPushKey 1, 27
                        End If
                    ElseIf key = 10 Or key = 13 Then
                        ' Enter key -> KEY_ENTER (13)
                        DoomPushKey 1, 13
                    ElseIf key = 32 Then
                        ' Space bar -> ASCII 32 (menu) and KEY_USE (0xA2, open doors)
                        DoomPushKey 1, 32
                        DoomPushKey 1, &HA2
                    ElseIf key = &H1D Then
                        ' Left / Right Ctrl -> KEY_FIRE (0xA3)
                        DoomPushKey 1, &HA3
                    ElseIf key = 8 Or key = 127 Then
                        ' Backspace / Delete -> KEY_BACKSPACE (0x7F)
                        DoomPushKey 1, &H7F
                    ElseIf key = 9 Then
                        ' Tab -> Automap (KEY_TAB = 9)
                        DoomPushKey 1, 9
                    Else
                        ' Standard alphanumeric keys, WASD movement, and weapon selection
                        Dim doomKey As Byte = key
                        If doomKey >= 97 And doomKey <= 122 Then
                            doomKey = doomKey - 32 ' Uppercase for DOOM keycodes
                        End If

                        If doomKey = 87 Then        ' 'W' -> Up Arrow
                            DoomPushKey 1, &HAD
                        ElseIf doomKey = 83 Then    ' 'S' -> Down Arrow
                            DoomPushKey 1, &HAF
                        ElseIf doomKey = 65 Then    ' 'A' -> Left Arrow
                            DoomPushKey 1, &HAC
                        ElseIf doomKey = 68 Then    ' 'D' -> Right Arrow
                            DoomPushKey 1, &HAE
                        ElseIf doomKey = 69 Then    ' 'E' -> Use (Open doors)
                            DoomPushKey 1, &HA2
                        ElseIf doomKey = 70 Or doomKey = 88 Then ' 'F' or 'X' -> Fire
                            DoomPushKey 1, &HA3
                        Else
                            DoomPushKey 1, doomKey
                        End If
                    End If
                    key = GetKey()
                Wend
            Else
                ' Drain stale keys when unfocused
                While GetKey() <> 0
                Wend
            End If

            ' 6. Step game logic & render frame
            DoomTick

            ' 7. If frame buffer updated, signal dirty rectangle to Window Manager & Compositor
            If DoomIsDirty() <> 0 Then
                DoomClearDirty
                WmSignalDirty g_winId, 0, 0, CANVAS_W, CANVAS_H
            End If

            ' Pace loop cooperatively; DOOM generic core TryRunTics handles 35 FPS clocking
            ProcessSleep 2
        Loop

        user_main = 0
    End Function

End Module
