' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sched/TaskControlBlock.cls
' Summary: Task Control Block encapsulation representing a scheduled thread/process.
'          Provides accessor and setup routines for thread execution contexts.

Namespace Sched

Public Class TaskControlBlock

    Private tcbAddr As UInt64

    ''
    ' @brief Bind this instance to a raw TaskControlBlock structure pointer.
    ' @param rawTcbAddr Memory address of the underlying TaskControlBlock structure.
    ''
    Public Sub Bind(ByVal rawTcbAddr As UInt64)
        tcbAddr = rawTcbAddr
    End Sub

    ''
    ' @brief Get the underlying raw structure address.
    ' @return Address of the underlying TCB structure.
    ''
    Public Function GetAddress() As UInt64
        GetAddress = tcbAddr
    End Function

    ''
    ' @brief Get the Thread/Process ID (PID).
    ' @return Unique integer task ID.
    ''
    Public Unsafe Function GetId() As UInt64
        If tcbAddr = 0 Then
            GetId = 0
            Exit Function
        End If
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        GetId = tcbPtr.Id
    End Function

    ''
    ' @brief Get the task state.
    ' @return ThreadState integer value.
    ''
    Public Unsafe Function GetState() As UInt32
        If tcbAddr = 0 Then
            GetState = 0
            Exit Function
        End If
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        GetState = tcbPtr.State
    End Function

    ''
    ' @brief Set the task state.
    ' @param newState New ThreadState integer value.
    ''
    Public Unsafe Sub SetState(ByVal newState As UInt32)
        If tcbAddr = 0 Then Exit Sub
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        tcbPtr.State = newState
    End Sub

    ''
    ' @brief Get the task priority.
    ' @return Priority level.
    ''
    Public Unsafe Function GetPriority() As UInt32
        If tcbAddr = 0 Then
            GetPriority = 0
            Exit Function
        End If
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        GetPriority = tcbPtr.Priority
    End Function

    ''
    ' @brief Get the pointer to the next task in the circular queue.
    ' @return Address of the next TaskControlBlock structure.
    ''
    Public Unsafe Function GetNext() As UInt64
        If tcbAddr = 0 Then
            GetNext = 0
            Exit Function
        End If
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        GetNext = tcbPtr.NextTask
    End Function

    ''
    ' @brief Set the pointer to the next task in the circular queue.
    ' @param nextAddr Address of the next TaskControlBlock structure.
    ''
    Public Unsafe Sub SetNext(ByVal nextAddr As UInt64)
        If tcbAddr = 0 Then Exit Sub
        Dim tcbPtr As Pointer To TaskControlBlock
        tcbPtr = CPtr(Pointer To TaskControlBlock, tcbAddr)
        tcbPtr.NextTask = nextAddr
    End Sub

End Class

End Namespace
