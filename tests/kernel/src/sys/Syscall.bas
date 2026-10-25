' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sys/Syscall.bas
' Summary: Native microkernel system call dispatch table and MSR programming.

Import Arch.X86_64.PortIO
Import Arch.Acpi
Import Core.Nodes
Import Sched
Use Drivers.SerialUart As Serial
Use Core.Nodes.SynapseChannel
Use Core.Nodes.NodeRegistry As Registry
Use Sched.Scheduler As SchedEngine

Namespace Sys

    Public Module Syscall

        ' Native Microkernel System Call Constants
        Public Const SYS_CONSOLE_WRITE   As UInt64 = 1
        Public Const SYS_PROCESS_YIELD   As UInt64 = 2
        Public Const SYS_PROCESS_SLEEP   As UInt64 = 3
        Public Const SYS_PROCESS_GETPID  As UInt64 = 6
        Public Const SYS_PROCESS_EXIT    As UInt64 = 16
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

        ' Hardware MSR Register Constants
        Private Const IA32_EFER          As UInt32 = &HC0000080
        Private Const IA32_STAR          As UInt32 = &HC0000081
        Private Const IA32_LSTAR         As UInt32 = &HC0000082
        Private Const IA32_FMASK         As UInt32 = &HC0000084

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

            Serial.PrintF "[SYSCALL] Native Microkernel Syscall MSRs configured (LSTAR: 0x%lx)\r\n", lstarAddr
        End Sub

        ''
        ' @brief Central native system call dispatcher called directly from SyscallEntry.S.
        ' @param sysNum Syscall identifier from %rdi.
        ' @param arg1 First user argument from %rsi.
        ' @param arg2 Second user argument from %rdx.
        ' @param arg3 Third user argument from %rcx.
        ' @param arg4 Fourth user argument from %r8.
        ' @return 64-bit return status placed into %rax for sysretq.
        ''
        Public Unsafe Function Dispatch(ByVal sysNum As UInt64, ByVal arg1 As UInt64, ByVal arg2 As UInt64, ByVal arg3 As UInt64, ByVal arg4 As UInt64) As UInt64
            Select Case sysNum
                Case SYS_CONSOLE_WRITE
                    If Not ValidateUserBuffer(arg1, arg2) Then
                        Dispatch = 0
                        Exit Function
                    End If
                    Dim bufPtr As Pointer To Byte = CPtr(Pointer To Byte, arg1)
                    Serial.WriteBuffer bufPtr, arg2
                    Dispatch = arg2

                Case SYS_PROCESS_YIELD
                    SchedEngine.Yield
                    Dispatch = 0

                Case SYS_PROCESS_SLEEP
                    SchedEngine.Sleep CType(UInt32, arg1)
                    Dispatch = 0

                Case SYS_PROCESS_GETPID
                    Dispatch = SchedEngine.GetCurrentPid()

                Case SYS_PROCESS_EXIT
                    SchedEngine.ExitCurrentTask CType(UInt32, arg1)
                    Dispatch = 0

                Case SYS_TIME_UPTIME
                    Dispatch = SchedEngine.GetUptime()

                Case SYS_SMP_CORE_COUNT
                    Dispatch = CType(UInt64, Arch.Acpi.GetCpuCount())

                Case SYS_NODE_REGISTER
                    ' arg1 = kind (UInt32), arg2 = namePtr (UInt64), arg3 = caps (UInt32)
                    If arg2 <> 0 And ValidateUserBuffer(arg2, 1) Then
                        Dim nameStr As Pointer To Byte = CPtr(Pointer To Byte, arg2)
                        Dispatch = Registry.RegisterNode(nameStr, CType(UInt32, arg1), SchedEngine.GetCurrentPid(), CType(UInt32, arg3))
                    Else
                        Dispatch = 0
                    End If

                Case SYS_SYNAPSE_CONNECT
                    ' arg1 = sourceNode (UInt64), arg2 = targetNode (UInt64), arg3 = caps (UInt32)
                    Dispatch = Registry.ConnectSynapse(arg1, arg2, CType(UInt32, arg3))

                Case SYS_SYNAPSE_PUSH
                    ' arg1 = channelId (UInt64), arg2 = packetPtr (UInt64)
                    If ValidateUserBuffer(arg2, SizeOf(AxonPacket)) Then
                        Dim chan As Pointer To SynapseChannel = Registry.GetChannel(arg1)
                        If chan <> 0 Then
                            Dim pktPtr As Pointer To AxonPacket = CPtr(Pointer To AxonPacket, arg2)
                            If chan.PushPacket(pktPtr(0)) Then
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
                    ' arg1 = channelId (UInt64), arg2 = packetPtr (UInt64), arg3 = block (0 or 1)
                    If ValidateUserBuffer(arg2, SizeOf(AxonPacket)) Then
                        Dim chanPop As Pointer To SynapseChannel = Registry.GetChannel(arg1)
                        If chanPop <> 0 Then
                            Dim outPktPtr As Pointer To AxonPacket = CPtr(Pointer To AxonPacket, arg2)
                            Dim shouldBlock As Boolean = (arg3 <> 0)
                            If chanPop.PopPacket(outPktPtr(0), shouldBlock) Then
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

                Case Else
                    Serial.PrintF "[SYSCALL] Unknown native syscall #%u invoked\r\n", CType(UInt32, sysNum)
                    Dispatch = CType(UInt64, -1)
            End Select
        End Function

    End Module

End Namespace
