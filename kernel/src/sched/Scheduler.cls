' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sched/Scheduler.cls
' Summary: SMP-aware multitasking scheduler managing per-CPU circular runqueues,
'          priority aging, work-stealing, and hardware context switching.
'          Ports PRK kernel/sched.c.

Import Sync
Import Sched
Import Arch.X86_64.Gdt
Import Arch.X86_64.PortIO
Import Arch.Acpi
Import Arch.Smp
Use Drivers.SerialUart As Serial
Use Mem.KernelHeap As KHeap
Use Mem.BuddyAllocator As Buddy
Use Mem.VirtualMemoryManager As VMM
Use Exec.BaxLoader As Bax

Namespace Sched

' External context switch and trampoline routines
Public Declare Sub switch_context(ByVal oldRspPtr As Pointer To UInt64, ByVal newRsp As UInt64, ByVal newCr3 As UInt64, ByVal lockPtr As Pointer To Sync.Spinlock)
Public Declare Sub thread_start_trampoline()

<Instancing(SingleUse)>
Public Class Scheduler

    Public Const KERNEL_STACK_SIZE As UInt32 = 4096
    Public Const MAX_SCHED_CPUS    As UInt32 = 16

    ' Fine-Grained SMP Per-CPU Runqueue Spinlocks & Work-Stealing Lock (Two-Lock Protocol)
    Private coreLocks(16)   As Sync.Spinlock
    Private stealLock       As Sync.Spinlock
    Private schedGlobalLock As Sync.Spinlock
    Private masterKernelCr3 As UInt64
    Private nextPid As UInt64
    Private systemUptimeMs As UInt64
    Private targetCoreIndex As UInt32

    ' Per-CPU Scheduler State (Index 0..MAX_SCHED_CPUS-1)
    Private currentTaskAddrs(16) As UInt64
    Private rtosQueueHeads(16)   As UInt64
    Private gposQueueHeads(16)   As UInt64
    Private idleTaskAddrs(16)    As UInt64

    ' Per-CPU Real Hardware Telemetry Accounting
    Private coreActiveTicks(16) As UInt64
    Private coreIdleTicks(16)   As UInt64
    Private coreTotalTicks(16)  As UInt64
    Private coreSampleActive(16) As UInt64
    Private coreSampleTotal(16) As UInt64
    Private coreLoadPct(16)     As UInt32

    ' Exited process record tracking (for SYS_PROCESS_WAIT exit code reaping)
    Private exitedPids(64) As UInt64
    Private exitedCodes(64) As UInt32
    Private exitedCount As UInt32

    ''
    ' @brief Helper to construct synthetic call frame on a thread stack for context switching.
    '        Mirrors PRK stack layout in create_kernel_thread.
    ' @param tcbPtr Pointer to the target TaskControlBlock.
    ' @param entryPoint Target procedure entry address.
    ''
    Private Unsafe Sub SetupSyntheticStack(ByVal tcbPtr As Pointer To TaskControlBlock, ByVal entryPoint As Pointer To Byte)
        Dim stackTop As UInt64 = (tcbPtr.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)) And (Not CType(UInt64, 15))
        Dim stack As Pointer To UInt64 = CPtr(Pointer To UInt64, stackTop)

        ' IRET Frame for kernel mode transition
        ' SS (0x10 = Kernel Data)
        stack = stack - 1
        stack(0) = &H10

        ' RSP placeholder (16-byte aligned kernel stack top)
        stack = stack - 1
        stack(0) = stackTop

        ' RFLAGS (0x202 = Interrupts Enabled)
        stack = stack - 1
        stack(0) = &H202

        ' CS (0x08 = Kernel Code)
        stack = stack - 1
        stack(0) = &H08

        ' RIP (entryPoint)
        stack = stack - 1
        stack(0) = CType(UInt64, entryPoint)

        ' Dummy Vector & Error Code
        stack = stack - 1
        stack(0) = 0
        stack = stack - 1
        stack(0) = 0

        ' 15 dummy general-purpose registers popped by thread_start_trampoline
        Dim i As UInt32
        For i = 0 To 14
            stack = stack - 1
            stack(0) = 0
        Next i

        ' Return address for switch_context's ret
        stack = stack - 1
        stack(0) = CType(UInt64, @thread_start_trampoline)

        ' 6 dummy callee-saved registers popped by switch_context (rbp, rbx, r12, r13, r14, r15)
        For i = 0 To 5
            stack = stack - 1
            stack(0) = 0
        Next i

        tcbPtr.ContextRsp = CType(UInt64, stack)
        tcbPtr.Rsp = CType(UInt64, stack)
    End Sub

    ''
    ' @brief Helper to construct synthetic call frame for a Ring 3 user thread.
    '        Mirrors PRK stack layout in create_user_thread.
    ' @param tcbPtr Target TaskControlBlock pointer.
    ' @param entryPoint Target virtual RIP in user space.
    ' @param userRsp Target virtual stack pointer in user space.
    ''
    Private Unsafe Sub SetupSyntheticUserStack(ByVal tcbPtr As Pointer To TaskControlBlock, ByVal entryPoint As UInt64, ByVal userRsp As UInt64)
        Dim stackTop As UInt64 = (tcbPtr.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)) And (Not CType(UInt64, 15))
        Dim stack As Pointer To UInt64 = CPtr(Pointer To UInt64, stackTop)

        ' IRET Frame for Ring 3 user transition:
        ' SS = 0x1B (User Data: 0x18 | 3)
        stack = stack - 1
        stack(0) = &H1B

        ' User RSP
        stack = stack - 1
        stack(0) = userRsp

        ' RFLAGS (0x202 = Interrupts Enabled)
        stack = stack - 1
        stack(0) = &H202

        ' CS = 0x23 (User Code: 0x20 | 3)
        stack = stack - 1
        stack(0) = &H23

        ' User RIP (entryPoint)
        stack = stack - 1
        stack(0) = entryPoint

        ' Dummy Vector & Error Code
        stack = stack - 1
        stack(0) = 0
        stack = stack - 1
        stack(0) = 0

        ' 15 dummy general-purpose registers popped by thread_start_trampoline
        Dim i As UInt32
        For i = 0 To 14
            stack = stack - 1
            stack(0) = 0
        Next i

        ' Return address for switch_context's ret
        stack = stack - 1
        stack(0) = CType(UInt64, @thread_start_trampoline)

        ' 6 dummy callee-saved registers popped by switch_context (rbp, rbx, r12, r13, r14, r15)
        For i = 0 To 5
            stack = stack - 1
            stack(0) = 0
        Next i

        tcbPtr.ContextRsp = CType(UInt64, stack)
        tcbPtr.Rsp = CType(UInt64, stack)
    End Sub

    ''
    ' @brief Helper to construct synthetic call frame for a Ring 3 user thread with initial argument registers.
    ' @param tcbPtr Target TaskControlBlock pointer.
    ' @param entryPoint Target virtual RIP in user space.
    ' @param userRsp Target virtual stack pointer in user space.
    ' @param arg1 Value placed into %rdi (argc).
    ' @param arg2 Value placed into %rsi (argv).
    ' @param arg3 Value placed into %rdx (context pointer).
    ''
    Private Unsafe Sub SetupSyntheticUserStackWithArgs(ByVal tcbPtr As Pointer To TaskControlBlock, ByVal entryPoint As UInt64, ByVal userRsp As UInt64, ByVal arg1 As UInt64, ByVal arg2 As UInt64, ByVal arg3 As UInt64)
        Dim stackTop As UInt64 = (tcbPtr.KStackBase + UInt64(KERNEL_STACK_SIZE)) And (Not UInt64(15))
        Dim stack As Pointer To UInt64 = Pointer To UInt64(stackTop)

        ' IRET Frame for Ring 3 user transition:
        stack = stack - 1 : stack(0) = &H1B       ' SS = 0x1B (User Data)
        stack = stack - 1 : stack(0) = userRsp   ' User RSP
        stack = stack - 1 : stack(0) = &H3202     ' RFLAGS (IF=1, IOPL=3 - direct driver I/O enabled)
        stack = stack - 1 : stack(0) = &H23      ' CS = 0x23 (User Code)
        stack = stack - 1 : stack(0) = entryPoint' User RIP

        ' Dummy Vector & Error Code
        stack = stack - 1 : stack(0) = 0
        stack = stack - 1 : stack(0) = 0

        ' 15 general-purpose registers popped by thread_start_trampoline:
        ' i=14(%r15) .. i=6(%rbp), i=5(%rdi), i=4(%rsi), i=3(%rdx), i=2(%rcx), i=1(%rbx), i=0(%rax)
        Dim i As UInt32
        For i = 0 To 14
            stack = stack - 1
            If i = 5 Then
                stack(0) = arg1
            ElseIf i = 4 Then
                stack(0) = arg2
            ElseIf i = 3 Then
                stack(0) = arg3
            Else
                stack(0) = 0
            End If
        Next i

        ' Return address for switch_context's ret
        stack = stack - 1
        stack(0) = UInt64(@thread_start_trampoline)

        ' 6 dummy callee-saved registers popped by switch_context (rbp, rbx, r12, r13, r14, r15)
        For i = 0 To 5
            stack = stack - 1
            stack(0) = 0
        Next i

        tcbPtr.ContextRsp = UInt64(stack)
        tcbPtr.Rsp = UInt64(stack)
    End Sub

    ''
    ' @brief Allocate and configure a dedicated idle task for a specific core.
    ' @param cpuId Target CPU core index.
    ' @return Address of the allocated idle TCB.
    ''
    Private Unsafe Function CreateIdleTaskForCore(ByVal cpuId As UInt32) As UInt64
        Dim idleTcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If idleTcbMem = 0 Then
            Serial.PrintF "[SCHED] Fatal: Failed to allocate idle task for core %d!\r\n", cpuId
            CreateIdleTaskForCore = 0
            Exit Function
        End If

        Dim idleTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, idleTcbMem)
        idleTask.Id = 0
        idleTask.ParentId = 0
        idleTask.State = Sched.ThreadState.STATE_READY
        idleTask.TaskType = Sched.ThreadType.TYPE_GPOS
        idleTask.Priority = 0
        idleTask.WakeUptime = 0
        idleTask.CpuTicks = 0
        idleTask.PendingSignals = 0
        idleTask.Cr3Root = masterKernelCr3
        idleTask.KStackBase = KHeap.KMalloc(KERNEL_STACK_SIZE)
        idleTask.NextTask = idleTcbMem

        SetupSyntheticStack idleTask, @Sched.TaskRoutines.CpuIdleLoop

        CreateIdleTaskForCore = idleTcbMem
    End Function

    ''
    ' @brief Initialize the multitasking scheduler, create BSP boot thread and idle threads.
    '        Mirrors PRK sched_init().
    ''
    Public Unsafe Sub Initialize()
        Sync.SpinlockOps.Init schedGlobalLock
        Sync.SpinlockOps.Init stealLock
        Dim ci As UInt32
        For ci = 0 To 15
            Sync.SpinlockOps.Init coreLocks(ci)
        Next ci

        nextPid = 1
        systemUptimeMs = 0
        targetCoreIndex = 0

        ' Clear per-CPU runqueue tracking
        Dim c As UInt32
        For c = 0 To 15
            currentTaskAddrs(c) = 0
            rtosQueueHeads(c) = 0
            gposQueueHeads(c) = 0
            idleTaskAddrs(c) = 0
            coreActiveTicks(c) = 0
            coreIdleTicks(c) = 0
            coreTotalTicks(c) = 0
            coreSampleActive(c) = 0
            coreSampleTotal(c) = 0
            coreLoadPct(c) = 0
        Next c

        exitedCount = 0
        Dim e As UInt32
        For e = 0 To 63
            exitedPids(e) = 0
            exitedCodes(e) = 0
        Next e

        ' Capture initial master kernel CR3 root
        Dim currentCr3 As UInt64 = 0
        Asm "mov %%cr3, %0" : "=r"(currentCr3)
        masterKernelCr3 = currentCr3

        Serial.PrintF "[SCHED] Initializing SMP Circular Runqueue Scheduler...\r\n"

        ' 1. Allocate and initialize Boot Task (PID 999) on BSP (Core 0)
        Dim bootTcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If bootTcbMem = 0 Then
            Serial.PrintF "[SCHED] Fatal: Failed to allocate TCB for boot task!\r\n"
            Exit Sub
        End If

        Dim bootTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, bootTcbMem)
        bootTask.Id = 999
        bootTask.ParentId = 0
        bootTask.State = Sched.ThreadState.STATE_RUNNING
        bootTask.TaskType = Sched.ThreadType.TYPE_GPOS
        bootTask.Priority = 0
        bootTask.WakeUptime = 0
        bootTask.CpuTicks = 0
        bootTask.PendingSignals = 0
        bootTask.Cr3Root = masterKernelCr3
        bootTask.KStackBase = KHeap.KMalloc(KERNEL_STACK_SIZE)
        bootTask.ContextRsp = 0
        bootTask.Rsp = 0
        bootTask.NextTask = bootTcbMem

        currentTaskAddrs(0) = bootTcbMem
        gposQueueHeads(0) = bootTcbMem

        ' Ensure Core 0 TSS RSP0 points to the boot thread stack top
        Dim bootKstackTop As UInt64 = bootTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)
        Arch.X86_64.Gdt.SetKernelStackForCore 0, bootKstackTop

        ' 2. Create idle task for Core 0 (BSP)
        idleTaskAddrs(0) = CreateIdleTaskForCore(0)

        ' 3. Pre-create idle tasks for AP cores so they are immediately available
        For c = 1 To 15
            idleTaskAddrs(c) = CreateIdleTaskForCore(c)
        Next c

        Serial.PrintF "[SCHED] Scheduler active. Boot PID: %u, Idle PID: 0\r\n", CType(UInt32, bootTask.Id)
    End Sub

    ''
    ' @brief Application Processor (AP) core entry into the scheduler.
    '        Sets active task to this core's idle thread and enters yield loop.
    '        Mirrors PRK kernel/smp.c ap_main scheduler handoff.
    ' @param cpuId Logical ID of the AP core.
    ''
    Public Unsafe Sub ApEnter(ByVal cpuId As UInt32)
        If cpuId >= MAX_SCHED_CPUS Then Exit Sub

        Dim idleMem As UInt64 = idleTaskAddrs(cpuId)
        If idleMem = 0 Then
            idleMem = CreateIdleTaskForCore(cpuId)
            idleTaskAddrs(cpuId) = idleMem
        End If

        Dim idleTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, idleMem)
        idleTask.State = Sched.ThreadState.STATE_RUNNING
        currentTaskAddrs(cpuId) = idleMem

        Dim idleKstackTop As UInt64 = idleTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)
        Arch.X86_64.Gdt.SetKernelStackForCore cpuId, idleKstackTop

        Serial.PrintF "[SCHED] AP Core #%d online: idle task ready. Waiting for dispatch barrier...\r\n", cpuId

        ' Atomically notify BSP that idle task is online and serial output is done
        SignalApJoined

        ' Wait for BSP to complete full SMP bring-up of all cores and signal dispatch start
        While Not Arch.Smp.IsDispatchActive()
            Asm "pause" : : : "memory"
        Wend

        ' Enable hardware interrupts on AP and start cooperative yield loop
        Arch.X86_64.PortIO.Sti
        Do
            Yield
            Asm "sti\n\tnop\n\thlt" : : : "memory"
        Loop
    End Sub

    ''
    ' @brief Determine target core for scheduling new threads via round-robin.
    '        Mirrors PRK get_next_target_core().
    ' @return Logical CPU index to receive the new thread.
    ''
    Private Function GetNextTargetCore() As UInt32
        Dim onlineCores As UInt32 = Arch.Smp.GetOnlineCoreCount()
        If onlineCores = 0 Or onlineCores > MAX_SCHED_CPUS Then
            onlineCores = 1
        End If

        Dim target As UInt32 = targetCoreIndex Mod onlineCores
        targetCoreIndex = targetCoreIndex + 1
        GetNextTargetCore = target
    End Function

    ''
    ' @brief Create a new kernel thread and enqueue it into a core's runqueue.
    '        Mirrors PRK create_kernel_thread().
    ' @param entryPoint Address of subroutine to execute.
    ' @param taskType ThreadType (RTOS or GPOS).
    ' @param priority Initial scheduling priority.
    ' @return Address of the newly created TaskControlBlock structure.
    ''
    Public Unsafe Function CreateKernelThread(ByVal entryPoint As Pointer To Byte, ByVal taskType As UInt32, ByVal priority As UInt32) As UInt64
        Dim tcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If tcbMem = 0 Then
            Serial.PrintF "[SCHED] Error: Failed to allocate TCB for kernel thread!\r\n"
            CreateKernelThread = 0
            Exit Function
        End If

        Dim thread As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, tcbMem)

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedGlobalLock)
        Dim assignedPid As UInt64 = nextPid
        nextPid = nextPid + 1
        Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, flags

        thread.Id = assignedPid
        thread.ParentId = 0
        thread.State = Sched.ThreadState.STATE_READY
        thread.TaskType = taskType
        thread.Priority = priority
        thread.WakeUptime = 0
        thread.CpuTicks = 0
        thread.PendingSignals = 0
        thread.Cr3Root = masterKernelCr3
        thread.KStackBase = KHeap.KMalloc(KERNEL_STACK_SIZE)

        If thread.KStackBase = 0 Then
            Serial.PrintF "[SCHED] Error: Failed to allocate stack for kernel thread PID %u!\r\n", CType(UInt32, assignedPid)
            KHeap.KFree tcbMem
            CreateKernelThread = 0
            Exit Function
        End If

        SetupSyntheticStack thread, entryPoint

        ' Select target CPU core and insert into its circular runqueue
        Dim targetCore As UInt32 = GetNextTargetCore()

        flags = Sync.SpinlockOps.AcquireIrqSave(coreLocks(targetCore))
        If taskType = Sched.ThreadType.TYPE_RTOS Then
            If rtosQueueHeads(targetCore) = 0 Then
                rtosQueueHeads(targetCore) = tcbMem
                thread.NextTask = tcbMem
            Else
                Dim rHead As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, rtosQueueHeads(targetCore))
                thread.NextTask = rHead.NextTask
                rHead.NextTask = tcbMem
            End If
        Else
            If gposQueueHeads(targetCore) = 0 Then
                gposQueueHeads(targetCore) = tcbMem
                thread.NextTask = tcbMem
            Else
                Dim gHead As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, gposQueueHeads(targetCore))
                thread.NextTask = gHead.NextTask
                gHead.NextTask = tcbMem
            End If
        End If
        Sync.SpinlockOps.ReleaseIrqRestore coreLocks(targetCore), flags

        Serial.PrintF "[SCHED] Spawned Kernel Thread (PID: %u, Priority: %u) assigned to Core #%d\r\n", CType(UInt32, assignedPid), priority, targetCore
        CreateKernelThread = tcbMem
    End Function

    ''
    ' @brief Create a new user thread with isolated CR3, stack ASLR, and Ring 3 iret frame.
    '        Mirrors PRK create_user_thread_from_buffer().
    ' @param name Identifier string.
    ' @param entryPoint Virtual entry address in user space (e.g. 0x400000).
    ' @param userPml4 Physical CR3 root of user address space.
    ' @param priority Initial scheduling priority.
    ' @return PID of newly created user thread.
    ''
    Public Unsafe Function CreateUserThread(ByVal name As Pointer To Byte, ByVal entryPoint As UInt64, ByVal userPml4 As UInt64, ByVal priority As UInt32) As UInt64
        Dim tcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If tcbMem = 0 Then
            CreateUserThread = 0
            Exit Function
        End If

        Dim thread As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, tcbMem)

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedGlobalLock)
        Dim assignedPid As UInt64 = nextPid
        nextPid = nextPid + 1
        Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, flags

        thread.Id = assignedPid
        thread.ParentId = GetCurrentPid()
        thread.State = Sched.ThreadState.STATE_READY
        thread.TaskType = Sched.ThreadType.TYPE_GPOS
        thread.Priority = priority
        thread.WakeUptime = 0
        thread.CpuTicks = 0
        thread.PendingSignals = 0
        thread.Cr3Root = userPml4
        thread.KStackBase = KHeap.KMalloc(KERNEL_STACK_SIZE)

        If thread.KStackBase = 0 Then
            KHeap.KFree tcbMem
            CreateUserThread = 0
            Exit Function
        End If

        ' ASLR Entropy Generator (random 16-page increments up to 1MB slide via TSC)
        Dim tsc As UInt64 = 0
        Asm "rdtsc" : "=A"(tsc) : : "memory"
        Dim randomSlide As UInt64 = ((tsc Xor systemUptimeMs) And &H0F) * &H10000
        Dim ustackVaddr As UInt64 = &H70000000 - randomSlide

        ' Allocate and map user stack pages (64 pages = 256KB stack)
        Dim stackPages As UInt32 = 64
        Dim topPhys As UInt64 = 0
        Dim s As UInt32
        For s = 0 To stackPages - 1
            Dim ustackPhys As UInt64 = Buddy.AllocPages(0)
            If s = (stackPages - 1) Then
                topPhys = ustackPhys
            End If
            VMM.MapPage userPml4, ustackVaddr + CType(UInt64, s * 4096), ustackPhys, &H07 ' PTE_PRESENT | PTE_WRITABLE | PTE_USER
        Next s

        ' Initialize user stack frame: envp[0]=0, argv[0]=0, argc=0
        If topPhys <> 0 Then
            Dim topPtr As Pointer To UInt64 = CPtr(Pointer To UInt64, topPhys + 4096)
            topPtr = topPtr - 1
            topPtr(0) = 0 ' NULL envp
            topPtr = topPtr - 1
            topPtr(0) = 0 ' NULL argv
            topPtr = topPtr - 1
            topPtr(0) = 0 ' argc = 0
        End If

        Dim userRsp As UInt64 = ustackVaddr + CType(UInt64, stackPages * 4096) - 24

        SetupSyntheticUserStack thread, entryPoint, userRsp

        ' Select target CPU core and insert into its circular runqueue
        Dim targetCore As UInt32 = GetNextTargetCore()

        flags = Sync.SpinlockOps.AcquireIrqSave(coreLocks(targetCore))
        If gposQueueHeads(targetCore) = 0 Then
            gposQueueHeads(targetCore) = tcbMem
            thread.NextTask = tcbMem
        Else
            Dim gHead As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, gposQueueHeads(targetCore))
            thread.NextTask = gHead.NextTask
            gHead.NextTask = tcbMem
        End If
        Sync.SpinlockOps.ReleaseIrqRestore coreLocks(targetCore), flags

        Serial.PrintF "[SCHED] Spawned User Thread '%s' (PID: %u, Entry: 0x%x, RSP: 0x%x) on Core #%d\r\n", _
                      name, CType(UInt32, assignedPid), entryPoint, userRsp, targetCore
        CreateUserThread = assignedPid
    End Function

    ''
    ' @brief Spawn a native NEO/PE-BAX executable process from in-memory binary image.
    ' @param name Human-readable process identifier.
    ' @param baxDataAddr Physical/virtual address of raw .bax binary image.
    ' @param baxSize Size of the .bax binary in bytes.
    ' @param priority Initial execution priority.
    ' @return Assigned PID on success, or 0 on failure.
    ''
    Public Unsafe Function CreateBaxProcess(ByVal name As Pointer To Byte, ByVal baxDataAddr As UInt64, ByVal baxSize As UInt64, ByVal priority As UInt32) As UInt64
        If baxDataAddr = 0 Or baxSize = 0 Then
            CreateBaxProcess = 0
            Exit Function
        End If

        ' Create dedicated User PML4 address space with cloned kernel supervisor half
        Dim userPml4 As UInt64 = VMM.CreateUserPml4()
        If userPml4 = 0 Then
            Serial.PrintF "[SCHED] Error: Failed to create User PML4 for BAX process!\r\n"
            CreateBaxProcess = 0
            Exit Function
        End If

        ' Load, verify, and map NEO/PE-BAX segments and resources into user address space
        Dim entryPoint As UInt64 = Bax.LoadBinary(userPml4, baxDataAddr, baxSize)
        If entryPoint = 0 Then
            Serial.PrintF "[SCHED] Error: BaxLoader failed to load binary!\r\n"
            CreateBaxProcess = 0
            Exit Function
        End If

        ' Spawn user thread using verified entrypoint and mapped User PML4
        CreateBaxProcess = Me.CreateUserThread(name, entryPoint, userPml4, priority)
    End Function

    ''
    ' @brief Atomically allocate the next available Process ID (PID).
    ' @return Unique 64-bit PID.
    ''
    Public Unsafe Function AllocatePid() As UInt64
        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedGlobalLock)
        Dim assignedPid As UInt64 = nextPid
        nextPid = nextPid + 1
        Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, flags
        AllocatePid = assignedPid
    End Function

    ''
    ' @brief Enqueue a dynamic user process with pre-allocated PID and custom argument registers.
    ' @param assignedPid Pre-allocated Process ID.
    ' @param name Identifier string.
    ' @param entryPoint Target virtual RIP in user space.
    ' @param userPml4 Physical CR3 root of user address space.
    ' @param userRsp Target virtual stack pointer in user space.
    ' @param priority Initial scheduling priority.
    ' @param argc Value passed into %rdi.
    ' @param argv Value passed into %rsi.
    ' @param ctxPtr Value passed into %rdx (Pointer To NodeStartupContext).
    ' @return Assigned PID on success, 0 on failure.
    ''
    Public Unsafe Function SpawnUserProcess(ByVal assignedPid As UInt64, ByVal name As Pointer To Byte, ByVal entryPoint As UInt64, ByVal userPml4 As UInt64, ByVal userRsp As UInt64, ByVal priority As UInt32, ByVal argc As UInt64, ByVal argv As UInt64, ByVal ctxPtr As UInt64) As UInt64
        Dim tcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If tcbMem = 0 Then
            SpawnUserProcess = 0
            Exit Function
        End If

        Dim thread As Pointer To TaskControlBlock = Pointer To TaskControlBlock(tcbMem)
        thread.Id = assignedPid
        thread.ParentId = GetCurrentPid()
        thread.State = Sched.ThreadState.STATE_READY
        thread.TaskType = Sched.ThreadType.TYPE_GPOS
        thread.Priority = priority
        thread.WakeUptime = 0
        thread.CpuTicks = 0
        thread.PendingSignals = 0
        thread.Cr3Root = userPml4
        thread.KStackBase = KHeap.KMalloc(KERNEL_STACK_SIZE)
        thread.ExitCode = 0

        If thread.KStackBase = 0 Then
            KHeap.KFree tcbMem
            SpawnUserProcess = 0
            Exit Function
        End If

        SetupSyntheticUserStackWithArgs thread, entryPoint, userRsp, argc, argv, ctxPtr

        ' Select target CPU core and insert into its circular runqueue
        Dim targetCore As UInt32 = GetNextTargetCore()

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(coreLocks(targetCore))
        If gposQueueHeads(targetCore) = 0 Then
            gposQueueHeads(targetCore) = tcbMem
            thread.NextTask = tcbMem
        Else
            Dim gHead As Pointer To TaskControlBlock = Pointer To TaskControlBlock(gposQueueHeads(targetCore))
            thread.NextTask = gHead.NextTask
            gHead.NextTask = tcbMem
        End If
        Sync.SpinlockOps.ReleaseIrqRestore coreLocks(targetCore), flags

        Serial.PrintF "[SCHED] Spawned Dynamic Process '%s' (PID: %u, Entry: 0x%lx, RSP: 0x%lx, Ctx: 0x%lx) on Core #%d\r\n", _
                      name, UInt32(assignedPid), entryPoint, userRsp, ctxPtr, targetCore
        SpawnUserProcess = assignedPid
    End Function

    ''
    ' @brief Select next ready task from a circular runqueue using priority aging.
    '        Mirrors PRK pick_next_ready().
    ''
    Private Unsafe Function PickNextReady(ByVal prevAddr As UInt64, ByVal queueHead As UInt64) As UInt64
        If queueHead = 0 Then
            PickNextReady = 0
            Exit Function
        End If

        Dim bestOtherAddr As UInt64 = 0
        Dim bestOtherUrgency As UInt32 = 0
        Dim bestPrevAddr As UInt64 = 0
        Dim bestPrevUrgency As UInt32 = 0

        Dim iterAddr As UInt64 = queueHead

        Do
            Dim iter As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, iterAddr)

            ' Wake sleeping tasks whose timer has expired
            If iter.State = Sched.ThreadState.STATE_BLOCKED And iter.WakeUptime > 0 Then
                If systemUptimeMs >= iter.WakeUptime Then
                    iter.State = Sched.ThreadState.STATE_READY
                    iter.WakeUptime = 0
                End If
            End If

            If iter.State = Sched.ThreadState.STATE_READY Or iter.State = Sched.ThreadState.STATE_RUNNING Then
                Dim urgency As UInt32 = iter.Priority

                ' Priority aging: boost priority for starving ready threads
                If iter.State = Sched.ThreadState.STATE_READY Then
                    iter.CpuTicks = iter.CpuTicks + 1
                    If iter.CpuTicks > 50 Then
                        urgency = urgency + (CType(UInt32, iter.CpuTicks) / 50)
                    End If
                End If

                If iterAddr = prevAddr Then
                    If bestPrevAddr = 0 Or urgency > bestPrevUrgency Then
                        bestPrevAddr = iterAddr
                        bestPrevUrgency = urgency
                    End If
                Else
                    If bestOtherAddr = 0 Or urgency >= bestOtherUrgency Then
                        bestOtherAddr = iterAddr
                        bestOtherUrgency = urgency
                    End If
                End If
            End If

            iterAddr = iter.NextTask
        Loop While iterAddr <> queueHead

        ' Prefer a different runnable thread over the one that just ran
        If bestOtherAddr <> 0 Then
            PickNextReady = bestOtherAddr
            Exit Function
        End If

        ' Allow previous thread to continue if runnable
        If prevAddr <> 0 Then
            Dim prevTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, prevAddr)
            If prevTask.State = Sched.ThreadState.STATE_READY Or prevTask.State = Sched.ThreadState.STATE_RUNNING Then
                PickNextReady = prevAddr
                Exit Function
            End If
        End If

        PickNextReady = 0
    End Function

    ''
    ' @brief Attempt to steal a ready task from other CPU cores' runqueues when local queue is empty.
    '        Balances workloads across SMP cores.
    ' @param thisCpu Logical ID of the calling CPU core looking for work.
    ' @return Address of stolen ready TCB, or 0 if all cores are idle.
    ''
    ''
    ' @brief Work-stealing is disabled in favor of strict partitioned SMP queues.
    ''
    Private Unsafe Function StealTask(ByVal thisCpu As UInt32) As UInt64
        StealTask = 0
    End Function

    ''
    ' @brief Core scheduling engine performing context switch to next task on calling core.
    '        Mirrors PRK _sched_yield_internal().
    ''
    Private Unsafe Sub SchedYieldInternal(ByVal targetState As UInt32, ByVal sleepMs As UInt64)
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId >= MAX_SCHED_CPUS Then coreId = 0

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(coreLocks(coreId))

        Dim prevAddr As UInt64 = currentTaskAddrs(coreId)
        Dim prevTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, prevAddr)

        If prevAddr <> 0 And prevTask.State = Sched.ThreadState.STATE_RUNNING Then
            prevTask.State = targetState
            If targetState = Sched.ThreadState.STATE_BLOCKED And sleepMs > 0 Then
                prevTask.WakeUptime = systemUptimeMs + sleepMs
            End If
        End If

        ' Pick next runnable task: RTOS queue first, then local GPOS queue
        Dim nextAddr As UInt64 = PickNextReady(prevAddr, rtosQueueHeads(coreId))
        If nextAddr = 0 Then
            nextAddr = PickNextReady(prevAddr, gposQueueHeads(coreId))
        End If

        ' Fallback to dedicated Idle task for this core
        If nextAddr = 0 Then
            nextAddr = idleTaskAddrs(coreId)
        End If

        ' Failsafe: if idle task for this core is not ready, fallback to Core 0 idle or previous task
        If nextAddr = 0 Then
            nextAddr = idleTaskAddrs(0)
        End If
        If nextAddr = 0 Then
            nextAddr = prevAddr
        End If

        If nextAddr = 0 Then
            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(coreId), flags
            Exit Sub
        End If

        If prevAddr = nextAddr Then
            If prevAddr <> 0 Then
                If prevTask.State = Sched.ThreadState.STATE_READY Or prevTask.State = Sched.ThreadState.STATE_RUNNING Then
                    prevTask.State = Sched.ThreadState.STATE_RUNNING
                End If
            End If
            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(coreId), flags
            Exit Sub
        End If

        currentTaskAddrs(coreId) = nextAddr
        Dim nextTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, nextAddr)
        nextTask.State = Sched.ThreadState.STATE_RUNNING

        ' Set per-core TSS RSP0 stack pointer to next task's kernel stack (strictly 16-byte aligned)
        Dim kstackTop As UInt64 = (nextTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)) And (Not CType(UInt64, 15))
        Arch.X86_64.Gdt.SetKernelStackForCore coreId, kstackTop

        Dim targetCr3 As UInt64 = nextTask.Cr3Root
        If targetCr3 = 0 Then
            targetCr3 = masterKernelCr3
        End If

        ' Switch context in hardware (releases this core's local spinlock upon RSP switch)
        switch_context @prevTask.ContextRsp, nextTask.ContextRsp, targetCr3, AddressOf coreLocks(coreId)

        ' If interrupts were enabled prior to yield, re-enable them
        If (flags And &H200) <> 0 Then
            Asm "sti" : : : "memory"
        End If
    End Sub

    ''
    ' @brief Yield processor execution to the next runnable thread.
    '        Mirrors PRK sched_yield() / thread_yield().
    ''
    Public Unsafe Sub Yield()
        SchedYieldInternal Sched.ThreadState.STATE_READY, 0
        If exitedCount > 0 Then
            ReapTerminatedTasks
        End If
    End Sub

    ''
    ' @brief Put the current task to sleep for the specified duration in milliseconds.
    '        Mirrors PRK thread_sleep().
    ' @param ms Duration to sleep in milliseconds.
    ''
    Public Unsafe Sub Sleep(ByVal ms As UInt64)
        SchedYieldInternal Sched.ThreadState.STATE_BLOCKED, ms
    End Sub

    ''
    ' @brief Periodic timer tick handler called from system timer ISR.
    '        Advances system uptime and triggers rescheduling.
    '        Mirrors PRK schedule().
    ''
    Public Unsafe Sub OnTimerTick(ByVal elapsedMs As UInt64)
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId >= MAX_SCHED_CPUS Then coreId = 0

        If elapsedMs > 0 Then
            systemUptimeMs = systemUptimeMs + elapsedMs
        End If

        Dim currAddr As UInt64 = currentTaskAddrs(coreId)
        If currAddr <> 0 Then
            Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currAddr)
            curr.CpuTicks = curr.CpuTicks + 1
        End If

        ' Real hardware tick accounting for CPU usage derivation
        coreTotalTicks(coreId) = coreTotalTicks(coreId) + 1
        If currAddr = idleTaskAddrs(coreId) Then
            coreIdleTicks(coreId) = coreIdleTicks(coreId) + 1
        Else
            coreActiveTicks(coreId) = coreActiveTicks(coreId) + 1
        End If

        ' Compute live windowed load percentage every 10 ticks (100 ms)
        Dim dTot As UInt64 = coreTotalTicks(coreId) - coreSampleTotal(coreId)
        If dTot >= 10 Then
            Dim dAct As UInt64 = coreActiveTicks(coreId) - coreSampleActive(coreId)
            coreLoadPct(coreId) = UInt32((dAct * 100) / dTot)
            coreSampleTotal(coreId) = coreTotalTicks(coreId)
            coreSampleActive(coreId) = coreActiveTicks(coreId)
        End If

        ' If running idle task, check if any task in local runqueues is ready or expiring
        If currAddr = idleTaskAddrs(coreId) Then
            Dim hasWork As Boolean = False
            Dim qh As UInt64 = rtosQueueHeads(coreId)
            If qh <> 0 Then
                Dim rIt As UInt64 = qh
                Do
                    Dim rT As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, rIt)
                    If rT.State = Sched.ThreadState.STATE_READY Then
                        hasWork = True
                        Exit Do
                    End If
                    If rT.State = Sched.ThreadState.STATE_BLOCKED And rT.WakeUptime > 0 And systemUptimeMs >= rT.WakeUptime Then
                        hasWork = True
                        Exit Do
                    End If
                    rIt = rT.NextTask
                Loop While rIt <> qh
            End If
            If Not hasWork Then
                qh = gposQueueHeads(coreId)
                If qh <> 0 Then
                    Dim gIt As UInt64 = qh
                    Do
                        Dim gT As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, gIt)
                        If gT.State = Sched.ThreadState.STATE_READY Then
                            hasWork = True
                            Exit Do
                        End If
                        If gT.State = Sched.ThreadState.STATE_BLOCKED And gT.WakeUptime > 0 And systemUptimeMs >= gT.WakeUptime Then
                            hasWork = True
                            Exit Do
                        End If
                        gIt = gT.NextTask
                    Loop While gIt <> qh
                End If
            End If
            If Not hasWork Then
                Exit Sub
            End If
        End If

        Yield
    End Sub

    ''
    ' @brief Query real live load percentage for target CPU core.
    ''
    Public Function GetCoreLoad(ByVal cpuId As UInt32) As UInt32
        If cpuId >= MAX_SCHED_CPUS Then
            GetCoreLoad = 0
        Else
            GetCoreLoad = coreLoadPct(cpuId)
        End If
    End Function

    ''
    ' @brief Query real cumulative active ticks for target CPU core.
    ''
    Public Function GetCoreActiveTicks(ByVal cpuId As UInt32) As UInt64
        If cpuId >= MAX_SCHED_CPUS Then
            GetCoreActiveTicks = 0
        Else
            GetCoreActiveTicks = coreActiveTicks(cpuId)
        End If
    End Function

    ''
    ' @brief Query real cumulative idle ticks for target CPU core.
    ''
    Public Function GetCoreIdleTicks(ByVal cpuId As UInt32) As UInt64
        If cpuId >= MAX_SCHED_CPUS Then
            GetCoreIdleTicks = 0
        Else
            GetCoreIdleTicks = coreIdleTicks(cpuId)
        End If
    End Function

    ''
    ' @brief Query real cumulative total ticks for target CPU core.
    ''
    Public Function GetCoreTotalTicks(ByVal cpuId As UInt32) As UInt64
        If cpuId >= MAX_SCHED_CPUS Then
            GetCoreTotalTicks = 0
        Else
            GetCoreTotalTicks = coreTotalTicks(cpuId)
        End If
    End Function

    ''
    ' @brief Get the currently active task ID (PID) on the calling core.
    ' @return Current PID or 0.
    ''
    Public Unsafe Function GetCurrentPid() As UInt64
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId >= MAX_SCHED_CPUS Then coreId = 0

        If currentTaskAddrs(coreId) = 0 Then
            GetCurrentPid = 0
            Exit Function
        End If
        Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currentTaskAddrs(coreId))
        GetCurrentPid = curr.Id
    End Function

    ''
    ' @brief Get the hardware Cr3Root of the currently executing task on this CPU core.
    ' @return Physical PML4 root address, or kernel PML4 if no active user task.
    ''
    Public Unsafe Function GetCurrentCr3() As UInt64
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId >= MAX_SCHED_CPUS Then coreId = 0

        If currentTaskAddrs(coreId) = 0 Then
            GetCurrentCr3 = VMM.GetKernelPml4()
            Exit Function
        End If
        Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currentTaskAddrs(coreId))
        If curr.Cr3Root <> 0 Then
            GetCurrentCr3 = curr.Cr3Root
        Else
            GetCurrentCr3 = VMM.GetKernelPml4()
        End If
    End Function

    ''
    ' @brief Transition current task to STATE_BLOCKED and immediately yield CPU.
    ''
    Public Unsafe Sub BlockCurrentTask()
        ' Guarantee 10ms safety fallback in case WakeTask was called before thread completed state switch
        SchedYieldInternal Sched.ThreadState.STATE_BLOCKED, 10
    End Sub

    ''
    ' @brief Unblock a sleeping or blocked task by PID, transitioning it back to STATE_READY.
    '        Mirrors PRK thread_wake(pid).
    ' @param targetPid Task ID of thread to wake.
    ' @return True if task was found and unblocked, False otherwise.
    ''
    Public Unsafe Function WakeTask(ByVal targetPid As UInt64) As Boolean
        If targetPid = 0 Then
            WakeTask = False
            Exit Function
        End If

        Dim onlineCores As UInt32 = Arch.Acpi.GetCpuCount()
        If onlineCores = 0 Or onlineCores > MAX_SCHED_CPUS Then onlineCores = 1

        Dim coreIdx As UInt32 = 0
        While coreIdx < onlineCores
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(coreLocks(coreIdx))

            ' Search GPOS queue
            Dim headAddr As UInt64 = gposQueueHeads(coreIdx)
            If headAddr <> 0 Then
                Dim iterAddr As UInt64 = headAddr
                Do
                    Dim iter As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, iterAddr)
                    If iter.Id = targetPid Then
                        If iter.State = Sched.ThreadState.STATE_BLOCKED Then
                            iter.State = Sched.ThreadState.STATE_READY
                            iter.WakeUptime = 0
                            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(coreIdx), flags
                            WakeTask = True
                            Exit Function
                        End If
                    End If
                    iterAddr = iter.NextTask
                Loop While iterAddr <> headAddr
            End If

            ' Search RTOS queue
            headAddr = rtosQueueHeads(coreIdx)
            If headAddr <> 0 Then
                Dim iterRtosAddr As UInt64 = headAddr
                Do
                    Dim iterRtos As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, iterRtosAddr)
                    If iterRtos.Id = targetPid Then
                        If iterRtos.State = Sched.ThreadState.STATE_BLOCKED Then
                            iterRtos.State = Sched.ThreadState.STATE_READY
                            iterRtos.WakeUptime = 0
                            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(coreIdx), flags
                            WakeTask = True
                            Exit Function
                        End If
                    End If
                    iterRtosAddr = iterRtos.NextTask
                Loop While iterRtosAddr <> headAddr
            End If

            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(coreIdx), flags
            coreIdx = coreIdx + 1
        Wend

        WakeTask = False
    End Function

    ''
    ' @brief Get the system uptime in milliseconds.
    ' @return Milliseconds since scheduler start.
    ''
    Public Function GetUptime() As UInt64
        GetUptime = systemUptimeMs
    End Function

    ''
    ' @brief Terminate execution of the calling task with an exit code.
    ' @param exitCode Return code passed by userspace / task.
    ''
    Public Unsafe Sub ExitCurrentTask(ByVal exitCode As UInt32)
        Dim thisCpu As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If thisCpu >= MAX_SCHED_CPUS Then thisCpu = 0

        Dim currAddr As UInt64 = currentTaskAddrs(thisCpu)
        If currAddr <> 0 Then
            Dim currTcb As Pointer To TaskControlBlock = Pointer To TaskControlBlock(currAddr)
            currTcb.ExitCode = exitCode
            currTcb.State = Sched.ThreadState.STATE_TERMINATED

            ' Record in exited tasks ring buffer
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedGlobalLock)
            Dim slot As UInt32 = exitedCount Mod 64
            exitedPids(slot) = currTcb.Id
            exitedCodes(slot) = exitCode
            exitedCount = exitedCount + 1
            Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, flags

            Serial.PrintF "[SCHED] PID %u exited with code %u. Recorded.\r\n", UInt32(currTcb.Id), exitCode
        End If
        Yield
    End Sub

    ''
    ' @brief Query the termination status and exit code of a process.
    ' @param pid Process ID to query.
    ' @param outExitCode ByRef variable receiving the process exit code.
    ' @return 0 if process has exited, 1 if process is still running, -1 if process was not found.
    ''
    Public Unsafe Function GetProcessExitStatus(ByVal pid As UInt64, ByRef outExitCode As UInt32) As Int32
        If pid = 0 Then
            GetProcessExitStatus = -1
            Exit Function
        End If

        ' 1. Check exited tasks ring buffer under schedGlobalLock
        Dim gFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedGlobalLock)
        Dim i As UInt32 = 0
        While i < 64
            If exitedPids(i) = pid Then
                outExitCode = exitedCodes(i)
                Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, gFlags
                GetProcessExitStatus = 0 ' Exited
                Exit Function
            End If
            i = i + 1
        Wend
        Sync.SpinlockOps.ReleaseIrqRestore schedGlobalLock, gFlags

        ' 2. Check if process is still active in any core's runqueue
        Dim onlineCores As UInt32 = Arch.Acpi.GetCpuCount()
        If onlineCores = 0 Or onlineCores > MAX_SCHED_CPUS Then onlineCores = 1

        Dim c As UInt32 = 0
        While c < onlineCores
            Dim cFlags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(coreLocks(c))
            Dim headAddr As UInt64 = gposQueueHeads(c)
            If headAddr <> 0 Then
                Dim iterAddr As UInt64 = headAddr
                Do
                    Dim iter As Pointer To TaskControlBlock = Pointer To TaskControlBlock(iterAddr)
                    If iter.Id = pid Then
                        If iter.State = Sched.ThreadState.STATE_TERMINATED Then
                            outExitCode = iter.ExitCode
                            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(c), cFlags
                            GetProcessExitStatus = 0
                            Exit Function
                        Else
                            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(c), cFlags
                            GetProcessExitStatus = 1 ' Still running
                            Exit Function
                        End If
                    End If
                    iterAddr = iter.NextTask
                Loop While iterAddr <> headAddr
            End If
            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(c), cFlags
            c = c + 1
        Wend

        GetProcessExitStatus = -1 ' Not found
    End Function

    ''
    ' @brief Reclaim resources of any terminated tasks (zombies) in runqueues.
    '        Safely frees stack and TCB memory for tasks that called SYS_PROCESS_EXIT.
    ''
    Public Unsafe Sub ReapTerminatedTasks()
        Dim c As UInt32
        For c = 0 To MAX_SCHED_CPUS - 1
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(coreLocks(c))
            Dim headAddr As UInt64 = gposQueueHeads(c)
            If headAddr <> 0 Then
                Dim prevAddr As UInt64 = headAddr
                Dim currAddr As UInt64 = headAddr
                Dim checkedCount As UInt32 = 0

                Do
                    Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currAddr)
                    Dim nextAddr As UInt64 = curr.NextTask

                    ' If task is terminated and not actively executing on any core
                    If curr.State = Sched.ThreadState.STATE_TERMINATED Then
                        Dim isExecuting As Boolean = False
                        Dim checkCore As UInt32
                        For checkCore = 0 To MAX_SCHED_CPUS - 1
                            If currentTaskAddrs(checkCore) = currAddr Then
                                isExecuting = True
                            End If
                        Next checkCore

                        If Not isExecuting Then
                            ' Mark blocked immediately so no other pass touches it
                            curr.State = Sched.ThreadState.STATE_BLOCKED

                            ' Unlink from circular list
                            If currAddr = nextAddr Then
                                gposQueueHeads(c) = 0
                            Else
                                Dim gPredAddr As UInt64 = currAddr
                                While CPtr(Pointer To TaskControlBlock, gPredAddr).NextTask <> currAddr
                                    gPredAddr = CPtr(Pointer To TaskControlBlock, gPredAddr).NextTask
                                Wend
                                CPtr(Pointer To TaskControlBlock, gPredAddr).NextTask = nextAddr
                                If gposQueueHeads(c) = currAddr Then
                                    gposQueueHeads(c) = nextAddr
                                End If
                            End If

                            Dim reapedPid As UInt32 = CType(UInt32, curr.Id)
                            Dim kstack As UInt64 = curr.KStackBase
                            Dim tcbToFree As UInt64 = currAddr

                            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(c), flags

                            Serial.PrintF "[SCHED] Reaped terminated task (PID: %u)\r\n", reapedPid

                            If kstack <> 0 Then
                                KHeap.KFree kstack
                            End If
                            KHeap.KFree tcbToFree

                            Exit Sub
                        End If
                    End If

                    prevAddr = currAddr
                    currAddr = nextAddr
                    checkedCount = checkedCount + 1
                Loop While currAddr <> headAddr And checkedCount < 64
            End If
            Sync.SpinlockOps.ReleaseIrqRestore coreLocks(c), flags
        Next c
    End Sub

End Class

End Namespace
