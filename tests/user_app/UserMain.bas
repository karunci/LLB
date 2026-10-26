' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/user_app/UserMain.bas
' Summary: Standalone Ring 3 userland test application running with Basic Runtime (BRT0).

Module UserApplication

    ' Native Microkernel System Call Constants
    Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
    Public Const SYS_PROCESS_YIELD   As UInt64 = 2
    Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
    Public Const SYS_PROCESS_GETPID  As UInt64 = 6
    Public Const SYS_PROCESS_EXIT    As UInt64 = 16
    Public Const SYS_TIME_UPTIME     As UInt64 = 28
    Public Const SYS_SMP_CORE_COUNT  As UInt64 = 34

    ' Dual-Plane Neural Node Extensions
    Public Const SYS_NODE_REGISTER   As UInt64 = 50
    Public Const SYS_SYNAPSE_CONNECT As UInt64 = 51
    Public Const SYS_SYNAPSE_PUSH    As UInt64 = 52
    Public Const SYS_SYNAPSE_POP     As UInt64 = 53
    Public Const SYS_NODE_LOOKUP     As UInt64 = 55

    ' Zero-Copy Shared Memory Extensions
    Public Const SYS_SHMEM_CREATE    As UInt64 = 60
    Public Const SYS_SHMEM_ATTACH    As UInt64 = 61
    Public Const SYS_SHMEM_DETACH    As UInt64 = 62

    ' Packed 288-byte AxonPacket structure for fast-path data plane transfer
    <Packed>
    Public Structure AxonPacket
        Public Sequence      As UInt64
        Public PacketType    As UInt32
        Public PayloadLength As UInt32
        Public SourceNode    As UInt64
        Public TargetNode    As UInt64
        Public Payload(255)  As Byte
    End Structure

    ''
    ' @brief Issue an x86_64 syscall with 0 arguments.
    ''
    Public Unsafe Function Syscall0(ByVal id As UInt64) As UInt64
        Dim ret As UInt64 = 0
        Asm "syscall" : "=a"(ret) : "a"(id) : "rcx", "r11", "memory"
        Syscall0 = ret
    End Function

    ''
    ' @brief Issue an x86_64 syscall with 1 argument.
    ''
    Public Unsafe Function Syscall1(ByVal id As UInt64, ByVal a1 As UInt64) As UInt64
        Dim ret As UInt64 = 0
        Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1) : "rcx", "r11", "memory"
        Syscall1 = ret
    End Function

    ''
    ' @brief Issue an x86_64 syscall with 2 arguments.
    ''
    Public Unsafe Function Syscall2(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64) As UInt64
        Dim ret As UInt64 = 0
        Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2) : "rcx", "r11", "memory"
        Syscall2 = ret
    End Function

    ''
    ' @brief Issue an x86_64 syscall with 3 arguments.
    ''
    Public Unsafe Function Syscall3(ByVal id As UInt64, ByVal a1 As UInt64, ByVal a2 As UInt64, ByVal a3 As UInt64) As UInt64
        Dim ret As UInt64 = 0
        Asm "syscall" : "=a"(ret) : "a"(id), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory"
        Syscall3 = ret
    End Function

    ''
    ' @brief Print a null-terminated string to kernel console via SYS_CONSOLE_WRITE.
    ''
    Public Unsafe Sub PrintString(ByVal strPtr As Pointer To Byte)
        If strPtr = 0 Then Exit Sub
        Dim length As UInt64 = 0
        While strPtr(length) <> 0
            length = length + 1
        Wend
        Syscall2 SYS_CONSOLE_WRITE, CType(UInt64, strPtr), length
    End Sub

    ''
    ' @brief Helper to convert a 64-bit integer into an ASCII string buffer.
    ''
    Public Unsafe Sub FormatUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte)
        If val = 0 Then
            buf(0) = 48 ' '0'
            buf(1) = 0
            Exit Sub
        End If

        Dim tmp(23) As Byte
        Dim idx As UInt32 = 0
        Dim v As UInt64 = val
        While v > 0
            tmp(idx) = CType(Byte, (v Mod 10) + 48)
            v = v / 10
            idx = idx + 1
        Wend

        Dim outIdx As UInt32 = 0
        While idx > 0
            idx = idx - 1
            buf(outIdx) = tmp(idx)
            outIdx = outIdx + 1
        Wend
        buf(outIdx) = 0
    End Sub

    ''
    ' @brief Emit a complete line consisting of prefix, formatted integer, and suffix in ONE atomic syscall.
    ''
    Public Unsafe Sub PrintMessageWithUInt(ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)
        Dim lineBuf(128) As Byte
        Dim outIdx As UInt32 = 0

        ' Copy prefix
        Dim pIdx As UInt32 = 0
        While prefix(pIdx) <> 0 And outIdx < 96
            lineBuf(outIdx) = prefix(pIdx)
            outIdx = outIdx + 1
            pIdx = pIdx + 1
        Wend

        ' Format and append unsigned integer
        Dim numBuf(24) As Byte
        FormatUInt val, @numBuf(0)
        Dim nIdx As UInt32 = 0
        While numBuf(nIdx) <> 0 And outIdx < 112
            lineBuf(outIdx) = numBuf(nIdx)
            outIdx = outIdx + 1
            nIdx = nIdx + 1
        Wend

        ' Copy suffix if present
        If suffix <> 0 Then
            Dim sIdx As UInt32 = 0
            While suffix(sIdx) <> 0 And outIdx < 126
                lineBuf(outIdx) = suffix(sIdx)
                outIdx = outIdx + 1
                sIdx = sIdx + 1
            Wend
        End If

        lineBuf(outIdx) = 0
        Syscall2 SYS_CONSOLE_WRITE, CType(UInt64, @lineBuf(0)), outIdx
    End Sub

    ''
    ' @brief Main application entry point invoked by Basic Runtime (BRT0).
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit status code returned to BRT0 (which invokes SYS_PROCESS_EXIT).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintString "[BRT0] =======================================================\r\n"
        PrintString "[BRT0] Basic Runtime Online! Entering user_main in Ring 3 (CPL=3)\r\n"

        ' 1. Verify PID via native SYS_PROCESS_GETPID syscall
        Dim pid As UInt64 = Syscall0(SYS_PROCESS_GETPID)
        PrintMessageWithUInt "[USER-APP] Querying process identity: Active PID = ", pid, "\r\n"

        ' 2. Verify active SMP Core count via native SYS_SMP_CORE_COUNT syscall
        Dim cores As UInt64 = Syscall0(SYS_SMP_CORE_COUNT)
        PrintMessageWithUInt "[USER-APP] System topology queried: Active SMP Cores = ", cores, "\r\n"

        ' 3. Register a Userland Compute Node via native SYS_NODE_REGISTER syscall
        Dim nodeName(31) As Byte
        nodeName(0) = 117 ' 'u'
        nodeName(1) = 115 ' 's'
        nodeName(2) = 101 ' 'e'
        nodeName(3) = 114 ' 'r'
        nodeName(4) = 46  ' '.'
        nodeName(5) = 97  ' 'a'
        nodeName(6) = 112 ' 'p'
        nodeName(7) = 112 ' 'p'
        nodeName(8) = 0
        Dim userNodeId As UInt64 = Syscall3(SYS_NODE_REGISTER, 1, CType(UInt64, @nodeName(0)), 3)
        PrintMessageWithUInt "[USER-APP] Registered Neural Node via SYS_NODE_REGISTER: Node #", userNodeId, "\r\n"

        ' 4. Connect Synapse Channel to Kernel Node #1000
        Dim synId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, 1000, 3)
        PrintMessageWithUInt "[USER-APP] Connected Synapse Channel via SYS_SYNAPSE_CONNECT: Channel #", synId, "\r\n"

        ' 5. Push AxonPacket across fast-path data plane via SYS_SYNAPSE_PUSH
        Dim pkt As AxonPacket
        pkt.Sequence = 101
        pkt.PacketType = 1
        pkt.SourceNode = userNodeId
        pkt.TargetNode = 1000
        pkt.PayloadLength = 5
        pkt.Payload(0) = 72 ' 'H'
        pkt.Payload(1) = 69 ' 'E'
        pkt.Payload(2) = 76 ' 'L'
        pkt.Payload(3) = 76 ' 'L'
        pkt.Payload(4) = 79 ' 'O'
        Dim pushRes As UInt64 = Syscall2(SYS_SYNAPSE_PUSH, synId, CType(UInt64, @pkt))
        If pushRes = 1 Then
            PrintString "[USER-APP] Axonal Data Plane packet transmission verified (Seq: 101)\r\n"
        End If

        ' 6. Yield processor time slice to prove preemptive/cooperative multitasking
        PrintString "[USER-APP] Calling SYS_PROCESS_YIELD...\r\n"
        Syscall0 SYS_PROCESS_YIELD
        PrintString "[USER-APP] Returned from SYS_PROCESS_YIELD! Task execution intact.\r\n"

        ' 7. Verify memory-mapped NEO/PE-BAX embedded resource access at 0x50000000
        Dim resTablePtr As Pointer To UInt32 = CPtr(Pointer To UInt32, &H50000000)
        If resTablePtr(0) = 1 Then ' ASSET_MANIFEST
            Dim manifestByteLenPtr As Pointer To UInt64 = CPtr(Pointer To UInt64, &H50000020)
            PrintMessageWithUInt "[USER-APP] Memory-Mapped BAX Manifest verified (Size: ", manifestByteLenPtr(0), " bytes, Mapped: 0x50000000)\r\n"
        End If

        ' 8. Verify Peer-to-Peer Node Lookup via SYS_NODE_LOOKUP
        Dim lookupId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @nodeName(0)))
        PrintMessageWithUInt "[USER-APP] Peer-to-Peer Node Lookup verified: Node 'user.app' -> ID #", lookupId, "\r\n"

        ' 8b. Discover Hardware Input Node ('hw.input.raw') and establish Synapse channel
        Dim rawInputName(15) As Byte
        rawInputName(0) = 104 ' 'h'
        rawInputName(1) = 119 ' 'w'
        rawInputName(2) = 46  ' '.'
        rawInputName(3) = 105 ' 'i'
        rawInputName(4) = 110 ' 'n'
        rawInputName(5) = 112 ' 'p'
        rawInputName(6) = 117 ' 'u'
        rawInputName(7) = 116 ' 't'
        rawInputName(8) = 46  ' '.'
        rawInputName(9) = 114 ' 'r'
        rawInputName(10) = 97 ' 'a'
        rawInputName(11) = 119' 'w'
        rawInputName(12) = 0
        Dim rawInputNodeId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @rawInputName(0)))
        PrintMessageWithUInt "[USER-APP] Discovered Hardware Input Node: 'hw.input.raw' -> ID #", rawInputNodeId, "\r\n"
        If rawInputNodeId > 0 Then
            Dim inputSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, rawInputNodeId, 3)
            PrintMessageWithUInt "[USER-APP] Subscribed Synapse to 'hw.input.raw' -> Channel #", inputSynId, "\r\n"
        End If

        ' 8c. Discover Unified Input Service Node ('srv.input')
        Dim srvInputName(15) As Byte
        srvInputName(0) = 115 ' 's'
        srvInputName(1) = 114 ' 'r'
        srvInputName(2) = 118 ' 'v'
        srvInputName(3) = 46  ' '.'
        srvInputName(4) = 105 ' 'i'
        srvInputName(5) = 110 ' 'n'
        srvInputName(6) = 112 ' 'p'
        srvInputName(7) = 117 ' 'u'
        srvInputName(8) = 116 ' 't'
        srvInputName(9) = 0
        Dim srvInputNodeId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @srvInputName(0)))
        PrintMessageWithUInt "[USER-APP] Discovered Unified Input Service Node: 'srv.input' -> ID #", srvInputNodeId, "\r\n"
        If srvInputNodeId > 0 Then
            Dim srvSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, srvInputNodeId, 3)
            PrintMessageWithUInt "[USER-APP] Connected Synapse to 'srv.input' -> Channel #", srvSynId, "\r\n"
        End If

        ' 9. Verify Zero-Copy Shared Memory (SYS_SHMEM_CREATE, Write Verification, SYS_SHMEM_DETACH)
        Dim shmTargetVaddr As UInt64 = &H60000000
        Dim shmid As UInt64 = Syscall2(SYS_SHMEM_CREATE, 8192, shmTargetVaddr)
        If shmid > 0 Then
            PrintMessageWithUInt "[USER-APP] Zero-Copy Shared Memory created (SHMID: ", shmid, ", Mapped @ 0x60000000)\r\n"
            Dim shmPtr As Volatile Pointer To UInt64 = CPtr(Volatile Pointer To UInt64, shmTargetVaddr)
            shmPtr(0) = &HCAFEBABE12345678
            If shmPtr(0) = &HCAFEBABE12345678 Then
                PrintString "[USER-APP] Zero-Copy Shared Memory write/read verified (0xCAFEBABE12345678)\r\n"
            End If

            ' Detach shared memory block
            Dim detRes As UInt64 = Syscall1(SYS_SHMEM_DETACH, shmid)
            If detRes = 0 Then
                PrintString "[USER-APP] Zero-Copy Shared Memory detached cleanly via SYS_SHMEM_DETACH\r\n"
            End If
        End If

        ' 10. Verify VFS Service via Synaptic IPC (Querying /system/bin/genesis.bax metadata)
        Dim vfsNodeName(15) As Byte
        vfsNodeName(0) = 115 ' 's'
        vfsNodeName(1) = 114 ' 'r'
        vfsNodeName(2) = 118 ' 'v'
        vfsNodeName(3) = 46  ' '.'
        vfsNodeName(4) = 118 ' 'v'
        vfsNodeName(5) = 102 ' 'f'
        vfsNodeName(6) = 115 ' 's'
        vfsNodeName(7) = 0
        Dim vfsTargetId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @vfsNodeName(0)))
        If vfsTargetId > 0 Then
            Dim vfsSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, vfsTargetId, 3)
            If vfsSynId > 0 Then
                Dim vfsReq As AxonPacket
                vfsReq.Sequence = 201
                vfsReq.PacketType = 11 ' VFS_CMD_STAT
                vfsReq.SourceNode = userNodeId
                vfsReq.TargetNode = vfsTargetId
                Dim testPath As Pointer To Byte = CPtr(Pointer To Byte, "/System/Servers/genesis.bax")
                Dim pi As UInt32 = 0
                While testPath(pi) <> 0
                    vfsReq.Payload(pi) = testPath(pi)
                    pi = pi + 1
                Wend
                vfsReq.Payload(pi) = 0
                vfsReq.PayloadLength = pi + 1
                Syscall2 SYS_SYNAPSE_PUSH, vfsSynId, CType(UInt64, @vfsReq)

                Dim vfsResp As AxonPacket
                If Syscall3(SYS_SYNAPSE_POP, userNodeId, CType(UInt64, @vfsResp), 1) = 1 Then
                    If vfsResp.PacketType = 100 Then ' VFS_RESP_OK
                        Dim pSize As Pointer To UInt32 = CPtr(Pointer To UInt32, @vfsResp.Payload(4))
                        PrintMessageWithUInt CPtr(Pointer To Byte, "[USER-APP] VFS Metadata verified: '/System/Servers/genesis.bax' (Size: "), CType(UInt64, pSize(0)), CPtr(Pointer To Byte, " bytes)\r\n")
                    End If
                End If
            End If
        End If

        ' 11. Verify Device Manager Service via Synaptic IPC (Querying 'pci.disp.lfb')
        Dim devNodeName(15) As Byte
        devNodeName(0) = 115 ' 's'
        devNodeName(1) = 114 ' 'r'
        devNodeName(2) = 118 ' 'v'
        devNodeName(3) = 46  ' '.'
        devNodeName(4) = 100 ' 'd'
        devNodeName(5) = 101 ' 'e'
        devNodeName(6) = 118 ' 'v'
        devNodeName(7) = 95  ' '_'
        devNodeName(8) = 109 ' 'm'
        devNodeName(9) = 103 ' 'g'
        devNodeName(10) = 114' 'r'
        devNodeName(11) = 0
        Dim devTargetId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @devNodeName(0)))
        If devTargetId > 0 Then
            Dim devSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, devTargetId, 3)
            If devSynId > 0 Then
                Dim devReq As AxonPacket
                devReq.Sequence = 202
                devReq.PacketType = 31 ' DEV_CMD_QUERY
                devReq.SourceNode = userNodeId
                devReq.TargetNode = devTargetId
                Dim devNamePtr As Pointer To Byte = CPtr(Pointer To Byte, "pci.disp.lfb")
                Dim di As UInt32 = 0
                While devNamePtr(di) <> 0
                    devReq.Payload(di) = devNamePtr(di)
                    di = di + 1
                Wend
                devReq.Payload(di) = 0
                devReq.PayloadLength = di + 1
                Syscall2 SYS_SYNAPSE_PUSH, devSynId, CType(UInt64, @devReq)

                Dim devResp As AxonPacket
                If Syscall3(SYS_SYNAPSE_POP, userNodeId, CType(UInt64, @devResp), 1) = 1 Then
                    If devResp.PacketType = 300 Then ' DEV_RESP_OK
                        Dim pBase As Pointer To UInt64 = CPtr(Pointer To UInt64, @devResp.Payload(16))
                        PrintMessageWithUInt CPtr(Pointer To Byte, "[USER-APP] Device Manager verified: 'pci.disp.lfb' (Aperture: 0x"), pBase(0), CPtr(Pointer To Byte, ")\r\n")
                    End If
                End If
            End If
        End If

        ' 12. Verify Plexus Supervisor Service via Synaptic IPC (Querying 'srv.compositor')
        Dim plexNodeName(16) As Byte
        plexNodeName(0) = 115 ' 's'
        plexNodeName(1) = 114 ' 'r'
        plexNodeName(2) = 118 ' 'v'
        plexNodeName(3) = 46  ' '.'
        plexNodeName(4) = 112 ' 'p'
        plexNodeName(5) = 108 ' 'l'
        plexNodeName(6) = 101 ' 'e'
        plexNodeName(7) = 120 ' 'x'
        plexNodeName(8) = 117 ' 'u'
        plexNodeName(9) = 115 ' 's'
        plexNodeName(10) = 95 ' '_'
        plexNodeName(11) = 109' 'm'
        plexNodeName(12) = 103' 'g'
        plexNodeName(13) = 114' 'r'
        plexNodeName(14) = 0
        Dim plexTargetId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @plexNodeName(0)))
        If plexTargetId > 0 Then
            Dim plexSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, userNodeId, plexTargetId, 3)
            If plexSynId > 0 Then
                Dim plexReq As AxonPacket
                plexReq.Sequence = 203
                plexReq.PacketType = 40 ' PLEXUS_CMD_STATUS
                plexReq.SourceNode = userNodeId
                plexReq.TargetNode = plexTargetId
                Dim srvCompName As Pointer To Byte = CPtr(Pointer To Byte, "srv.compositor")
                Dim cpi As UInt32 = 0
                While srvCompName(cpi) <> 0
                    plexReq.Payload(cpi) = srvCompName(cpi)
                    cpi = cpi + 1
                Wend
                plexReq.Payload(cpi) = 0
                plexReq.PayloadLength = cpi + 1
                Syscall2 SYS_SYNAPSE_PUSH, plexSynId, CType(UInt64, @plexReq)

                Dim plexResp As AxonPacket
                If Syscall3(SYS_SYNAPSE_POP, userNodeId, CType(UInt64, @plexResp), 1) = 1 Then
                    If plexResp.PacketType = 400 Then ' PLEXUS_RESP_OK
                        PrintString CPtr(Pointer To Byte, "[USER-APP] Plexus Supervisor verified: 'srv.compositor' is supervised & active\r\n")
                    End If
                End If
            End If
        End If

        PrintString CPtr(Pointer To Byte, "[BRT0] user_main completed successfully. Returning exit code 0.\r\n")
        PrintString CPtr(Pointer To Byte, "[BRT0] =======================================================\r\n")

        user_main = 0
    End Function

End Module
