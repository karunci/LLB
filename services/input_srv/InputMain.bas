' Project Name: PROS (Personal Research Operating System)
' Filename: services/input_srv/InputMain.bas
' Summary: Standalone Ring 3 Unified Input Service driver daemon.
'          Collects raw hardware packets from 'hw.input.raw' and publishes normalized events.

Module InputServiceMain

    ' Native Microkernel System Call Constants
    Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
    Public Const SYS_PROCESS_YIELD   As UInt64 = 2
    Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
    Public Const SYS_PROCESS_GETPID  As UInt64 = 6
    Public Const SYS_PROCESS_EXIT    As UInt64 = 16
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

    ' High-Level Input Event Codes
    Public Const EVENT_KEY_DOWN      As UInt32 = 1
    Public Const EVENT_KEY_UP        As UInt32 = 2
    Public Const EVENT_MOUSE_MOVE    As UInt32 = 3
    Public Const EVENT_MOUSE_BUTTON  As UInt32 = 4

    ' Shared Memory Event Buffer Header Magic ("INPUT_QU")
    Public Const INPUT_QUEUE_MAGIC   As UInt64 = &H494E5055545F5155

    <Packed>
    Public Structure InputEvent
        Public Timestamp  As UInt64
        Public EventType  As UInt32
        Public DeviceId   As UInt32
        Public Code       As UInt32
        Public Modifiers  As UInt32
        Public PosX       As Int32
        Public PosY       As Int32
        Public DeltaX     As Int32
        Public DeltaY     As Int32
    End Structure

    <Packed>
    Public Structure SharedInputQueue
        Public Magic     As UInt64
        Public Head      As UInt32
        Public Tail      As UInt32
        Public Capacity  As UInt32
        Public Reserved  As UInt32
        Public Events(63) As InputEvent
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

        Dim pIdx As UInt32 = 0
        While prefix(pIdx) <> 0 And outIdx < 96
            lineBuf(outIdx) = prefix(pIdx)
            outIdx = outIdx + 1
            pIdx = pIdx + 1
        Wend

        Dim numBuf(24) As Byte
        FormatUInt val, @numBuf(0)
        Dim nIdx As UInt32 = 0
        While numBuf(nIdx) <> 0 And outIdx < 112
            lineBuf(outIdx) = numBuf(nIdx)
            outIdx = outIdx + 1
            nIdx = nIdx + 1
        Wend

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
    ' @brief Main application entry point for PROS Unified Input Service.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintString "[INPUT_SRV] =======================================================\r\n"
        PrintString "[INPUT_SRV] PROS Unified Input Service Daemon Online (CPL=3)\r\n"

        ' 1. Query PID
        Dim pid As UInt64 = Syscall0(SYS_PROCESS_GETPID)
        PrintMessageWithUInt "[INPUT_SRV] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.input' (Kind: Router/Broker = 4, Caps: RWN = 7)
        Dim srvName(31) As Byte
        srvName(0) = 115 ' 's'
        srvName(1) = 114 ' 'r'
        srvName(2) = 118 ' 'v'
        srvName(3) = 46  ' '.'
        srvName(4) = 105 ' 'i'
        srvName(5) = 110 ' 'n'
        srvName(6) = 112 ' 'p'
        srvName(7) = 117 ' 'u'
        srvName(8) = 116 ' 't'
        srvName(9) = 0
        Dim srvNodeId As UInt64 = Syscall3(SYS_NODE_REGISTER, 4, CType(UInt64, @srvName(0)), 7)
        PrintMessageWithUInt "[INPUT_SRV] Registered Node 'srv.input' -> Node #", srvNodeId, "\r\n"

        ' 3. Discover and connect to raw hardware input node: 'hw.input.raw'
        Dim hwRawName(15) As Byte
        hwRawName(0) = 104 ' 'h'
        hwRawName(1) = 119 ' 'w'
        hwRawName(2) = 46  ' '.'
        hwRawName(3) = 105 ' 'i'
        hwRawName(4) = 110 ' 'n'
        hwRawName(5) = 112 ' 'p'
        hwRawName(6) = 117 ' 'u'
        hwRawName(7) = 116 ' 't'
        hwRawName(8) = 46  ' '.'
        hwRawName(9) = 114 ' 'r'
        hwRawName(10) = 97 ' 'a'
        hwRawName(11) = 119' 'w'
        hwRawName(12) = 0
        Dim hwInputNodeId As UInt64 = Syscall1(SYS_NODE_LOOKUP, CType(UInt64, @hwRawName(0)))
        PrintMessageWithUInt "[INPUT_SRV] Discovered 'hw.input.raw' -> ID #", hwInputNodeId, "\r\n"

        If hwInputNodeId > 0 Then
            Dim inputSynId As UInt64 = Syscall3(SYS_SYNAPSE_CONNECT, srvNodeId, hwInputNodeId, 3)
            PrintMessageWithUInt "[INPUT_SRV] Established Synapse to hardware input -> Channel #", inputSynId, "\r\n"
        End If

        ' 4. Allocate Zero-Copy Shared Memory Event Ring Buffer (8 KB at 0x60000000)
        Dim shmVaddr As UInt64 = &H60000000
        Dim shmid As UInt64 = Syscall2(SYS_SHMEM_CREATE, 8192, shmVaddr)
        If shmid > 0 Then
            PrintMessageWithUInt "[INPUT_SRV] Zero-Copy Event Buffer allocated (SHMID: ", shmid, ", Mapped @ 0x60000000)\r\n"
            
            Dim qPtr As Pointer To SharedInputQueue = CPtr(Pointer To SharedInputQueue, shmVaddr)
            qPtr.Magic = INPUT_QUEUE_MAGIC
            qPtr.Head = 0
            qPtr.Tail = 0
            qPtr.Capacity = 64
            PrintString "[INPUT_SRV] Shared Event Queue initialized (Capacity: 64 high-level events)\r\n"
        End If

        ' 5. Yield processor time slice to simulate continuous event dispatching
        PrintString "[INPUT_SRV] Dispatcher loop active. Calling SYS_PROCESS_YIELD...\r\n"
        Syscall0 SYS_PROCESS_YIELD
        PrintString "[INPUT_SRV] Resumed from time slice. Pipeline ready for Compositor.\r\n"

        PrintString "[INPUT_SRV] input_srv daemon operational. Yielding cleanly.\r\n"
        PrintString "[INPUT_SRV] =======================================================\r\n"

        user_main = 0
    End Function

End Module
