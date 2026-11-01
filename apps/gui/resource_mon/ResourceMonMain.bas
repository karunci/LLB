' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: apps/gui/resource_mon/ResourceMonMain.bas
' Summary: Standalone Ring 3 Hardware Resource & Telemetry Monitor (CPUs, RAM, VRAM, GPU)
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders real-time CPU, RAM, VRAM, and GPU telemetry
'          queried directly from active kernel state via SYS_GET_SYSTEM_METRICS.

Import "../../../include/pros.bas"

Module ResourceMonMain

    Private Const CANVAS_W As Int32 = 356
    Private Const CANVAS_H As Int32 = 270

    Private clientSurf As Surface

    ''
    ' @brief Draw a horizontal resource metric bar with container frame and fill ratio.
    ' @param surf Target surface.
    ' @param x Left coordinate.
    ' @param y Top coordinate.
    ' @param w Total bar width.
    ' @param h Total bar height.
    ' @param percent Progress percentage (0..100).
    ' @param fillColor 32-bit ARGB bar color.
    ''
    Private Unsafe Sub DrawResourceBar(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal w As Int32, ByVal h As Int32, ByVal percent As UInt32, ByVal fillColor As UInt32)
        ' Draw container frame background
        FillRect surf, x, y, w, h, &HFF2E3440
        FillRect surf, x, y, w, 1, &HFF4C566A
        FillRect surf, x, (y + h) - 1, w, 1, &HFF4C566A

        ' Fill proportional bar
        Dim clampedPct As UInt32 = percent
        If clampedPct > 100 Then clampedPct = 100
        Dim fillW As Int32 = Int32((UInt64(w - 2) * UInt64(clampedPct)) / 100)
        If fillW > 0 Then
            FillRect surf, x + 1, y + 1, fillW, h - 2, fillColor
        End If
    End Sub

    ''
    ' @brief Main entry point for Resource Monitor application.
    ' @param argc Argument count.
    ' @param argv Argument pointers.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[RES_MON] Starting PROS Hardware Resource Monitor (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H67000000)
        Dim pPixels As Pointer To UInt32 = *UInt32(&H67000000)

        If shmId = 0 Or pPixels = 0 Then
            ConsoleWriteLine "[RES_MON] ERR: Failed to create client shared memory buffer!"
            user_main = 1
            Exit Function
        End If
        ConsolePrintWithUInt "[RES_MON] Surface allocated (SHMID: ", shmId, " @ 0x67000000)\r\n"

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
            winId = WmCreateWindow(CANVAS_W + 4, CANVAS_H + 28, shmId, "PROS Resource Monitor")
            If winId = 0 Then
                ProcessSleep 50
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[RES_MON] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[RES_MON] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' Signal initial full surface
        WmSignalDirty winId, 0, 0, CANVAS_W, CANVAS_H

        ' 3. Active Real Telemetry Update Loop (Updates every 500ms via SYS_GET_SYSTEM_METRICS)
        Dim metrics As SystemMetrics
        Do
            If GetSystemMetrics(metrics) Then
                ' Render Background
                FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF232731

                ' Card 1: CPU SMP Multi-Core Telemetry
                FillRect clientSurf, 8, 8, CANVAS_W - 16, 62, &HFF2E3440
                FillRect clientSurf, 8, 8, 4, 62, &HFF88C0D0

                Dim cpuHeaderBuf(64) As Byte
                Dim chIdx As UInt32 = 0
                AppendStr "CPU SMP LOAD & TOPOLOGY [", @cpuHeaderBuf(0), chIdx
                AppendUInt UInt64(metrics.CpuCount), @cpuHeaderBuf(0), chIdx
                AppendStr " CORES ONLINE]", @cpuHeaderBuf(0), chIdx
                cpuHeaderBuf(chIdx) = 0
                DrawText5x7 clientSurf, 18, 12, @cpuHeaderBuf(0), &HFFECEFF4

                DrawText5x7 clientSurf, 18, 26, "CORE 0 (BSP):", &HFFD8DEE9
                DrawResourceBar clientSurf, 95, 26, 75, 8, metrics.Cores(0).LoadPercent, &HFF88C0D0

                DrawText5x7 clientSurf, 18, 38, "CORE 1 (AP) :", &HFFD8DEE9
                DrawResourceBar clientSurf, 95, 38, 75, 8, metrics.Cores(1).LoadPercent, &HFF88C0D0

                DrawText5x7 clientSurf, 180, 26, "CORE 2 (AP):", &HFFD8DEE9
                DrawResourceBar clientSurf, 260, 26, 75, 8, metrics.Cores(2).LoadPercent, &HFF88C0D0

                DrawText5x7 clientSurf, 180, 38, "CORE 3 (AP):", &HFFD8DEE9
                DrawResourceBar clientSurf, 260, 38, 75, 8, metrics.Cores(3).LoadPercent, &HFF88C0D0

                DrawText5x7 clientSurf, 18, 52, "SCHED: PER-CPU RUNQUEUES (100 HZ LAPIC PACED)", &HFF81A1C1

                ' Card 2: System Physical Memory (RAM) Telemetry (Direct from Kernel PMM)
                FillRect clientSurf, 8, 74, CANVAS_W - 16, 60, &HFF2E3440
                FillRect clientSurf, 8, 74, 4, 60, &HFFA3BE8C
                DrawText5x7 clientSurf, 18, 78, "SYSTEM PHYSICAL MEMORY (RAM)", &HFFECEFF4

                Dim totRamMB As UInt64 = metrics.TotalRamBytes / 1048576
                Dim usedRamMB As UInt64 = metrics.UsedRamBytes / 1048576
                Dim freeRamMB As UInt64 = metrics.FreeRamBytes / 1048576
                Dim ramPct As UInt32 = 0
                If totRamMB > 0 Then ramPct = UInt32((usedRamMB * 100) / totRamMB)

                Dim ramBuf(64) As Byte
                Dim rbIdx As UInt32 = 0
                AppendStr "TOTAL: ", @ramBuf(0), rbIdx
                AppendUInt totRamMB, @ramBuf(0), rbIdx
                AppendStr " MB | USED: ", @ramBuf(0), rbIdx
                AppendUInt usedRamMB, @ramBuf(0), rbIdx
                AppendStr " MB | FREE: ", @ramBuf(0), rbIdx
                AppendUInt freeRamMB, @ramBuf(0), rbIdx
                AppendStr " MB", @ramBuf(0), rbIdx
                ramBuf(rbIdx) = 0
                DrawText5x7 clientSurf, 18, 92, @ramBuf(0), &HFF88C0D0
                DrawResourceBar clientSurf, 260, 78, 75, 8, ramPct, &HFFA3BE8C

                Dim buddyBuf(64) As Byte
                Dim bbIdx As UInt32 = 0
                AppendStr "BUDDY: ", @buddyBuf(0), bbIdx
                AppendUInt metrics.BuddyPoolBytes / 1048576, @buddyBuf(0), bbIdx
                AppendStr " MB POOL (0x04000000 - 0x08000000)", @buddyBuf(0), bbIdx
                buddyBuf(bbIdx) = 0
                DrawText5x7 clientSurf, 18, 104, @buddyBuf(0), &HFFD8DEE9

                Dim heapBuf(64) As Byte
                Dim hbIdx As UInt32 = 0
                AppendStr "KHEAP: ", @heapBuf(0), hbIdx
                AppendUInt metrics.HeapAllocBytes / 1048576, @heapBuf(0), hbIdx
                AppendStr " MB DYNAMIC ALIGNED (0x81000000)", @heapBuf(0), hbIdx
                heapBuf(hbIdx) = 0
                DrawText5x7 clientSurf, 18, 116, @heapBuf(0), &HFFEBCB8B

                ' Card 3: Video RAM (VRAM) & Aperture Telemetry
                FillRect clientSurf, 8, 138, CANVAS_W - 16, 60, &HFF2E3440
                FillRect clientSurf, 8, 138, 4, 60, &HFFEBCB8B
                DrawText5x7 clientSurf, 18, 142, "VIDEO MEMORY & APERTURE (VRAM)", &HFFECEFF4

                Dim vramTotMB As UInt64 = metrics.VramTotalBytes / 1048576
                If vramTotMB = 0 Then vramTotMB = (metrics.VramTotalBytes + 1048575) / 1048576
                Dim vramUsedMB As UInt64 = (metrics.VramUsedBytes + 1048575) / 1048576
                Dim vramPct As UInt32 = 0
                If metrics.VramTotalBytes > 0 Then
                    vramPct = UInt32((metrics.VramUsedBytes * 100) / metrics.VramTotalBytes)
                End If

                Dim vramBuf(64) As Byte
                Dim vbIdx As UInt32 = 0
                AppendStr "LFB APERTURE: ", @vramBuf(0), vbIdx
                AppendUInt UInt64(metrics.DisplayWidth), @vramBuf(0), vbIdx
                AppendStr "x", @vramBuf(0), vbIdx
                AppendUInt UInt64(metrics.DisplayHeight), @vramBuf(0), vbIdx
                AppendStr "x", @vramBuf(0), vbIdx
                AppendUInt UInt64(metrics.DisplayBpp), @vramBuf(0), vbIdx
                AppendStr " ARGB (", @vramBuf(0), vbIdx
                AppendUInt vramUsedMB, @vramBuf(0), vbIdx
                AppendStr " MB)", @vramBuf(0), vbIdx
                vramBuf(vbIdx) = 0
                DrawText5x7 clientSurf, 18, 156, @vramBuf(0), &HFF88C0D0
                DrawResourceBar clientSurf, 260, 142, 75, 8, vramPct, &HFFEBCB8B

                Dim vramCapBuf(64) As Byte
                Dim vcbIdx As UInt32 = 0
                AppendStr "TOTAL VRAM  : ", @vramCapBuf(0), vcbIdx
                AppendUInt vramTotMB, @vramCapBuf(0), vcbIdx
                AppendStr " MB PHYSICAL BAR APERTURE", @vramCapBuf(0), vcbIdx
                vramCapBuf(vcbIdx) = 0
                DrawText5x7 clientSurf, 18, 168, @vramCapBuf(0), &HFFD8DEE9
                DrawText5x7 clientSurf, 18, 180, "BACKBUFFER  : ZERO-COPY DOUBLE-BUFFERED RAM", &HFFA3BE8C

                ' Card 4: GPU & Presentation Pipeline Telemetry (PCI Discovery)
                FillRect clientSurf, 8, 202, CANVAS_W - 16, 60, &HFF2E3440
                FillRect clientSurf, 8, 202, 4, 60, &HFFB48EAD
                DrawText5x7 clientSurf, 18, 206, "GPU & DISPLAY CONTROLLER PIPELINE", &HFFECEFF4

                Dim gpuBuf(64) As Byte
                Dim gbIdx As UInt32 = 0
                If metrics.GpuDriverType = 1 Then
                    AppendStr "CONTROLLER  : VMware SVGA-II (0x15AD:0x0405)", @gpuBuf(0), gbIdx
                    gpuBuf(gbIdx) = 0
                    DrawText5x7 clientSurf, 18, 220, @gpuBuf(0), &HFF88C0D0

                    Dim fifoBuf(64) As Byte
                    Dim fb2Idx As UInt32 = 0
                    AppendStr "ACCEL BUS   : HARDWARE FIFO QUEUE (I/O 0x", @fifoBuf(0), fb2Idx
                    AppendHex UInt64(metrics.GpuBar0IoPort), @fifoBuf(0), fb2Idx
                    AppendStr ")", @fifoBuf(0), fb2Idx
                    fifoBuf(fb2Idx) = 0
                    DrawText5x7 clientSurf, 18, 232, @fifoBuf(0), &HFFD8DEE9
                Else
                    AppendStr "CONTROLLER  : PCI Display (0x", @gpuBuf(0), gbIdx
                    AppendHex UInt64(metrics.GpuVendorId), @gpuBuf(0), gbIdx
                    AppendStr ":0x", @gpuBuf(0), gbIdx
                    AppendHex UInt64(metrics.GpuDeviceId), @gpuBuf(0), gbIdx
                    AppendStr ")", @gpuBuf(0), gbIdx
                    gpuBuf(gbIdx) = 0
                    DrawText5x7 clientSurf, 18, 220, @gpuBuf(0), &HFF88C0D0
                    DrawText5x7 clientSurf, 18, 232, "ACCEL BUS   : FAST_BLIT32_NT STREAMING BURST", &HFFD8DEE9
                End If
                DrawText5x7 clientSurf, 18, 244, "PRESENTATION: 60 FPS PACED (16 MS DEADLINE)", &HFFA3BE8C

                ' Signal full surface update to Window Manager
                WmSignalDirty winId, 0, 0, CANVAS_W, CANVAS_H
            End If

            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module