' Project Name: Personal Research Operating System (PROS) / Low-Level Basic
' Filename: services/plexus_mgr/PlexusMgrMain.bas
' Summary: Standalone Ring 3 Decoupled Plexus Service Supervisor daemon (PID 2).
'          Oversees system service lifecycles, parses boot manifests, summons
'          daemons and drivers in staged dependency order, and performs auto-restart.

Import "../../include/pros.bas"

Module PlexusMgrMain

    Public Const PLEXUS_STATUS_STOPPED  As UInt32 = 0
    Public Const PLEXUS_STATUS_STARTING As UInt32 = 1
    Public Const PLEXUS_STATUS_RUNNING  As UInt32 = 2
    Public Const PLEXUS_STATUS_FAULTED  As UInt32 = 3

    Public Const PLEXUS_CMD_STATUS As UInt32 = 40
    Public Const PLEXUS_CMD_PING   As UInt32 = 41
    Public Const PLEXUS_RESP_OK    As UInt32 = 400

    <Packed>
    Structure ServiceItem
        Public Pid           As UInt64
        Public Name          As String
        Public BaxFile       As String
        Public Status        As UInt32
        Public LastHeartbeat As UInt64
    End Structure

    Private services(16) As ServiceItem
    Private serviceCount As UInt32

    ''
    ' @brief Locate a target .bax binary within the mapped USTAR ramdisk in userspace.
    ' @param ramdiskBase Virtual base address where initrd is mapped.
    ' @param targetFilename Simple filename to search for (e.g. "wm.bax").
    ' @param outSize ByRef variable receiving the file byte size.
    ' @return Pointer to file data in ramdisk, or 0 if not found.
    ''
    Private Unsafe Function FindBaxInRamdisk(ByVal ramdiskBase As UInt64, ByVal targetFilename As String, ByRef outSize As UInt64) As Pointer To Byte
        outSize = 0
        If ramdiskBase = 0 Or targetFilename = 0 Then
            FindBaxInRamdisk = 0
            Exit Function
        End If

        Dim currentAddr As UInt64 = ramdiskBase
        Do
            Dim pHeader As Pointer To Byte = CPtr(Pointer To Byte, currentAddr)
            If pHeader(0) = 0 Then Exit Do

            ' Parse octal file size at offset 124 in USTAR header
            Dim fileSize As UInt64 = 0
            Dim si As UInt32 = 0
            While si < 11
                Dim ch As Byte = pHeader(124 + si)
                If ch >= 48 And ch <= 55 Then
                    fileSize = (fileSize LShift 3) + UInt64(ch - 48)
                End If
                si = si + 1
            Wend

            ' Check if filename matches targetFilename suffix
            Dim pathLen As UInt32 = 0
            While pathLen < 100 And pHeader(pathLen) <> 0
                pathLen = pathLen + 1
            Wend

            Dim targetLen As UInt32 = 0
            Dim pTarget As Pointer To Byte = CPtr(Pointer To Byte, targetFilename)
            While targetLen < 100 And pTarget(targetLen) <> 0
                targetLen = targetLen + 1
            Wend

            If pathLen >= targetLen Then
                Dim matchOffset As UInt32 = pathLen - targetLen
                Dim matches As Boolean = True
                Dim mi As UInt32 = 0
                While mi < targetLen
                    If pHeader(matchOffset + mi) <> pTarget(mi) Then
                        matches = False
                        Exit While
                    End If
                    mi = mi + 1
                Wend

                If matches Then
                    If matchOffset = 0 Or pHeader(matchOffset - 1) = 47 Then ' 47 = '/'
                        outSize = fileSize
                        FindBaxInRamdisk = CPtr(Pointer To Byte, currentAddr + 512)
                        Exit Function
                    End If
                End If
            End If

            Dim blocks As UInt64 = (fileSize + 511) / 512
            currentAddr = currentAddr + ((blocks + 1) * 512)
        Loop

        FindBaxInRamdisk = 0
    End Function

    ''
    ' @brief Spawn a service binary from the mapped ramdisk via shared memory and SYS_PROCESS_SPAWN.
    ' @param ramdiskBase Base virtual address of mapped initrd.
    ' @param procName Canonical process and node name.
    ' @param baxFilename Name of binary file in ramdisk.
    ' @return Process ID of newly spawned process, or 0 on failure.
    ''
    Private Unsafe Function SpawnService(ByVal ramdiskBase As UInt64, ByVal procName As String, ByVal baxFilename As String) As UInt64
        Dim baxSize As UInt64 = 0
        Dim pBax As Pointer To Byte = FindBaxInRamdisk(ramdiskBase, baxFilename, baxSize)
        If pBax = 0 Or baxSize = 0 Then
            ConsoleWrite "[PLEXUS_MGR] ERR: Failed to locate binary in ramdisk: "
            ConsoleWriteLine baxFilename
            SpawnService = 0
            Exit Function
        End If

        ' Allocate 512KB Shared Memory transfer buffer at 0x67000000
        Dim shmId As UInt64 = ShmemCreate(524288, &H67000000)
        If shmId = 0 Then
            ConsoleWriteLine "[PLEXUS_MGR] ERR: Failed to allocate Shared Memory transfer window!"
            SpawnService = 0
            Exit Function
        End If

        ' Copy binary into transfer window
        Copy CPtr(Pointer To Byte, &H67000000), pBax, baxSize

        ' Invoke microkernel SYS_PROCESS_SPAWN (10)
        Dim childPid As UInt64 = SpawnBaxProcess(procName, shmId)

        ' Detach caller mapping
        ShmemDetach shmId

        If childPid <> 0 Then
            ConsoleWrite "[PLEXUS_MGR] Summoned '"
            ConsoleWrite procName
            ConsolePrintWithUInt "' -> PID ", childPid, "\r\n"

            ' Record into supervisor tracking table
            If serviceCount < 16 Then
                services(serviceCount).Pid = childPid
                services(serviceCount).Name = procName
                services(serviceCount).BaxFile = baxFilename
                services(serviceCount).Status = PLEXUS_STATUS_RUNNING
                services(serviceCount).LastHeartbeat = GetUptime()
                serviceCount = serviceCount + 1
            End If
        Else
            ConsoleWrite "[PLEXUS_MGR] ERR: Failed to spawn '"
            ConsoleWrite procName
            ConsoleWriteLine "'!"
        End If

        SpawnService = childPid
    End Function

    ''
    ' @brief Application entry point for plexus_mgr daemon (Ring 3 CPL=3, PID 2).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[PLEXUS_MGR] ======================================================="
        ConsoleWriteLine "[PLEXUS_MGR] Personal Research Operating System - Service Supervisor"
        ConsoleWriteLine "[PLEXUS_MGR] Plexus Service Supervisor Online (PID 2, CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[PLEXUS_MGR] Active Supervisor PID = ", myPid, "\r\n"

        ' 2. Register Plexus Manager Node
        Dim mgrNodeId As UInt64 = NodeRegister(NODE_KIND_SYSTEM, "srv.plexus_mgr", 7)
        If mgrNodeId <> 0 Then
            ConsolePrintWithUInt "[PLEXUS_MGR] Registered Node 'srv.plexus_mgr' -> Node #", mgrNodeId, "\r\n"
        Else
            ConsoleWriteLine "[PLEXUS_MGR] WARN: Failed to register 'srv.plexus_mgr' node!"
        End If

        ' 3. Map boot initrd ramdisk to userspace address 0x58000000
        Dim ramdiskBase As UInt64 = &H58000000
        Dim info As InitrdInfo
        If InitrdGetInfo(@info) Then
            If InitrdMap(ramdiskBase) Then
                ConsoleWriteLine "[PLEXUS_MGR] Boot ramdisk mapped to userland at 0x58000000"
            Else
                ConsoleWriteLine "[PLEXUS_MGR] ERR: Failed to map boot ramdisk!"
            End If
        End If

        ' 4. Staged Service Boot Orchestration
        serviceCount = 0

        ' Stage 1: Storage Subsystem (VFS and In-Memory RamFS)
        ConsoleWriteLine "[PLEXUS_MGR] Staging Stage 1: Storage Subsystem..."
        SpawnService ramdiskBase, "srv.vfs", "vfs_srv.bax"
        ProcessSleep 40
        SpawnService ramdiskBase, "fs.ramfs", "ramfs_srv.bax"
        ProcessSleep 40

        ' Stage 2: Hardware Device Arbiter
        ConsoleWriteLine "[PLEXUS_MGR] Staging Stage 2: Device Arbiter..."
        SpawnService ramdiskBase, "srv.dev_mgr", "dev_mgr.bax"
        ProcessSleep 40

        ' Stage 3: Hardware Drivers (Display & Input)
        ConsoleWriteLine "[PLEXUS_MGR] Staging Stage 3: Display & Input Drivers..."
        SpawnService ramdiskBase, "drv.disp.svga", "svga_drv.bax"
        ProcessSleep 40
        SpawnService ramdiskBase, "drv.disp.lfb", "lfb_drv.bax"
        ProcessSleep 40
        SpawnService ramdiskBase, "srv.display", "disp_srv.bax"
        ProcessSleep 50
        SpawnService ramdiskBase, "srv.input", "input_srv.bax"
        ProcessSleep 40

        ' Stage 4: Windowing & Presentation Engine
        ConsoleWriteLine "[PLEXUS_MGR] Staging Stage 4: Windowing Engine..."
        SpawnService ramdiskBase, "srv.compositor", "compositor.bax"
        ProcessSleep 50
        SpawnService ramdiskBase, "srv.wm", "wm.bax"
        ProcessSleep 50

        ' Stage 5: Desktop Applications & Core Utilities
        ConsoleWriteLine "[PLEXUS_MGR] Staging Stage 5: Desktop Applications..."
        SpawnService ramdiskBase, "apps.sys_mon", "sys_mon.bax"
        ProcessSleep 30
        SpawnService ramdiskBase, "apps.res_mon", "res_mon.bax"
        ProcessSleep 30
        SpawnService ramdiskBase, "apps.node_viewer", "node_viewer.bax"
        ProcessSleep 30
        SpawnService ramdiskBase, "apps.terminal", "terminal.bax"
        ProcessSleep 30
        SpawnService ramdiskBase, "apps.doom", "doom.bax"
        ProcessSleep 30
        SpawnService ramdiskBase, "user.test.app", "user_app.bax"

        ConsolePrintWithUInt "[PLEXUS_MGR] All services staged: ", serviceCount, " Supervised Services Active\r\n"
        ConsoleWriteLine "[PLEXUS_MGR] Service supervision online. Entering active heartbeat & auto-restart loop..."
        ConsoleWriteLine "[PLEXUS_MGR] ======================================================="

        ' 5. Active Supervisor & Auto-Restart Loop
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim pReqCount As UInt64 = 0

        Do
            ' A. Health Check & Auto-Restart of monitored services
            Dim sIdx As UInt32 = 0
            While sIdx < serviceCount
                Dim exitCode As UInt32 = 0
                Dim pollStatus As Int32 = ProcessPollExit(services(sIdx).Pid, exitCode)
                If pollStatus = 0 Then
                    ' Service exited unexpectedly! Re-summon replacement instance
                    ConsoleWrite "[PLEXUS_MGR] WARN: Service '"
                    ConsoleWrite services(sIdx).Name
                    ConsoleWriteLine "' terminated! Auto-restarting..."
                    services(sIdx).Status = PLEXUS_STATUS_FAULTED
                    Dim newPid As UInt64 = SpawnService(ramdiskBase, services(sIdx).Name, services(sIdx).BaxFile)
                    If newPid <> 0 Then
                        services(sIdx).Pid = newPid
                        services(sIdx).Status = PLEXUS_STATUS_RUNNING
                        services(sIdx).LastHeartbeat = GetUptime()
                    End If
                End If
                sIdx = sIdx + 1
            Wend

            ' B. Handle incoming telemetry / status queries over Synapse
            If SynapsePop(mgrNodeId, reqPkt) Then
                If reqPkt.PacketType = PLEXUS_CMD_STATUS Then
                    respPkt.Sequence = pReqCount
                    respPkt.SourceNode = mgrNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    respPkt.PacketType = PLEXUS_RESP_OK
                    respPkt.PayloadLength = 16

                    Dim replyChan As UInt64 = SynapseConnect(mgrNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                    pReqCount = pReqCount + 1
                End If
            End If

            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
