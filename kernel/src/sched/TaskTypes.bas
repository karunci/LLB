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

' Virtual Memory Area (VMA) entry for demand paging and lazy allocation
<Packed>
Public Structure VmaEntry
    Public StartVaddr As UInt64          ' Page-aligned start virtual address
    Public EndVaddr   As UInt64          ' Page-aligned end virtual address (exclusive)
    Public Flags      As UInt32          ' VMA permissions and properties
    Public PageCount  As UInt32          ' Number of 4 KB pages in region
End Structure

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
    Public ExitCode As UInt32            ' Exit status code on termination
    Public VmaCount As UInt32            ' Active VMA count (0..32)
    Public Vmas(32) As VmaEntry          ' Process Virtual Memory Areas for demand paging
End Structure

Public Module VmaOperations

    Public Const VMA_READ  As UInt32 = 1
    Public Const VMA_WRITE As UInt32 = 2
    Public Const VMA_EXEC  As UInt32 = 4
    Public Const VMA_ANON  As UInt32 = 8
    Public Const VMA_LAZY  As UInt32 = 16

    ''
    ' @brief Add a Virtual Memory Area to the task control block with contiguous coalescing.
    ' @param pTcb Pointer to target TaskControlBlock.
    ' @param startVaddr Page-aligned start virtual address.
    ' @param length Size in bytes (page-aligned up).
    ' @param flags VMA permission and allocation flags.
    ' @return True on success, False if VMA table is full.
    ''
    Public Unsafe Function AddVma(ByVal pTcb As Pointer To TaskControlBlock, ByVal startVaddr As UInt64, ByVal length As UInt64, ByVal flags As UInt32) As Boolean
        If pTcb = 0 Or length = 0 Then
            AddVma = False
            Exit Function
        End If

        Dim alignedStart As UInt64 = startVaddr And &HFFFFFFFFFFFFF000
        Dim pageCount As UInt64 = (length + 4095) / 4096
        Dim alignedEnd As UInt64 = alignedStart + (pageCount * 4096)

        ' Check if contiguous with an existing VMA having identical flags to coalesce
        Dim i As UInt32 = 0
        While i < pTcb.VmaCount
            If pTcb.Vmas(i).EndVaddr = alignedStart And pTcb.Vmas(i).Flags = flags Then
                pTcb.Vmas(i).EndVaddr = alignedEnd
                pTcb.Vmas(i).PageCount = pTcb.Vmas(i).PageCount + UInt32(pageCount)
                AddVma = True
                Exit Function
            ElseIf pTcb.Vmas(i).StartVaddr = alignedEnd And pTcb.Vmas(i).Flags = flags Then
                pTcb.Vmas(i).StartVaddr = alignedStart
                pTcb.Vmas(i).PageCount = pTcb.Vmas(i).PageCount + UInt32(pageCount)
                AddVma = True
                Exit Function
            End If
            i = i + 1
        Wend

        If pTcb.VmaCount >= 32 Then
            AddVma = False
            Exit Function
        End If

        Dim slot As UInt32 = pTcb.VmaCount
        pTcb.Vmas(slot).StartVaddr = alignedStart
        pTcb.Vmas(slot).EndVaddr = alignedEnd
        pTcb.Vmas(slot).Flags = flags
        pTcb.Vmas(slot).PageCount = UInt32(pageCount)
        pTcb.VmaCount = pTcb.VmaCount + 1
        AddVma = True
    End Function

    ''
    ' @brief Find the VMA containing the target virtual address.
    ' @param pTcb Pointer to target TaskControlBlock.
    ' @param vaddr Virtual address to locate.
    ' @return Pointer to VmaEntry, or 0 if not within any registered VMA.
    ''
    Public Unsafe Function FindVma(ByVal pTcb As Pointer To TaskControlBlock, ByVal vaddr As UInt64) As Pointer To VmaEntry
        If pTcb = 0 Then
            FindVma = 0
            Exit Function
        End If

        Dim i As UInt32 = 0
        While i < pTcb.VmaCount
            If vaddr >= pTcb.Vmas(i).StartVaddr And vaddr < pTcb.Vmas(i).EndVaddr Then
                FindVma = AddressOf pTcb.Vmas(i)
                Exit Function
            End If
            i = i + 1
        Wend
        FindVma = 0
    End Function

End Module

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
