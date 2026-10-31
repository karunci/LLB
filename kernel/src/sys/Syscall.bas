' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sys/Syscall.bas
' Summary: Native microkernel system call dispatch table and MSR programming.

Import Arch.X86_64.PortIO
Import Arch.Acpi
Import Core.Nodes
Import Sched
Import Exec
Use Drivers.SerialUart As Serial
Use Core.Nodes.SynapseChannel
Use Core.Nodes.NodeRegistry As Registry
Use Sched.Scheduler As SchedEngine
Use Mem.SharedMemoryManager As Shmem
Use Drivers.Framebuffer As FbDriver
Use Mem.VirtualMemoryManager As VmmEngine
Use Mem.BuddyAllocator As Buddy
Use Drivers.Mouse As MouseDriver
Use Drivers.Keyboard As Kbd
Use Mem.PhysicalMemoryManager As PMM
Use Exec.BaxLoader As Bax
Use Mem.KernelHeap As KHeap

Namespace Sys

    <Packed>
    Public Structure InitrdInfo
        Public PhysAddr  As UInt64
        Public SizeBytes As UInt64
    End Structure

    <Packed>
    Public Structure MouseState
        Public X As Int32
        Public Y As Int32
        Public Buttons As Byte
        Public Reserved1 As Byte
        Public Reserved2 As Byte
        Public Reserved3 As Byte
    End Structure

    <Packed>
    Public Structure DisplayInfo
        Public Width    As Int32
        Public Height   As Int32
        Public Pitch    As UInt32
        Public Bpp      As UInt32
        Public PhysAddr As UInt64
    End Structure

    Public Module Syscall

        ' Native Microkernel System Call Constants
        Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
        Public Const SYS_PROCESS_YIELD   As UInt64 = 2
        Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
        Public Const SYS_PROCESS_GETPID  As UInt64 = 6
        Public Const SYS_PROCESS_SPAWN   As UInt64 = 10
        Public Const SYS_PROCESS_WAIT    As UInt64 = 11
        Public Const SYS_PROCESS_EXIT    As UInt64 = 16
        Public Const SYS_GET_MOUSE       As UInt64 = 19
        Public Const SYS_GET_KEY         As UInt64 = 20
        Public Const SYS_MEM_ALLOC_PAGES As UInt64 = 26
        Public Const SYS_TIME_UPTIME     As UInt64 = 28
        Public Const SYS_SYSTEM_INFO     As UInt64 = 33
        Public Const SYS_SMP_CORE_COUNT  As UInt64 = 34

        ' Dual-Plane Neural Node Extensions
        Public Const SYS_NODE_REGISTER   As UInt64 = 50
        Public Const SYS_SYNAPSE_CONNECT As UInt64 = 51
        Public Const SYS_SYNAPSE_PUSH    As UInt64 = 52
        Public Const SYS_SYNAPSE_POP     As UInt64 = 53
        Public Const SYS_SYNAPSE_WAIT    As UInt64 = 54
        Public Const SYS_NODE_LOOKUP     As UInt64 = 55

        ' Zero-Copy Shared Memory Extensions
        Public Const SYS_SHMEM_CREATE    As UInt64 = 60
        Public Const SYS_SHMEM_ATTACH    As UInt64 = 61
        Public Const SYS_SHMEM_DETACH    As UInt64 = 62

        ' Hardware Display Aperture Extensions
        Public Const SYS_FB_GET_INFO     As UInt64 = 70
        Public Const SYS_FB_MAP          As UInt64 = 71

        ' Initrd Memory Mapping Extensions
        Public Const SYS_INITRD_GET_INFO As UInt64 = 80
        Public Const SYS_INITRD_MAP      As UInt64 = 81

        ' Hardware MSR Register Constants
        Private Const IA32_EFER          As UInt32 = &HC0000080
        Private Const IA32_STAR          As UInt32 = &HC0000081
        Private Const IA32_LSTAR         As UInt32 = &HC0000082
        Private Const IA32_FMASK         As UInt32 = &HC0000084
        Private Const IA32_PAT           As UInt32 = &H00000277

        ' Hardware PAT Layout:
        '   PA0 (000b) = WB  (0x06) - Default write-back caching for normal RAM
        '   PA1 (001b) = WC  (0x01) - Write-Combining for linear framebuffers/PCIe MMIO
        '   PA2 (010b) = UC- (0x07) - Weak Uncacheable
        '   PA3 (011b) = UC  (0x00) - Strong Uncacheable
        '   PA4 (100b) = WB  (0x06)
        '   PA5 (101b) = WT  (0x04) - Write-Through
        '   PA6 (110b) = UC- (0x07)
        '   PA7 (111b) = UC  (0x00)
        ' 64-bit value: 0x0007040600070106
        Private Const PAT_CONFIG         As UInt64 = &H0007040600070106

        ' Canonical top of lower-half user address space
        Private Const USER_SPACE_MAX     As UInt64 = &H00007FFFFFFFFFFF

        ''
        ' @brief Write a 64-bit value to a Model-Specific Register (MSR).
        ' @param msr Target MSR index in %ecx.
        ' @param val 64-bit value packed into %edx:%eax.
        ''
        Private Unsafe Sub WriteMsr(ByVal msr As UInt32, ByVal val As UInt64)
            Dim lowPart As UInt32 = CType(UInt32, val And &HFFFFFFFF)
            Dim highPart As UInt32 = CType(UInt32, (val RShift 32) And &HFFFFFFFF)
            Asm "wrmsr" : : "c"(msr), "a"(lowPart), "d"(highPart) : "memory"
        End Sub

        ''
        ' @brief Read a 64-bit value from a Model-Specific Register (MSR).
        ' @param msr Target MSR index in %ecx.
        ' @return 64-bit value assembled from %edx:%eax.
        ''
        Private Unsafe Function ReadMsr(ByVal msr As UInt32) As UInt64
            Dim lowPart As UInt32 = 0
            Dim highPart As UInt32 = 0
            Asm "rdmsr" : "=a"(lowPart), "=d"(highPart) : "c"(msr) : "memory"
            ReadMsr = (CType(UInt64, highPart) LShift 32) Or CType(UInt64, lowPart)
        End Function

        ''
        ' @brief Validate that a user-supplied buffer pointer lies entirely within lower-half canonical space.
        ' @param userPtr Starting virtual address.
        ' @param length Size in bytes of the buffer.
        ' @return True if buffer is within canonical user space, False otherwise.
        ''
        Public Function ValidateUserBuffer(ByVal userPtr As UInt64, ByVal length As UInt64) As Boolean
            If userPtr = 0 Or length = 0 Then
                ValidateUserBuffer = False
                Exit Function
            End If

            If userPtr > USER_SPACE_MAX Then
                ValidateUserBuffer = False
                Exit Function
            End If

            Dim endAddr As UInt64 = userPtr + length
            If endAddr < userPtr Or endAddr > USER_SPACE_MAX Then
                ValidateUserBuffer = False
                Exit Function
            End If

            ValidateUserBuffer = True
        End Function

        ''
        ' @brief Initialize x86_64 Model-Specific Registers for hardware syscall/sysret.
        '        Configures IA32_EFER.SCE, IA32_STAR, IA32_LSTAR, and IA32_FMASK.
        ''
        Public Unsafe Sub Initialize()
            ' 1. Enable System Call Extensions (SCE) in IA32_EFER (Bit 0)
            Dim efer As UInt64 = ReadMsr(IA32_EFER)
            WriteMsr IA32_EFER, efer Or 1

            ' 2. Program IA32_STAR:
            '    Bits 47:32 = Kernel CS (0x08, SS will be 0x10)
            '    Bits 63:48 = User CS/SS base (0x10 -> User SS = 0x1B, User CS = 0x23)
            WriteMsr IA32_STAR, &H0010000800000000

            ' 3. Program IA32_LSTAR with target syscall_entry RIP
            Dim lstarAddr As UInt64 = 0
            Asm "movabs $syscall_entry, %0" : "=r"(lstarAddr) : : "memory"
            WriteMsr IA32_LSTAR, lstarAddr

            ' 4. Program IA32_FMASK to mask Interrupt Flag (IF=0x200), DF (0x400), TF (0x100), NT (0x4000)
            WriteMsr IA32_FMASK, &H00004700

            ' 5. Configure IA32_PAT MSR (PA1 = Write-Combining, PA0 = Write-Back)
            WriteMsr IA32_PAT, PAT_CONFIG

            Serial.PrintF "[SYSCALL] Native Microkernel Syscall & PAT MSRs configured (LSTAR: 0x%lx, PAT: WC enabled)\r\n", lstarAddr
        End Sub

        ''
        ' @brief Central native system call dispatcher called directly from SyscallEntry.S.
        ' @param sysNum Syscall identifier from %rdi.
        ' @param arg1 First user argument from %rsi.
        ' @param arg2 Second user argument from %rdx.
        ' @param arg3 Third user argument from %rcx.
        ' @param arg4 Fourth user argument from %r8.
        ' @param arg5 Fifth user argument from %r9.
        ' @return 64-bit return status placed into %rax for sysretq.
        ''
        Public Unsafe Function Dispatch(ByVal sysNum As UInt64, ByVal arg1 As UInt64, ByVal arg2 As UInt64, ByVal arg3 As UInt64, ByVal arg4 As UInt64, ByVal arg5 As UInt64) As UInt64
            Select Case sysNum
                Case SYS_CONSOLE_WRITE
                    If Not ValidateUserBuffer(arg1, arg2) Then
                        Dispatch = 0
                        Exit Function
                    End If
                    Dim bufPtr As Pointer To Byte = *Byte(arg1)
                    Serial.WriteBuffer bufPtr, arg2
                    Dispatch = arg2

                Case SYS_PROCESS_YIELD
                    SchedEngine.Yield
                    Dispatch = 0

                Case SYS_PROCESS_SLEEP
                    SchedEngine.Sleep UInt32(arg1)
                    Dispatch = 0

                Case SYS_PROCESS_GETPID
                    Dispatch = SchedEngine.GetCurrentPid()

                Case SYS_PROCESS_SPAWN
                    ' arg1 = namePtr, arg2 = shmId, arg3 = argc, arg4 = argvPtr, arg5 = priority
                    Dim namePtr As UInt64 = arg1
                    Dim shmId As UInt64 = arg2
                    Dim argc As UInt64 = arg3
                    Dim argvPtr As UInt64 = arg4
                    Dim priority As UInt32 = UInt32(arg5)
                    If priority = 0 Then priority = 1

                    If shmId = 0 Then
                        Dispatch = 0
                        Exit Function
                    End If

                    ' Extract name
                    Dim procName(32) As Byte
                    Dim pnIdx As UInt32 = 0
                    If namePtr <> 0 And ValidateUserBuffer(namePtr, 1) Then
                        Dim uName As Pointer To Byte = Pointer To Byte(namePtr)
                        While pnIdx < 31 And uName(pnIdx) <> 0
                            procName(pnIdx) = uName(pnIdx)
                            pnIdx = pnIdx + 1
                        Wend
                    End If
                    If pnIdx = 0 Then
                        procName(0) = 112 ' 'p'
                        procName(1) = 114 ' 'r'
                        procName(2) = 111 ' 'o'
                        procName(3) = 99 ' 'c'
                        pnIdx = 4
                    End If
                    procName(pnIdx) = 0

                    ' 1. Resolve shmId physical frames from SharedMemoryManager
                    Dim numPages As UInt32 = 0
                    Dim shmFrames(64) As UInt64
                    If Not Shmem.GetShmemFrames(shmId, numPages, @shmFrames(0), 64) Or numPages = 0 Then
                        Serial.PrintF "[SYSCALL] Error: SYS_PROCESS_SPAWN failed to resolve SHMID %u\r\n", UInt32(shmId)
                        Dispatch = 0
                        Exit Function
                    End If

                    Dim totalShmBytes As UInt64 = UInt64(numPages) * 4096
                    Dim tempBuf As UInt64 = KHeap.KMalloc(totalShmBytes)
                    If tempBuf = 0 Then
                        Serial.PrintF "[SYSCALL] Error: SYS_PROCESS_SPAWN failed to allocate kernel tempBuf\r\n"
                        Dispatch = 0
                        Exit Function
                    End If

                    Dim pi As UInt32 = 0
                    While pi < numPages
                        Dim srcPhys As UInt64 = shmFrames(pi)
                        Dim srcPtr As Pointer To Byte = Pointer To Byte(srcPhys)
                        Dim dstPtr As Pointer To Byte = Pointer To Byte(tempBuf + (UInt64(pi) * 4096))
                        Dim bi As UInt32 = 0
                        While bi < 4096
                            dstPtr(bi) = srcPtr(bi)
                            bi = bi + 1
                        Wend
                        pi = pi + 1
                    Wend

                    ' 2. Allocate User PML4 address space
                    Dim userPml4 As UInt64 = VmmEngine.CreateUserPml4()
                    If userPml4 = 0 Then
                        KHeap.KFree tempBuf
                        Serial.PrintF "[SYSCALL] Error: SYS_PROCESS_SPAWN failed to create User PML4\r\n"
                        Dispatch = 0
                        Exit Function
                    End If

                    ' 3. Load binary segments into User PML4 at 0x40000000 using BaxLoader
                    Dim entryPoint As UInt64 = Bax.LoadBinary(userPml4, tempBuf, totalShmBytes)
                    KHeap.KFree tempBuf
                    If entryPoint = 0 Then
                        Serial.PrintF "[SYSCALL] Error: SYS_PROCESS_SPAWN BaxLoader failed\r\n"
                        VmmEngine.DestroyUserPml4 userPml4
                        Dispatch = 0
                        Exit Function
                    End If

                    ' 4. Allocate and map user stack up to 0x78000000 (top of PDPT[1])
                    ' 64 pages = 256KB: 0x77FC0000 to 0x78000000
                    Dim ustackPages As UInt32 = 64
                    Dim ustackBase As UInt64 = &H78000000 - (UInt64(ustackPages) * 4096)
                    Dim topPhys As UInt64 = 0
                    Dim s As UInt32 = 0
                    While s < ustackPages
                        Dim sPhys As UInt64 = Buddy.AllocPages(0)
                        If s = (ustackPages - 1) Then topPhys = sPhys
                        VmmEngine.MapPage userPml4, ustackBase + (UInt64(s) * 4096), sPhys, &H07
                        s = s + 1
                    Wend

                    ' 5. Allocate child PID
                    Dim childPid As UInt64 = SchedEngine.AllocatePid()

                    ' 6. Enroll in NodeRegistry
                    ' Build unique node name: "<name>.<pid>"
                    Dim uniqueNodeName(32) As Byte
                    Dim uIdx As UInt32 = 0
                    Dim nIdx As UInt32 = 0
                    While nIdx < pnIdx And uIdx < 20
                        uniqueNodeName(uIdx) = procName(nIdx)
                        uIdx = uIdx + 1
                        nIdx = nIdx + 1
                    Wend
                    uniqueNodeName(uIdx) = 46 ' '.'
                    uIdx = uIdx + 1
                    ' append PID digits
                    Dim pidVal As UInt64 = childPid
                    Dim pidDigits(16) As Byte
                    Dim dCount As UInt32 = 0
                    If pidVal = 0 Then
                        pidDigits(0) = 48
                        dCount = 1
                    Else
                        While pidVal > 0 And dCount < 16
                            pidDigits(dCount) = Byte(48 + (pidVal Mod 10))
                            pidVal = pidVal / 10
                            dCount = dCount + 1
                        Wend
                    End If
                    While dCount > 0 And uIdx < 31
                        dCount = dCount - 1
                        uniqueNodeName(uIdx) = pidDigits(dCount)
                        uIdx = uIdx + 1
                    Wend
                    uniqueNodeName(uIdx) = 0

                    Dim childNodeId As UInt64 = Registry.RegisterNode(@uniqueNodeName(0), Core.Nodes.NodeKind.NODE_COMPUTE, childPid, SynapseCaps.CAP_SYNAPSE_READ Or SynapseCaps.CAP_SYNAPSE_WRITE)

                    ' Connect default synapses to parent process
                    Dim parentPid As UInt64 = SchedEngine.GetCurrentPid()
                    Dim parentNodeId As UInt64 = Registry.FindNodeByPid(parentPid)
                    Dim outSyn As UInt64 = 0
                    Dim inSyn As UInt64 = 0
                    If parentNodeId <> 0 And childNodeId <> 0 Then
                        outSyn = Registry.ConnectSynapse(childNodeId, parentNodeId, SynapseCaps.CAP_SYNAPSE_WRITE Or SynapseCaps.CAP_SYNAPSE_READ)
                        inSyn = Registry.ConnectSynapse(parentNodeId, childNodeId, SynapseCaps.CAP_SYNAPSE_WRITE Or SynapseCaps.CAP_SYNAPSE_READ)
                    End If

                    ' 7. Construct NodeStartupContext, argument strings, and synthetic stack frame
                    ' Top stack page physical address: topPhys (mapped at 0x77FFF000..0x78000000)
                    ' Layout in top stack page:
                    '   0x77FFFF80 .. 0x77FFFFDF: NodeStartupContext (96 bytes, offset 0xF80)
                    '   0x77FFFF00 .. 0x77FFFF7F: Command-line argument strings (128 bytes, offset 0xF00)
                    '   0x77FFFE60 .. 0x77FFFEFF: Synthetic stack frame & argv pointer table (offset 0xE60)
                    '   userRsp = 0x77FFFE60 (strictly below NodeStartupContext and strings; all stack growth stays < 0x77FFFE60)
                    Dim ctxVaddr As UInt64 = &H77FFFF80
                    Dim userRsp As UInt64 = &H77FFFE60
                    Dim childArgvPtr As UInt64 = &H77FFFE68
                    Dim parsedArgc As UInt64 = 1

                    If topPhys <> 0 Then
                        ' 7a. Materialize argument strings at child virtual 0x77FFFF00 (offset 0xF00)
                        Dim strBuf As Pointer To Byte = Pointer To Byte(topPhys + &HF00)
                        Dim strOff As UInt32 = 0
                        Dim childArgvVaddr(16) As UInt64

                        ' Arg 0: program name (procName)
                        childArgvVaddr(0) = &H77FFFF00 + UInt64(strOff)
                        Dim si As UInt32 = 0
                        While si < pnIdx And strOff < 126
                            strBuf(strOff) = procName(si)
                            strOff = strOff + 1
                            si = si + 1
                        Wend
                        strBuf(strOff) = 0
                        strOff = strOff + 1
                        parsedArgc = 1

                        ' Arg 1..N: parsed space-delimited tokens from parent argvPtr (rawArgsPtr)
                        If argvPtr <> 0 And ValidateUserBuffer(argvPtr, 1) Then
                            Dim pArgs As Pointer To Byte = Pointer To Byte(argvPtr)
                            Dim ai As UInt32 = 0

                            While pArgs(ai) <> 0 And parsedArgc < 16 And strOff < 126
                                ' Skip leading whitespace (ASCII <= 32: space, tab, newline, cr)
                                While pArgs(ai) <> 0 And pArgs(ai) <= 32
                                    ai = ai + 1
                                Wend

                                If pArgs(ai) <> 0 And strOff < 126 Then
                                    childArgvVaddr(parsedArgc) = &H77FFFF00 + UInt64(strOff)
                                    ' Copy non-whitespace token
                                    While pArgs(ai) > 32 And strOff < 126
                                        strBuf(strOff) = pArgs(ai)
                                        strOff = strOff + 1
                                        ai = ai + 1
                                    Wend
                                    strBuf(strOff) = 0
                                    strOff = strOff + 1
                                    parsedArgc = parsedArgc + 1
                                End If
                            Wend
                        End If

                        ' 7b. Materialize synthetic stack frame at topPhys + 0xE60 (userRsp = 0x77FFFE60)
                        ' System V ABI entry:
                        '   (%rsp)     = parsedArgc (at 0x77FFFE60)
                        '   8(%rsp)    = argv[0]    (at 0x77FFFE68, child virtual &H77FFFF00)
                        '   16(%rsp)   = argv[1]    (at 0x77FFFE70, child virtual of token 1)
                        '   ...
                        '   8*(argc+1) = 0          (NULL sentinel)
                        '   8*(argc+2) = 0          (NULL envp)
                        Dim topPtr As Pointer To UInt64 = Pointer To UInt64(topPhys + &HE60)
                        topPtr(0) = parsedArgc
                        Dim argi As UInt64
                        For argi = 0 To parsedArgc - 1
                            topPtr(argi + 1) = childArgvVaddr(argi)
                        Next argi
                        topPtr(parsedArgc + 1) = 0 ' NULL sentinel
                        topPtr(parsedArgc + 2) = 0 ' NULL envp

                        ' 7c. Construct NodeStartupContext at child virtual 0x77FFFF80 (offset 0xF80)
                        Dim ctxPtr As Pointer To NodeStartupContext = Pointer To NodeStartupContext(topPhys + &HF80)
                        ctxPtr.NodeId = childNodeId
                        ctxPtr.ProcessId = childPid
                        ctxPtr.ParentPid = parentPid
                        ctxPtr.InboundSynapse = inSyn
                        ctxPtr.OutboundSynapse = outSyn
                        ctxPtr.ErrorSynapse = outSyn
                        ctxPtr.Argc = parsedArgc
                        ctxPtr.Argv = childArgvPtr
                        Dim cni As UInt32 = 0
                        While cni < 31 And uniqueNodeName(cni) <> 0
                            ctxPtr.NodeName(cni) = uniqueNodeName(cni)
                            cni = cni + 1
                        Wend
                        ctxPtr.NodeName(cni) = 0
                    End If

                    ' 8. Enqueue task in Scheduler
                    SchedEngine.SpawnUserProcess childPid, @uniqueNodeName(0), entryPoint, userPml4, userRsp, priority, parsedArgc, childArgvPtr, ctxVaddr

                    Serial.PrintF "[SYSCALL] SYS_PROCESS_SPAWN succeeded -> Child PID %u, Node %u, OutSyn %u, Argc %u\r\n", _
                                  UInt32(childPid), UInt32(childNodeId), UInt32(outSyn), UInt32(parsedArgc)
                    Dispatch = childPid

                Case SYS_PROCESS_WAIT
                    ' arg1 = targetPid, arg2 = outStatusPtr, arg3 = flags (0=blocking, 1=non-blocking poll)
                    Dim targetPid As UInt64 = arg1
                    Dim outPtr As UInt64 = arg2
                    Dim flags As UInt64 = arg3

                    If outPtr <> 0 And Not ValidateUserBuffer(outPtr, 4) Then
                        Dispatch = UInt64(-1)
                        Exit Function
                    End If

                    Dim exitCode As UInt32 = 0

                    If flags = 1 Then
                        ' Non-blocking poll
                        Dim pollStatus As Int32 = SchedEngine.GetProcessExitStatus(targetPid, exitCode)
                        If pollStatus = 0 Then
                            If outPtr <> 0 Then
                                Dim pOut As Pointer To UInt32 = Pointer To UInt32(outPtr)
                                pOut(0) = exitCode
                            End If
                            Dispatch = 0
                        ElseIf pollStatus = 1 Then
                            Dispatch = 1
                        Else
                            Dispatch = UInt64(-1)
                        End If
                    Else
                        ' Blocking wait
                        While True
                            Dim waitStatus As Int32 = SchedEngine.GetProcessExitStatus(targetPid, exitCode)
                            If waitStatus = 0 Then
                                If outPtr <> 0 Then
                                    Dim pOut2 As Pointer To UInt32 = Pointer To UInt32(outPtr)
                                    pOut2(0) = exitCode
                                End If
                                Dispatch = 0
                                Exit Function
                            ElseIf waitStatus = -1 Then
                                Dispatch = UInt64(-1)
                                Exit Function
                            End If
                            SchedEngine.Sleep 10
                        Wend
                    End If

                Case SYS_PROCESS_EXIT
                    SchedEngine.ExitCurrentTask UInt32(arg1)
                    Dispatch = 0

                Case SYS_GET_MOUSE
                    ' Hypervisor failsafe: drain pending PS/2 keyboard/mouse data
                    Dim ps2Limit As UInt32 = 16
                    While ps2Limit > 0
                        Dim ps2Status As Byte = Arch.X86_64.PortIO.InB(&H64)
                        If (ps2Status And &H01) = 0 Then Exit While
                        If (ps2Status And &H20) <> 0 Then
                            MouseDriver.HandleInterrupt
                        Else
                            Kbd.HandleInterrupt
                        End If
                        ps2Limit = ps2Limit - 1
                    Wend

                    ' arg1 = userPtr (Pointer To MouseState, 12 bytes)
                    If ValidateUserBuffer(arg1, SizeOf(MouseState)) Then
                        Dim mPtr As Pointer To MouseState = Pointer To MouseState(arg1)
                        Dim mx As Int32 = 0
                        Dim my As Int32 = 0
                        Dim mb As Byte = 0
                        MouseDriver.GetState mx, my, mb
                        mPtr.X = mx
                        mPtr.Y = my
                        mPtr.Buttons = mb
                        Dispatch = 0
                    Else
                        Dispatch = UInt64(-1)
                    End If

                Case SYS_GET_KEY
                    ' Hypervisor failsafe: drain pending PS/2 keyboard/mouse data
                    Dim ps2LimitKbd As UInt32 = 16
                    While ps2LimitKbd > 0
                        Dim ps2StatusKbd As Byte = Arch.X86_64.PortIO.InB(&H64)
                        If (ps2StatusKbd And &H01) = 0 Then Exit While
                        If (ps2StatusKbd And &H20) <> 0 Then
                            MouseDriver.HandleInterrupt
                        Else
                            Kbd.HandleInterrupt
                        End If
                        ps2LimitKbd = ps2LimitKbd - 1
                    Wend
                    Dispatch = UInt64(Kbd.GetChar())

                Case SYS_MEM_ALLOC_PAGES
                    ' arg1 = pageCount (UInt64), arg2 = targetVaddr (UInt64)
                    Dim reqPages As UInt64 = arg1
                    Dim reqVaddr As UInt64 = arg2
                    Dim totalBytes As UInt64 = reqPages * 4096
                    If reqPages > 0 And reqPages <= 8192 And (reqVaddr And &HFFF) = 0 And ValidateUserBuffer(reqVaddr, totalBytes) And reqVaddr >= &H40000000 And (reqVaddr + totalBytes) <= &H78000000 Then
                        Dim memCr3 As UInt64 = SchedEngine.GetCurrentCr3()
                        Dim allocFail As Boolean = False
                        Dim physFrame0 As UInt64 = 0
                        Dim physFrameLast As UInt64 = 0
                        Dim memPidx As UInt64 = 0
                        While memPidx < reqPages
                            Dim physFrame As UInt64 = Buddy.AllocPages(0)
                            If physFrame = 0 Then
                                allocFail = True
                                Exit While
                            End If
                            If memPidx = 0 Then physFrame0 = physFrame
                            physFrameLast = physFrame

                            ' Zero initialize allocated physical frame
                            Dim framePtr As Volatile Pointer To UInt64 = Volatile Pointer To UInt64(physFrame)
                            Dim zIdx As UInt32 = 0
                            While zIdx < 512
                                framePtr(zIdx) = 0
                                zIdx = zIdx + 1
                            Wend

                            ' Map frame into caller's page directory (PTE: Present | Writable | User = 7)
                            VmmEngine.MapPage memCr3, reqVaddr + (memPidx * 4096), physFrame, &H07
                            memPidx = memPidx + 1
                        Wend

                        If Not allocFail Then
                            Serial.PrintF "[MEM_ALLOC_PAGES] PID %u: %u pages @ 0x%lx (Phys: 0x%lx .. 0x%lx)\r\n", _
                                          UInt32(SchedEngine.GetCurrentPid()), UInt32(reqPages), reqVaddr, _
                                          physFrame0, physFrameLast
                        End If

                        If allocFail Then
                            ' Roll back already mapped pages
                            Dim memRollIdx As UInt64 = 0
                            While memRollIdx < memPidx
                                Dim resolved As UInt64 = VmmEngine.VirtToPhys(memCr3, reqVaddr + (memRollIdx * 4096))
                                VmmEngine.UnmapPage memCr3, reqVaddr + (memRollIdx * 4096)
                                If resolved <> 0 Then Buddy.FreePages resolved, 0
                                memRollIdx = memRollIdx + 1
                            Wend
                            Dispatch = 0
                        Else
                            Dispatch = reqVaddr
                        End If
                    Else
                        Dispatch = 0
                    End If

                Case SYS_TIME_UPTIME
                    Dispatch = SchedEngine.GetUptime()

                Case SYS_SMP_CORE_COUNT
                    Dispatch = UInt64(Arch.Acpi.GetCpuCount())

                Case SYS_NODE_REGISTER
                    ' arg1 = kind (UInt32), arg2 = namePtr (UInt64), arg3 = caps (UInt32)
                    If arg2 <> 0 And ValidateUserBuffer(arg2, 1) Then
                        Dim nameStr As Pointer To Byte = *Byte(arg2)
                        Dispatch = Registry.RegisterNode(nameStr, UInt32(arg1), SchedEngine.GetCurrentPid(), UInt32(arg3))
                    Else
                        Dispatch = 0
                    End If

                Case SYS_SYNAPSE_CONNECT
                    ' arg1 = sourceNode (UInt64), arg2 = targetNode (UInt64), arg3 = caps (UInt32)
                    Dispatch = Registry.ConnectSynapse(arg1, arg2, UInt32(arg3))

                Case SYS_SYNAPSE_PUSH
                    ' arg1 = channelId (UInt64), arg2 = packetPtr (UInt64)
                    If ValidateUserBuffer(arg2, SizeOf(AxonPacket)) Then
                        Dim chan As Pointer To SynapseChannel = Registry.GetChannel(arg1)
                        If chan <> 0 Then
                            Dim pktPtr As Pointer To AxonPacket = Pointer To AxonPacket(arg2)
                            If chan.PushPacket(pktPtr(0)) Then
                                Registry.WakeNodeWaiter chan.GetTargetNode()
                                Dispatch = 1
                            Else
                                Dispatch = 0
                            End If
                        Else
                            Dispatch = 0
                        End If
                    Else
                        Dispatch = 0
                    End If

                Case SYS_SYNAPSE_POP
                    ' arg1 = channelId or targetNodeId (UInt64), arg2 = packetPtr (UInt64), arg3 = block (0 or 1)
                    If ValidateUserBuffer(arg2, SizeOf(AxonPacket)) Then
                        Dim outPktPtr As Pointer To AxonPacket = Pointer To AxonPacket(arg2)
                        Dim shouldBlock As Boolean = (arg3 <> 0)
                        If arg1 < 5000 Then
                            ' Node-level multiplexed pop: receive from any channel destined to this node
                            Do
                                Dim chanIn As Pointer To SynapseChannel = Registry.GetInboundChannel(arg1)
                                If chanIn <> 0 Then
                                    If chanIn.PopPacket(outPktPtr(0), False) Then
                                        Registry.SetNodeWaitingPid arg1, 0
                                        Dispatch = 1
                                        Exit Do
                                    End If
                                End If

                                If Not shouldBlock Then
                                    Dispatch = 0
                                    Exit Do
                                End If

                                Registry.SetNodeWaitingPid arg1, SchedEngine.GetCurrentPid()

                                ' Immediate recheck: catch packets queued during window before sleep
                                Dim recheckChan As Pointer To SynapseChannel = Registry.GetInboundChannel(arg1)
                                If recheckChan <> 0 Then
                                    If recheckChan.PopPacket(outPktPtr(0), False) Then
                                        Registry.SetNodeWaitingPid arg1, 0
                                        Dispatch = 1
                                        Exit Do
                                    End If
                                End If

                                ' Bounded sleep: wake up either via WakeNodeWaiter / WakeTask OR timeout after 10ms
                                SchedEngine.Sleep 10
                            Loop
                        Else
                            ' Channel-specific pop
                            Dim chanPop As Pointer To SynapseChannel = Registry.GetChannel(arg1)
                            If chanPop <> 0 Then
                                If chanPop.PopPacket(outPktPtr(0), shouldBlock) Then
                                    Dispatch = 1
                                Else
                                    Dispatch = 0
                                End If
                            Else
                                Dispatch = 0
                            End If
                        End If
                    Else
                        Dispatch = 0
                    End If

                Case SYS_NODE_LOOKUP
                    ' arg1 = namePtr (UInt64)
                    If arg1 <> 0 And ValidateUserBuffer(arg1, 1) Then
                        Dim lookupName As Pointer To Byte = *Byte(arg1)
                        Dispatch = Registry.LookupNode(lookupName)
                    Else
                        Dispatch = 0
                    End If

                Case SYS_SHMEM_CREATE
                    ' arg1 = sizeBytes (UInt64), arg2 = targetVaddr (UInt64)
                    If ValidateUserBuffer(arg2, arg1) Then
                        Dim curPml4 As UInt64 = SchedEngine.GetCurrentCr3()
                        Dim curPid As UInt64 = SchedEngine.GetCurrentPid()
                        Dim shmRes As Int64 = Shmem.CreateShmem(arg1, arg2, curPml4, curPid)
                        Dispatch = UInt64(shmRes)
                    Else
                        Dispatch = UInt64(-1)
                    End If

                Case SYS_SHMEM_ATTACH
                    ' arg1 = shmid (Int64), arg2 = targetVaddr (UInt64)
                    If ValidateUserBuffer(arg2, 4096) Then
                        Dim attPml4 As UInt64 = SchedEngine.GetCurrentCr3()
                        Dim attRes As Int64 = Shmem.AttachShmem(Int64(arg1), arg2, attPml4)
                        If attRes = 0 Then
                            Dispatch = arg2
                        Else
                            Dispatch = 0
                        End If
                    Else
                        Dispatch = 0
                    End If

                Case SYS_SHMEM_DETACH
                    ' arg1 = shmid (Int64)
                    Dim detRes As Int64 = Shmem.DetachShmem(Int64(arg1))
                    Dispatch = UInt64(detRes)

                Case SYS_FB_GET_INFO
                    ' arg1 = userPtr (Pointer To DisplayInfo, 24 bytes)
                    If ValidateUserBuffer(arg1, SizeOf(DisplayInfo)) Then
                        Dim dispPtr As Pointer To DisplayInfo = Pointer To DisplayInfo(arg1)
                        dispPtr.Width = FbDriver.GetDisplayWidth()
                        dispPtr.Height = FbDriver.GetDisplayHeight()
                        dispPtr.Pitch = FbDriver.GetDisplayPitch()
                        dispPtr.Bpp = FbDriver.GetDisplayBpp()
                        dispPtr.PhysAddr = FbDriver.GetFramebufferPhys()
                        Dispatch = 1
                    Else
                        Dispatch = 0
                    End If

                Case SYS_FB_MAP
                    ' arg1 = targetVaddr (UInt64)
                    Dim lfbPhys As UInt64 = FbDriver.GetFramebufferPhys()
                    Dim lfbPitch As UInt64 = UInt64(FbDriver.GetDisplayPitch())
                    Dim lfbHeight As UInt64 = UInt64(FbDriver.GetDisplayHeight())
                    Dim lfbSize As UInt64 = lfbPitch * lfbHeight
                    If lfbPhys <> 0 And lfbSize > 0 And ValidateUserBuffer(arg1, lfbSize) Then
                        Dim callerCr3 As UInt64 = SchedEngine.GetCurrentCr3()
                        Dim pageCount As UInt64 = (lfbSize + 4095) / 4096
                        Dim pIdx As UInt64
                        For pIdx = 0 To pageCount - 1
                            VmmEngine.MapPage callerCr3, arg1 + (pIdx * 4096), lfbPhys + (pIdx * 4096), &H0F ' Present | Writable | User | PWT (PAT PA1 = Write-Combining)
                        Next pIdx
                        Dispatch = 1
                    Else
                        Dispatch = 0
                    End If

                Case SYS_INITRD_GET_INFO
                    ' arg1 = userPtr (Pointer To InitrdInfo, 16 bytes)
                    If ValidateUserBuffer(arg1, SizeOf(InitrdInfo)) Then
                        Dim initrdStartInfo As UInt64 = PMM.GetInitrdStart()
                        Dim initrdEndInfo As UInt64 = PMM.GetInitrdEnd()
                        Dim infoPtr As Pointer To InitrdInfo = Pointer To InitrdInfo(arg1)
                        infoPtr.PhysAddr = initrdStartInfo
                        If initrdEndInfo > initrdStartInfo Then
                            infoPtr.SizeBytes = initrdEndInfo - initrdStartInfo
                        Else
                            infoPtr.SizeBytes = 0
                        End If
                        Dispatch = 1
                    Else
                        Dispatch = 0
                    End If

                Case SYS_INITRD_MAP
                    ' arg1 = targetVaddr (UInt64)
                    Dim initrdMapStart As UInt64 = PMM.GetInitrdStart()
                    Dim initrdMapEnd As UInt64 = PMM.GetInitrdEnd()
                    Dim initrdMapSize As UInt64 = 0
                    If initrdMapEnd > initrdMapStart Then initrdMapSize = initrdMapEnd - initrdMapStart

                    If initrdMapStart <> 0 And initrdMapSize > 0 And ValidateUserBuffer(arg1, initrdMapSize) Then
                        Dim callerMapCr3 As UInt64 = SchedEngine.GetCurrentCr3()
                        Dim pageMapCount As UInt64 = (initrdMapSize + 4095) / 4096
                        Dim pmIdx As UInt64
                        For pmIdx = 0 To pageMapCount - 1
                            VmmEngine.MapPage callerMapCr3, arg1 + (pmIdx * 4096), initrdMapStart + (pmIdx * 4096), &H05 ' Present | User (Read-Only)
                        Next pmIdx
                        Dispatch = 1
                    Else
                        Dispatch = 0
                    End If

                Case Else
                    Serial.PrintF "[SYSCALL] Unknown native syscall #%u invoked\r\n", CType(UInt32, sysNum)
                    Dispatch = CType(UInt64, -1)
            End Select
        End Function

    End Module

End Namespace
