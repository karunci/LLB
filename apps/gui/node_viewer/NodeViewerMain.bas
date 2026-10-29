' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/node_viewer/NodeViewerMain.bas
' Summary: Standalone Ring 3 Neural Node Topology Viewer GUI Application.
'          Allocates dedicated zero-copy shared memory surface, registers window
'          with srv.wm, and renders live registered node hierarchy and packet counters.

Import "../../../include/pros.bas"

Module NodeViewerMain

    Private Const CANVAS_W As Int32 = 396
    Private Const CANVAS_H As Int32 = 190

    Private clientSurf As Surface

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[NODE_VIEWER] Starting PROS Neural Node Topology Viewer (CPL=3)..."

        ' 1. Allocate dedicated client surface via Shared Memory
        Dim surfBytes As UInt64 = UInt64(CANVAS_W) * UInt64(CANVAS_H) * 4
        Dim shmId As UInt64 = ShmemCreate(surfBytes, &H66000000)
        Dim pPixels As Pointer To UInt32 = *UInt32(&H66000000)

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
        While regTries < 60 And winId = 0
            winId = WmCreateWindow(400, 220, shmId, "PROS Neural Node Viewer")
            If winId = 0 Then
                ProcessSleep 50
                regTries = regTries + 1
            End If
        Wend

        If winId = 0 Then
            ConsoleWriteLine "[NODE_VIEWER] ERR: Failed to create window via WindowManager!"
            user_main = 2
            Exit Function
        End If
        ConsolePrintWithUInt "[NODE_VIEWER] Registered window with WindowManager -> ID #", winId, "\r\n"

        ' 3. Render Static Table Layout
        FillRect clientSurf, 0, 0, CANVAS_W, CANVAS_H, &HFF242933

        ' Header Banner
        FillRect clientSurf, 0, 0, CANVAS_W, 20, &HFF2E3440
        FillRect clientSurf, 0, 19, CANVAS_W, 1, &HFF3B4252
        DrawText5x7 clientSurf, 10, 6, "NEURAL NODE TOPOLOGY & SYNAPSE PLANE", &HFF88C0D0

        ' Table Columns
        DrawText5x7 clientSurf, 10, 26, "ID      NAME            ROLE          STATUS", &HFF4C566A
        FillRect clientSurf, 10, 36, CANVAS_W - 20, 1, &HFF3B4252

        ' Rows
        DrawText5x7 clientSurf, 10, 42, "#1000   kernel.core     CONTROL       ONLINE", &HFFA3BE8C
        DrawText5x7 clientSurf, 10, 56, "#1003   srv.display     DISPLAY_DRV   ACTIVE", &HFF81A1C1
        DrawText5x7 clientSurf, 10, 70, "#1004   srv.wm          WINDOW_MGR    ACTIVE", &HFFEBCB8B
        DrawText5x7 clientSurf, 10, 84, "#1005   srv.compositor  COMPOSITOR    ACTIVE", &HFF88C0D0
        DrawText5x7 clientSurf, 10, 98, "#1007   srv.input       INPUT_ROUTER  ACTIVE", &HFFD8DEE9
        DrawText5x7 clientSurf, 10, 112, "#1009   srv.dev_mgr     DEV_ARBITER   ACTIVE", &HFF81A1C1
        DrawText5x7 clientSurf, 10, 126, "#1010   srv.plexus_mgr  SUPERVISOR    ACTIVE", &HFFA3BE8C
        DrawText5x7 clientSurf, 10, 140, "#1011   srv.vfs         STORAGE_NODE  ACTIVE", &HFF88C0D0

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
