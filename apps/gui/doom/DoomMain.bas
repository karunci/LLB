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
    ' @brief Exported callback invoked from C DOOM sound module to play digital PCM sound effects.
    ''
    Public Unsafe Sub doom_platform_play_sound_cb(ByVal sampleRate As UInt32, ByVal numSamples As UInt32, _
                                                  ByVal pcmPtr As Pointer To Byte, ByVal channel As Int32, _
                                                  ByVal vol As Int32, ByVal sep As Int32)
        Dim volByte As Byte = Byte(vol And &H7F)
        Dim sepByte As Byte = Byte(sep And &HFF)
        AudioPlaySample sampleRate, 1, 8, pcmPtr, numSamples, volByte, sepByte
    End Sub

    ''
    ' @brief Exported callback invoked from C DOOM sound module to stop a sound channel.
    ''
    Public Unsafe Sub doom_platform_stop_sound_cb(ByVal channel As Int32)
        AudioStopChannel channel
    End Sub

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

            ' Poll keystrokes exclusively from the Window Manager event queue
            Dim inEvt As InputEvent
            While WmPollEvent(g_winId, inEvt)
                If inEvt.EventType = EVENT_KEY_DOWN Or inEvt.EventType = EVENT_KEY_UP Then
                    Dim isPress As Int32 = 0
                    If inEvt.EventType = EVENT_KEY_DOWN Then isPress = 1

                    Dim scancode As UInt32 = inEvt.Code
                    Dim isExt As Boolean = ((inEvt.Modifiers And 8) <> 0)
                    Dim doomKey As Byte = 0

                If isExt Then
                    ' Extended Navigation & Cursor Keys
                    If scancode = &H48 Then doomKey = &HAD     ' Up Arrow (KEY_UPARROW)
                    If scancode = &H50 Then doomKey = &HAF     ' Down Arrow (KEY_DOWNARROW)
                    If scancode = &H4B Then doomKey = &HAC     ' Left Arrow (KEY_LEFTARROW)
                    If scancode = &H4D Then doomKey = &HAE     ' Right Arrow (KEY_RIGHTARROW)
                    If scancode = &H1D Then doomKey = &HA3     ' Right Ctrl (KEY_FIRE)
                    If scancode = &H38 Then doomKey = &HA0     ' Right Alt (KEY_STRAFE_L)
                Else
                    If scancode = &H01 Then
                        doomKey = 27                           ' Escape (KEY_ESCAPE)
                    ElseIf scancode = &H1C Then
                        doomKey = 13                           ' Enter (KEY_ENTER)
                    ElseIf scancode = &H39 Then
                        doomKey = 32                           ' Space bar
                        DoomPushKey isPress, &HA2              ' Space bar also activates KEY_USE
                    ElseIf scancode = &H0E Then
                        doomKey = &H7F                         ' Backspace (KEY_BACKSPACE)
                    ElseIf scancode = &H0F Then
                        doomKey = 9                            ' Tab (KEY_TAB, automap)
                    ElseIf scancode = &H1D Then
                        doomKey = &HA3                         ' Left Ctrl (KEY_FIRE)
                    ElseIf scancode = &H2A Or scancode = &H36 Then
                        doomKey = &HB6                         ' Shift (KEY_RSHIFT, run)
                    ElseIf scancode = &H38 Then
                        doomKey = &HA0                         ' Left Alt (KEY_STRAFE_L)
                    ' WASD Movement
                    ElseIf scancode = &H11 Then
                        doomKey = &HAD                         ' 'W' -> Forward (KEY_UPARROW)
                    ElseIf scancode = &H1F Then
                        doomKey = &HAF                         ' 'S' -> Backward (KEY_DOWNARROW)
                    ElseIf scancode = &H1E Then
                        doomKey = &HAC                         ' 'A' -> Turn Left (KEY_LEFTARROW)
                    ElseIf scancode = &H20 Then
                        doomKey = &HAE                         ' 'D' -> Turn Right (KEY_RIGHTARROW)
                    ElseIf scancode = &H12 Then
                        doomKey = &HA2                         ' 'E' -> Use (KEY_USE)
                    ' Weapon selection numbers '1'..'7'
                    ElseIf scancode >= &H02 And scancode <= &H08 Then
                        doomKey = CType(Byte, 49 + (scancode - &H02))
                    Else
                        If inEvt.Ascii <> 0 Then
                            doomKey = CType(Byte, inEvt.Ascii)
                        End If
                    End If
                End If

                If doomKey <> 0 Then
                    DoomPushKey isPress, doomKey
                End If
                End If
            Wend

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
