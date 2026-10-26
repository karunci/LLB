' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sched/TaskTypes.bas
' Summary: Task Control Block (TCB) definitions, thread execution states, and constants.
'          Ports PRK include/prk/sched.h structures.

Namespace Sched

' Execution state of a task
Public Enum ThreadState
    STATE_READY = 0
    STATE_RUNNING = 1
    STATE_BLOCKED = 2
    STATE_TERMINATED = 3
End Enum

' Task scheduling category
Public Enum ThreadType
    TYPE_RTOS = 0
    TYPE_GPOS = 1
End Enum

' Task Control Block (TCB) node
<Packed>
Public Structure TaskControlBlock
    Public Id As UInt64                  ' Process / Thread ID (PID)
    Public ParentId As UInt64            ' Parent Process ID (PPID)
    Public State As UInt32               ' ThreadState enum value
    Public TaskType As UInt32            ' ThreadType enum value
    Public Priority As UInt32            ' Scheduling priority (higher = higher urgency)
    Public WakeUptime As UInt64          ' Millisecond timestamp when task unblocks
    Public CpuTicks As UInt64            ' Active execution / waiting tick counter
    Public PendingSignals As UInt32      ' Signal bitmask
    Public Cr3Root As UInt64             ' Physical PML4 root address
    Public KStackBase As UInt64          ' Base address of allocated kernel stack
    Public ContextRsp As UInt64          ' Stack pointer saved during switch_context
    Public Rsp As UInt64                 ' Saved user or current stack pointer
    Public NextTask As UInt64            ' Pointer To TaskControlBlock (circular linked list)
End Structure

Module TaskRoutines

    ''
    ' @brief Idle loop executed when no runnable tasks remain in the runqueue.
    '        Mirrors PRK cpu_idle_loop().
    ''
    Public Unsafe Sub CpuIdleLoop()
        Do
            ' Continuously pause and wait for interrupt / rescheduling
            ' Note: nop separates sti and hlt to ensure STI interrupt shadow clears before VM exit
            Asm "sti\n\tnop\n\thlt" : : : "memory"
        Loop
    End Sub

End Module

End Namespace
