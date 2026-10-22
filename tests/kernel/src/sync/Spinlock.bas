' Project Name: Low-Level Basic Kernel / llbc
' Filename: tests/kernel/src/sync/Spinlock.bas
' Summary: Low-overhead IRQ-safe spinlock primitives optimized for x86_64 SMP.

Module Sync.SpinlockOps

    Public Structure Spinlock
        Public Locked As UInt32
    End Structure

    Public Sub Init(ByRef lock As Spinlock)
        lock.Locked = 0
    End Sub

    ' Standard atomic spinlock acquire
    Public Unsafe Sub Acquire(ByRef lock As Spinlock)
        Dim oneVal As UInt32 = 1
        Do
            Asm "xchgl %0, %1" : : "r"(oneVal), "m"(lock.Locked) : "memory"
            If lock.Locked = 1 Then
                Exit Do
            End If
            Asm "pause"
        Loop
    End Sub

    ' Release spinlock
    Public Unsafe Sub Release(ByRef lock As Spinlock)
        Dim zeroVal As UInt32 = 0
        Asm "movl %0, %1" : : "r"(zeroVal), "m"(lock.Locked) : "memory"
    End Sub

    ' IRQ-safe spinlock acquire saving RFLAGS
    Public Unsafe Function AcquireIrqSave(ByRef lock As Spinlock) As UInt64
        Dim rflags As UInt64 = 0
        Do
            ' Read-only spin check with pause hint
            Do While lock.Locked <> 0
                Asm "pause"
            Loop

            ' Capture RFLAGS into rflags variable and disable interrupts
            Asm "pushfq\n\tpopq %0\n\tcli" : "=r"(rflags) : : "memory"

            ' Attempt atomic claim
            If lock.Locked = 0 Then
                lock.Locked = 1
                AcquireIrqSave = rflags
                Exit Function
            End If

            ' Contention: restore interrupts if they were enabled
            If (rflags And &H200) <> 0 Then
                Asm "sti"
            End If
            Asm "pause"
        Loop
        AcquireIrqSave = 0
    End Function

    ' IRQ-safe spinlock release restoring RFLAGS
    Public Unsafe Sub ReleaseIrqRestore(ByRef lock As Spinlock, ByVal rflags As UInt64)
        lock.Locked = 0
        If (rflags And &H200) <> 0 Then
            Asm "sti"
        End If
    End Sub

End Module
