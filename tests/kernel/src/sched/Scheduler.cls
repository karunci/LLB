' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sched/Scheduler.cls
' Summary: Multitasking scheduler managing circular runqueues, priority aging,
'          and hardware context switching. Ports PRK kernel/sched.c.

Import Sync
Import Sched
Import Arch.X86_64.Gdt
Use Drivers.SerialUart As Serial
Use Mem.KernelHeap As KHeap

Namespace Sched

' External context switch and trampoline routines
Public Declare Sub switch_context(ByVal oldRspPtr As Pointer To UInt64, ByVal newRsp As UInt64, ByVal newCr3 As UInt64, ByVal lockPtr As Pointer To Sync.Spinlock)
Public Declare Sub thread_start_trampoline()

<Instancing(SingleUse)>
Public Class Scheduler

    Public Const KERNEL_STACK_SIZE As UInt32 = 4096

    Private schedLock As Sync.Spinlock
    Private masterKernelCr3 As UInt64
    Private currentTaskAddr As UInt64
    Private rtosQueueHead As UInt64
    Private gposQueueHead As UInt64
    Private idleTaskAddr As UInt64
    Private nextPid As UInt64
    Private systemUptimeMs As UInt64


    ''
    ' @brief Initialize the multitasking scheduler, create BSP boot thread and idle thread.
    '        Mirrors PRK sched_init().
    ''
    Public Unsafe Sub Initialize()
        Sync.SpinlockOps.Init schedLock
        nextPid = 1
        systemUptimeMs = 0
        currentTaskAddr = 0
        rtosQueueHead = 0
        gposQueueHead = 0
        idleTaskAddr = 0

        ' Capture initial master kernel CR3 root
        Dim currentCr3 As UInt64 = 0
        Asm "mov %%cr3, %0" : "=r"(currentCr3)
        masterKernelCr3 = currentCr3

        Serial.PrintF "[SCHED] Initializing Circular Runqueue Scheduler...\r\n"

        ' 1. Allocate and initialize Boot Task (PID 999) representing currently running KernelEntry
        Dim bootTcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If bootTcbMem = 0 Then
            Serial.PrintF "[SCHED] Fatal: Failed to allocate TCB for boot task!\r\n"
            Exit Sub
        End If

        Dim bootTask As Pointer To TaskControlBlock
        bootTask = CPtr(Pointer To TaskControlBlock, bootTcbMem)
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

        currentTaskAddr = bootTcbMem
        gposQueueHead = bootTcbMem

        ' Ensure TSS RSP0 points to the boot thread stack top
        Dim bootKstackTop As UInt64 = bootTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)
        Arch.X86_64.Gdt.SetKernelStack bootKstackTop

        ' 2. Allocate and initialize Idle Task (PID 0)
        Dim idleTcbMem As UInt64 = KHeap.KMalloc(SizeOf(TaskControlBlock))
        If idleTcbMem = 0 Then
            Serial.PrintF "[SCHED] Fatal: Failed to allocate TCB for idle task!\r\n"
            Exit Sub
        End If

        Dim idleTask As Pointer To TaskControlBlock
        idleTask = CPtr(Pointer To TaskControlBlock, idleTcbMem)
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

        ' Setup synthetic execution stack for Idle Task
        SetupSyntheticStack idleTask, @Sched.TaskRoutines.CpuIdleLoop

        idleTaskAddr = idleTcbMem

        Serial.PrintF "[SCHED] Scheduler active. Boot PID: %u, Idle PID: 0\r\n", CType(UInt32, bootTask.Id)
    End Sub

    ''
    ' @brief Helper to construct synthetic call frame on a thread stack for context switching.
    '        Mirrors PRK stack layout in create_kernel_thread.
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
    ' @brief Create a kernel thread and insert it into the appropriate circular runqueue.
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

        Dim thread As Pointer To TaskControlBlock
        thread = CPtr(Pointer To TaskControlBlock, tcbMem)

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

        ' Insert into circular runqueue
        flags = Sync.SpinlockOps.AcquireIrqSave(schedLock)
        If taskType = Sched.ThreadType.TYPE_RTOS Then
            If rtosQueueHead = 0 Then
                rtosQueueHead = tcbMem
                thread.NextTask = tcbMem
            Else
                Dim rHead As Pointer To TaskControlBlock
                rHead = CPtr(Pointer To TaskControlBlock, rtosQueueHead)
                thread.NextTask = rHead.NextTask
                rHead.NextTask = tcbMem
            End If
        Else
            If gposQueueHead = 0 Then
                gposQueueHead = tcbMem
                thread.NextTask = tcbMem
            Else
                Dim gHead As Pointer To TaskControlBlock
                gHead = CPtr(Pointer To TaskControlBlock, gposQueueHead)
                thread.NextTask = gHead.NextTask
                gHead.NextTask = tcbMem
            End If
        End If
        Sync.SpinlockOps.ReleaseIrqRestore schedLock, flags

        Serial.PrintF "[SCHED] Spawned Kernel Thread (PID: %u, Priority: %u)\r\n", CType(UInt32, assignedPid), priority
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
            Dim iter As Pointer To TaskControlBlock
            iter = CPtr(Pointer To TaskControlBlock, iterAddr)

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
            Dim prevTask As Pointer To TaskControlBlock
            prevTask = CPtr(Pointer To TaskControlBlock, prevAddr)
            If prevTask.State = Sched.ThreadState.STATE_READY Or prevTask.State = Sched.ThreadState.STATE_RUNNING Then
                PickNextReady = prevAddr
                Exit Function
            End If
        End If

        PickNextReady = 0
    End Function

    ''
    ' @brief Core scheduling engine performing context switch to next task.
    '        Mirrors PRK _sched_yield_internal().
    ''
    Private Unsafe Sub SchedYieldInternal(ByVal targetState As UInt32, ByVal sleepMs As UInt64)
        Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(schedLock)

        Dim prevAddr As UInt64 = currentTaskAddr
        Dim prevTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, prevAddr)

        If prevAddr <> 0 And prevTask.State = Sched.ThreadState.STATE_RUNNING Then
            prevTask.State = targetState
            If targetState = Sched.ThreadState.STATE_BLOCKED And sleepMs > 0 Then
                prevTask.WakeUptime = systemUptimeMs + sleepMs
            End If
        End If

        ' Pick next runnable task: RTOS queue first, then GPOS queue, fallback to Idle
        Dim nextAddr As UInt64 = PickNextReady(prevAddr, rtosQueueHead)
        If nextAddr = 0 Then
            nextAddr = PickNextReady(prevAddr, gposQueueHead)
        End If
        If nextAddr = 0 Then
            nextAddr = idleTaskAddr
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

        currentTaskAddr = nextAddr
        Dim nextTask As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, nextAddr)
        nextTask.State = Sched.ThreadState.STATE_RUNNING

        ' Set TSS RSP0 stack pointer to next task's kernel stack
        Dim kstackTop As UInt64 = nextTask.KStackBase + CType(UInt64, KERNEL_STACK_SIZE)
        Arch.X86_64.Gdt.SetKernelStack kstackTop

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
        systemUptimeMs = systemUptimeMs + elapsedMs
        If currentTaskAddr <> 0 Then
            Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currentTaskAddr)
            curr.CpuTicks = curr.CpuTicks + 1
        End If
        Yield
    End Sub

    ''
    ' @brief Get the currently active task ID (PID).
    ' @return Current PID or 0.
    ''
    Public Unsafe Function GetCurrentPid() As UInt64
        If currentTaskAddr = 0 Then
            GetCurrentPid = 0
            Exit Function
        End If
        Dim curr As Pointer To TaskControlBlock = CPtr(Pointer To TaskControlBlock, currentTaskAddr)
        GetCurrentPid = curr.Id
    End Function

End Class

End Namespace
