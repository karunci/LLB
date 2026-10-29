' Project Name: PROS (Personal Research Operating System)
' Filename: services/disp_srv/DispMain.bas
' Summary: Standalone Ring 3 Display Driver Service daemon.
'          Queries hardware display configuration, maps framebuffer aperture,
'          and exposes 'srv.display' device node to client applications.

Import "../../include/pros.bas"

Module DispServiceMain

    ''
    ' @brief Render 5x7 FPS telemetry string ("<fps> FPS") onto badge surface.
    ''
    Private Unsafe Sub DrawFps(ByRef surf As Surface, ByVal startX As Int32, ByVal startY As Int32, ByVal fpsVal As UInt32, ByVal color As UInt32)
        FillRect surf, startX - 2, startY - 2, 44, 11, &HFF1B2028

        Dim fpsBuf(16) As Byte
        Dim fIdx As UInt32 = 0
        AppendUInt fpsVal, @fpsBuf(0), fIdx
        AppendStr " FPS", @fpsBuf(0), fIdx
        fpsBuf(fIdx) = 0
        DrawText5x7 surf, startX, startY, @fpsBuf(0), color
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
        Dim srvName As String = "srv.display"
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, srvName, 7)
        ConsolePrintWithUInt "[DISP_SRV] Registered Node 'srv.display' -> Node #", srvNodeId, "\r\n"

        ' 3. Query Hardware Display Geometry
        Dim disp As DisplayInfo
        If GetDisplayInfo(disp) Then
            Dim resBuf(64) As Byte
            Dim rIdx As UInt32 = 0
            AppendStr "[DISP_SRV] Resolution: ", @resBuf(0), rIdx
            AppendUInt disp.Width, @resBuf(0), rIdx
            AppendStr "x", @resBuf(0), rIdx
            AppendUInt disp.Height, @resBuf(0), rIdx
            AppendStr " @ ", @resBuf(0), rIdx
            AppendUInt disp.Bpp, @resBuf(0), rIdx
            AppendStr " BPP", @resBuf(0), rIdx
            resBuf(rIdx) = 0
            ConsoleWriteLine @resBuf(0)
            ConsolePrintWithUInt "[DISP_SRV] Framebuffer Pitch: ", disp.Pitch, " bytes\r\n"
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
            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
