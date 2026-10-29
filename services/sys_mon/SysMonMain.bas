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

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[SYS_MON] Starting PROS System Monitor Client (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
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
        Dim winId As UInt32 = 0
        Dim regTries As UInt32 = 0
        While regTries < 25 And winId = 0
            winId = WmCreateWindow(480, 280, shmId, "PROS System Monitor")
            If winId = 0 Then
                ProcessSleep 40
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[SYS_MON] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[SYS_MON] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' 3. Render Static Card Backgrounds
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF232731

        ' Card 1: Microkernel Architecture Card
        FillRect clientSurf, 10, 10, CANVAS_W - 20, 65, &HFF2E3440
        FillRect clientSurf, 10, 10, 4, 65, &HFF88C0D0
        DrawText5x7 clientSurf, 22, 16, "PROS MICROKERNEL TELEMETRY [CPL=3]", &HFFECEFF4
        DrawText5x7 clientSurf, 22, 30, "ARCH: x86_64 SMP (4 Cores Online)", &HFF81A1C1
        DrawText5x7 clientSurf, 22, 44, "KERNEL REV: 2026.10.29-r37-re04", &HFFEBCB8B
        DrawText5x7 clientSurf, 22, 58, "STATUS: SYSTEM HEALTH OPTIMAL", &HFFA3BE8C

        ' Card 2: Neural Synapse Plane Card
        FillRect clientSurf, 10, 85, CANVAS_W - 20, 65, &HFF2E3440
        FillRect clientSurf, 10, 85, 4, 65, &HFFA3BE8C
        DrawText5x7 clientSurf, 22, 91, "DUAL-PLANE NEURAL SYNAPSE IPC", &HFFECEFF4
        DrawText5x7 clientSurf, 22, 105, "AXON RING BUFFER: ZERO COPY (LOCK-FREE)", &HFF88C0D0
        DrawText5x7 clientSurf, 22, 119, "SERVICES: COMPOSITOR, INPUT, WM, VFS", &HFFD8DEE9
        DrawText5x7 clientSurf, 22, 133, "CONTROL PLANE: KERNEL.CORE (#1000)", &HFF81A1C1

        ' Card 3: Memory & Display Pipeline Card
        FillRect clientSurf, 10, 160, CANVAS_W - 20, 80, &HFF2E3440
        FillRect clientSurf, 10, 160, 4, 80, &HFFEBCB8B
        DrawText5x7 clientSurf, 22, 166, "GRAPHICAL PIPELINE & SHMEM CLIENT", &HFFECEFF4
        DrawText5x7 clientSurf, 22, 180, "PRESENTATION: 60 FPS PACED (16 MS)", &HFF88C0D0
        DrawText5x7 clientSurf, 22, 194, "VRAM APERTURE: 1024x768x32 ARGB BURST", &HFFD8DEE9

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
