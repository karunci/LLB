' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: apps/gui/gl_demo/GlDemoMain.bas
' Summary: Standalone Ring 3 Software 3D OpenGL Rasterizer interactive demo.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders real-time rotating 3D Gouraud-shaded geometry at 60 FPS.

Import "../../../include/pros.bas"

Module GlDemoMain

    Private Const CANVAS_W As Int32 = 320
    Private Const CANVAS_H As Int32 = 240

    Private clientSurf As Surface

    ''
    ' @brief Main application entry point for 3D GL demo.
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[GL_DEMO] Starting PROS 3D OpenGL Rasterizer Demo (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H66000000)
        Dim pPixels As Pointer To UInt32 = *UInt32(&H66000000)

        ' Allocate dedicated depth buffer via Shared Memory
        Dim depthShmId As UInt64 = ShmemCreate(surfBytes, &H66200000)
        Dim pDepth As Pointer To Single = *Single(&H66200000)

        If shmId = 0 Or pPixels = 0 Or depthShmId = 0 Or pDepth = 0 Then
            ConsoleWriteLine "[GL_DEMO] ERR: Failed to create client shared memory buffers!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[GL_DEMO] Surface allocated (SHMID: ", shmId, " @ 0x66000000)\r\n"

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
            winId = WmCreateWindow(324, 270, shmId, "PROS 3D GL Demo")
            If winId = 0 Then
                ProcessSleep 50
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[GL_DEMO] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[GL_DEMO] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' 3. Initialize Software 3D OpenGL Rasterizer Pipeline
        GlInit CANVAS_W, CANVAS_H, pPixels, pDepth
        GlViewport 0, 0, CANVAS_W, CANVAS_H
        GlEnable GL_DEPTH_TEST
        GlDisable GL_CULL_FACE

        ' 4. Interactive 3D Render Loop (60 FPS Paced Presentation)
        Dim rotX As Single = 15.0
        Dim rotY As Single = 20.0
        Dim rotZ As Single = 0.0

        Do
            ' Clear frame buffers
            GlClearColor 0.09, 0.11, 0.15, 1.0 ' Deep Nord slate
            GlClearDepth 1.0
            GlClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT

            ' Setup Perspective Projection Matrix
            GlMatrixMode GL_PROJECTION
            GlLoadIdentity
            GluPerspective 50.0, (Single(CANVAS_W) / Single(CANVAS_H)), 0.1, 100.0

            ' Setup ModelView Matrix
            GlMatrixMode GL_MODELVIEW
            GlLoadIdentity
            GlTranslatef 0.0, 0.0, -3.2
            GlRotatef rotX, 1.0, 0.0, 0.0
            GlRotatef rotY, 0.0, 1.0, 0.0
            GlRotatef rotZ, 0.0, 0.0, 1.0

            ' Render 3D Gouraud-Shaded Cube
            ' Front Face (Red / Coral)
            GlBegin GL_QUADS
            GlColor4f 0.92, 0.34, 0.34, 1.0
            GlVertex3f -0.5, -0.5, 0.5
            GlColor4f 0.95, 0.55, 0.35, 1.0
            GlVertex3f 0.5, -0.5, 0.5
            GlColor4f 0.92, 0.34, 0.34, 1.0
            GlVertex3f 0.5, 0.5, 0.5
            GlColor4f 0.85, 0.25, 0.25, 1.0
            GlVertex3f -0.5, 0.5, 0.5
            GlEnd

            ' Back Face (Teal / Mint)
            GlBegin GL_QUADS
            GlColor4f 0.25, 0.75, 0.65, 1.0
            GlVertex3f -0.5, -0.5, -0.5
            GlColor4f 0.20, 0.65, 0.55, 1.0
            GlVertex3f -0.5, 0.5, -0.5
            GlColor4f 0.35, 0.85, 0.75, 1.0
            GlVertex3f 0.5, 0.5, -0.5
            GlColor4f 0.30, 0.80, 0.70, 1.0
            GlVertex3f 0.5, -0.5, -0.5
            GlEnd

            ' Top Face (Nord Ice Blue)
            GlBegin GL_QUADS
            GlColor4f 0.53, 0.75, 0.82, 1.0
            GlVertex3f -0.5, 0.5, -0.5
            GlColor4f 0.58, 0.80, 0.87, 1.0
            GlVertex3f -0.5, 0.5, 0.5
            GlColor4f 0.63, 0.85, 0.92, 1.0
            GlVertex3f 0.5, 0.5, 0.5
            GlColor4f 0.50, 0.70, 0.77, 1.0
            GlVertex3f 0.5, 0.5, -0.5
            GlEnd

            ' Bottom Face (Nord Gold)
            GlBegin GL_QUADS
            GlColor4f 0.92, 0.80, 0.55, 1.0
            GlVertex3f -0.5, -0.5, -0.5
            GlColor4f 0.95, 0.85, 0.60, 1.0
            GlVertex3f 0.5, -0.5, -0.5
            GlColor4f 0.88, 0.75, 0.50, 1.0
            GlVertex3f 0.5, -0.5, 0.5
            GlColor4f 0.85, 0.70, 0.45, 1.0
            GlVertex3f -0.5, -0.5, 0.5
            GlEnd

            ' Right Face (Nord Purple)
            GlBegin GL_QUADS
            GlColor4f 0.71, 0.56, 0.68, 1.0
            GlVertex3f 0.5, -0.5, -0.5
            GlColor4f 0.76, 0.61, 0.73, 1.0
            GlVertex3f 0.5, 0.5, -0.5
            GlColor4f 0.81, 0.66, 0.78, 1.0
            GlVertex3f 0.5, 0.5, 0.5
            GlColor4f 0.66, 0.51, 0.63, 1.0
            GlVertex3f 0.5, -0.5, 0.5
            GlEnd

            ' Left Face (Nord Emerald)
            GlBegin GL_QUADS
            GlColor4f 0.64, 0.75, 0.55, 1.0
            GlVertex3f -0.5, -0.5, -0.5
            GlColor4f 0.69, 0.80, 0.60, 1.0
            GlVertex3f -0.5, -0.5, 0.5
            GlColor4f 0.74, 0.85, 0.65, 1.0
            GlVertex3f -0.5, 0.5, 0.5
            GlColor4f 0.59, 0.70, 0.50, 1.0
            GlVertex3f -0.5, 0.5, -0.5
            GlEnd

            ' 2D Telemetry & HUD Overlay
            DrawText5x7 clientSurf, 10, 8, "PROS SOFTWARE 3D OPENGL", &HFFECEFF4
            DrawText5x7 clientSurf, 10, 20, "Z-BUFFER: 32-BIT | 60 FPS", &HFF88C0D0

            ' Advance rotation angles
            rotX = rotX + 1.2
            rotY = rotY + 1.8
            rotZ = rotZ + 0.6
            If rotX >= 360.0 Then rotX = rotX - 360.0
            If rotY >= 360.0 Then rotY = rotY - 360.0
            If rotZ >= 360.0 Then rotZ = rotZ - 360.0

            ' Signal dirty rectangle to Window Manager & Compositor
            WmSignalDirty winId, 0, 0, CANVAS_W, CANVAS_H

            ' Pace at ~60 FPS (16ms)
            ProcessSleep 16
        Loop

        user_main = 0
    End Function

End Module
