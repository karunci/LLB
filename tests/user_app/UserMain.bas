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

    ' Packed 288-byte AxonPacket structure for fast-path data plane transfer
    <Packed>
    Public Structure AxonPacket
        Public Sequence      As UInt64
        Public PacketType    As UInt32
        Public Flags         As UInt32
        Public SourceNode    As UInt64
        Public TargetNode    As UInt64
        Public PayloadLength As UInt32
        Public Reserved      As UInt32
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
        pkt.Flags = 0
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

        PrintString "[BRT0] user_main completed successfully. Returning exit code 0.\r\n"
        PrintString "[BRT0] =======================================================\r\n"

        user_main = 0
    End Function

End Module
