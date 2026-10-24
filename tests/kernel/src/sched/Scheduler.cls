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
Use Drivers.SerialUart As Serial
Use Mem.KernelHeap As KHeap

Namespace Sched

' External context switch and trampoline routines
Public Declare Sub switch_context(ByVal oldRspPtr As Pointer To UInt64, ByVal newRsp As UInt64, ByVal newCr3 As UInt64, ByVal lockPtr As Pointer To Sync.Spinlock)
Public Declare Sub thread_start_trampoline()

<Instancing(SingleUse)>
Public Class Scheduler

    Public Const KERNEL_STACK_SIZE As UInt32 = 4096
    Public Const MAX_SCHED_CPUS    As UInt32 = 16

    Private schedLock As Sync.Spinlock
    Private masterKernelCr3 As UInt64
    Private nextPid As UInt64
    Private systemUptimeMs As UInt64
    Private targetCoreIndex As UInt32

    ' Per-CPU Scheduler State (Index 0..MAX_SCHED_CPUS-1)
    Private currentTaskAddrs(15) As UInt64
    Private rtosQueueHeads(15)   As UInt64
    Private gposQueueHeads(15)   As UInt64
    Private idleTaskAddrs(15)    As UInt64

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

        ' RSP placeholder
        stack = stack - 1
        stack(0) = CType(UInt64, stack + 1)

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
        Sync.SpinlockOps.Init schedLock
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
        Next c

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
        bootTask.Priority = 10
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

        Serial.PrintF "[SCHED] AP Core #%d online: idle task ready. Enabling interrupts...\r\n", cpuId

        ' Enable hardware interrupts on AP and start cooperative yield loop
        Arch.X86_64.PortIO.Sti
        Do
            Yield
            Asm "sti\n\thlt" : : : "memory"
        Loop
    End Sub

    ''
    ' @brief Determine target core for scheduling new threads via round-robin.
    '        Mirrors PRK get_next_target_core().
    ' @return Logical CPU index to receive the new thread.
    ''
    Private Function GetNextTargetCore() As UInt32
        Dim onlineCores As UInt32 = Arch.Acpi.GetCpuCount()
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

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedLock)
        Dim assignedPid As UInt64 = nextPid
        nextPid = nextPid + 1
        Sync.SpinlockOps.ReleaseIrqRestore schedLock, flags

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

        flags = Sync.SpinlockOps.AcquireIrqSave(schedLock)
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
        Sync.SpinlockOps.ReleaseIrqRestore schedLock, flags

        Serial.PrintF "[SCHED] Spawned Kernel Thread (PID: %u, Priority: %u) assigned to Core #%d\r\n", CType(UInt32, assignedPid), priority, targetCore
        CreateKernelThread = tcbMem
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
                    If bestOtherAddr = 0 Or urgency > bestOtherUrgency Then
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
    Private Unsafe Function StealTask(ByVal thisCpu As UInt32) As UInt64
        Dim onlineCores As UInt32 = Arch.Acpi.GetCpuCount()
        If onlineCores <= 1 Then
            StealTask = 0
            Exit Function
        End If
        If onlineCores > MAX_SCHED_CPUS Then onlineCores = MAX_SCHED_CPUS

        Dim otherCore As UInt32 = 0
        While otherCore < onlineCores
            If otherCore <> thisCpu Then
                Dim headAddr As UInt64 = gposQueueHeads(otherCore)
                If headAddr <> 0 Then
                    Dim iterAddr As UInt64 = headAddr
                    Do
                        Dim iter As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, iterAddr)
                        ' Only steal tasks in STATE_READY (not currently running on the other core)
                        If iter.State = Sched.ThreadState.STATE_READY Then
                            ' Remove iter from otherCore's queue if there are multiple tasks
                            If iter.NextTask <> iterAddr Then
                                ' Find predecessor
                                Dim predAddr As UInt64 = iterAddr
                                While CPtr(Pointer To TaskControlBlock, predAddr).NextTask <> iterAddr
                                    predAddr = CPtr(Pointer To TaskControlBlock, predAddr).NextTask
                                Wend
                                CPtr(Pointer To TaskControlBlock, predAddr).NextTask = iter.NextTask
                                If gposQueueHeads(otherCore) = iterAddr Then
                                    gposQueueHeads(otherCore) = iter.NextTask
                                End If
                            Else
                                gposQueueHeads(otherCore) = 0
                            End If

                            ' Insert into thisCpu's runqueue
                            If gposQueueHeads(thisCpu) = 0 Then
                                gposQueueHeads(thisCpu) = iterAddr
                                iter.NextTask = iterAddr
                            Else
                                Dim thisHead As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, gposQueueHeads(thisCpu))
                                iter.NextTask = thisHead.NextTask
                                thisHead.NextTask = iterAddr
                            End If

                            StealTask = iterAddr
                            Exit Function
                        End If
                        iterAddr = iter.NextTask
                    Loop While iterAddr <> headAddr
                End If
            End If
            otherCore = otherCore + 1
        Wend

        StealTask = 0
    End Function

    ''
    ' @brief Core scheduling engine performing context switch to next task on calling core.
    '        Mirrors PRK _sched_yield_internal().
    ''
    Private Unsafe Sub SchedYieldInternal(ByVal targetState As UInt32, ByVal sleepMs As UInt64)
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId >= MAX_SCHED_CPUS Then coreId = 0

        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedLock)

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

        ' If local queues have no ready tasks, attempt work-stealing from peer cores
        If nextAddr = 0 Then
            nextAddr = StealTask(coreId)
        End If

        ' Fallback to dedicated Idle task for this core
        If nextAddr = 0 Then
            nextAddr = idleTaskAddrs(coreId)
        End If

        If prevAddr = nextAddr Then
            If prevAddr <> 0 Then
                If prevTask.State = Sched.ThreadState.STATE_READY Or prevTask.State = Sched.ThreadState.STATE_RUNNING Then
                    prevTask.State = Sched.ThreadState.STATE_RUNNING
                End If
            End If
            Sync.SpinlockOps.ReleaseIrqRestore schedLock, flags
            Exit Sub
        End If

        currentTaskAddrs(coreId) = nextAddr
        Dim nextTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, nextAddr)
        nextTask.State = Sched.ThreadState.STATE_RUNNING

        ' Set per-core TSS RSP0 stack pointer to next task's kernel stack
        Dim kstackTop As UInt64 = nextTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)
        Arch.X86_64.Gdt.SetKernelStackForCore coreId, kstackTop

        Dim targetCr3 As UInt64 = nextTask.Cr3Root
        If targetCr3 = 0 Then
            targetCr3 = masterKernelCr3
        End If

        ' Switch context in hardware
        switch_context @prevTask.ContextRsp, nextTask.ContextRsp, targetCr3, @schedLock

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

        systemUptimeMs = systemUptimeMs + elapsedMs
        If currentTaskAddrs(coreId) <> 0 Then
            Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currentTaskAddrs(coreId))
            curr.CpuTicks = curr.CpuTicks + 1
        End If
        Yield
    End Sub

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
    ' @brief Transition current task to STATE_BLOCKED and immediately yield CPU.
    ''
    Public Unsafe Sub BlockCurrentTask()
        SchedYieldInternal Sched.ThreadState.STATE_BLOCKED, 0
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
                            WakeTask = True
                            Exit Function
                        End If
                    End If
                    iterRtosAddr = iterRtos.NextTask
                Loop While iterRtosAddr <> headAddr
            End If

            coreIdx = coreIdx + 1
        Wend

        WakeTask = False
    End Function

End Class

End Namespace
