' Project Name: Personal Research Operating System (PROS) / Low-Level Basic
' Filename: services/genesis/GenesisMain.bas
' Summary: Minimal Ring 3 Genesis PID 1 Root Init daemon.
'          Responsible solely for core initialization, boot ramdisk mapping,
'          spawning the decoupled Service Supervisor (PID 2), and adopting zombie processes.

Import "../../include/pros.bas"

Module GenesisMain

    ''
    ' @brief Locate a target .bax binary within the mapped USTAR ramdisk in userspace.
    ' @param ramdiskBase Virtual base address where initrd is mapped.
    ' @param targetFilename Simple filename to search for (e.g. "plexus_mgr.bax").
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
    Private Unsafe Function SpawnFromRamdisk(ByVal ramdiskBase As UInt64, ByVal procName As String, ByVal baxFilename As String) As UInt64
        Dim baxSize As UInt64 = 0
        Dim pBax As Pointer To Byte = FindBaxInRamdisk(ramdiskBase, baxFilename, baxSize)
        If pBax = 0 Or baxSize = 0 Then
            ConsoleWrite "[GENESIS] ERR: Failed to locate binary in ramdisk: "
            ConsoleWriteLine baxFilename
            SpawnFromRamdisk = 0
            Exit Function
        End If

        ' Allocate 128KB Shared Memory transfer buffer at 0x67000000
        Dim shmId As UInt64 = ShmemCreate(131072, &H67000000)
        If shmId = 0 Then
            ConsoleWriteLine "[GENESIS] ERR: Failed to allocate Shared Memory transfer window!"
            SpawnFromRamdisk = 0
            Exit Function
        End If

        ' Copy binary into transfer window
        Copy CPtr(Pointer To Byte, &H67000000), pBax, baxSize

        ' Invoke microkernel SYS_PROCESS_SPAWN (10)
        Dim childPid As UInt64 = SpawnBaxProcess(procName, shmId)

        ' Detach caller mapping
        ShmemDetach shmId

        SpawnFromRamdisk = childPid
    End Function

    ''
    ' @brief Main application entry point for PROS Genesis PID 1 Minimal Core Init.
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit code (0 for success).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[GENESIS] ======================================================="
        ConsoleWriteLine "[GENESIS] Personal Research Operating System - Minimal Core Init"
        ConsoleWriteLine "[GENESIS] System Init Online (PID 1, CPL=3, Mode: SRP Decoupled)"

        ' 1. Verify Process Identity
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[GENESIS] Active Root PID = ", pid, "\r\n"

        ' 2. Register Root System Node: 'sys.genesis'
        Dim rootNodeId As UInt64 = NodeRegister(NODE_KIND_SYSTEM, "sys.genesis", 7)
        ConsolePrintWithUInt "[GENESIS] Registered Root System Node 'sys.genesis' -> Node #", rootNodeId, "\r\n"

        ' 3. Map boot initrd ramdisk to userspace address 0x58000000
        Dim info As InitrdInfo
        If InitrdGetInfo(@info) Then
            ConsolePrintWithUInt "[GENESIS] Initrd ramdisk detected (Phys: 0x", info.PhysAddr, ""
            ConsolePrintWithUInt ", Size: ", info.SizeBytes, " bytes)\r\n"
            If InitrdMap(&H58000000) Then
                ConsoleWriteLine "[GENESIS] Boot ramdisk mapped to userland at 0x58000000"
            Else
                ConsoleWriteLine "[GENESIS] ERR: InitrdMap failed to map virtual address space!"
            End If
        Else
            ConsoleWriteLine "[GENESIS] WARN: InitrdGetInfo syscall failed!"
        End If

        ' 4. Spawn Decoupled Service Supervisor (PID 2)
        Dim plexusPid As UInt64 = SpawnFromRamdisk(&H58000000, "srv.plexus_mgr", "plexus_mgr.bax")
        If plexusPid <> 0 Then
            ConsolePrintWithUInt "[GENESIS] Summoned Service Supervisor 'srv.plexus_mgr' -> PID ", plexusPid, "\r\n"
        Else
            ConsoleWriteLine "[GENESIS] FATAL: Failed to spawn Service Supervisor! System cannot start services."
        End If

        ' 5. Minimal PID 1 Loop: Adopt Zombie Processes & Catch System Signals
        ConsoleWriteLine "[GENESIS] Handed off service orchestration to PID 2."
        ConsoleWriteLine "[GENESIS] Entering PID 1 Minimal Core Init (Zombie Adoption & Signal Loop)..."
        ConsoleWriteLine "[GENESIS] ======================================================="

        Do
            ' Adopt and reap terminated child / orphaned tasks
            Dim deadExitCode As UInt32 = 0
            Dim deadPid As UInt64 = 0
            Do
                deadPid = ReapProcess(deadExitCode)
                If deadPid > 0 Then
                    ConsolePrintWithUInt "[GENESIS] Reaped terminated process PID ", deadPid, ""
                    ConsolePrintWithUInt " (Exit Code: ", UInt64(deadExitCode), ")\r\n"
                End If
            Loop While deadPid > 0

            ProcessSleep 1000
        Loop

        user_main = 0
    End Function

End Module
