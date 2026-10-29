' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
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
        Dim lockPtr As Pointer To UInt32 = CPtr(Pointer To UInt32, AddressOf lock)
        Do
            ' Read-only spin check with pause hint
            Do While lock.Locked <> 0
                Asm "pause" : : : "memory"
            Loop

            Dim prevVal As UInt32 = 0
            Asm "movl $1, %0\n\txchgl %0, (%1)" : "=&r"(prevVal) : "r"(lockPtr) : "memory"
            If prevVal = 0 Then
                Exit Do
            End If
            Asm "pause" : : : "memory"
        Loop
    End Sub

    ' Release spinlock
    Public Unsafe Sub Release(ByRef lock As Spinlock)
        lock.Locked = 0
        Asm "" : : : "memory"
    End Sub

    ' IRQ-safe spinlock acquire saving RFLAGS
    Public Unsafe Function AcquireIrqSave(ByRef lock As Spinlock) As UInt64
        Dim lockPtr As Pointer To UInt32 = CPtr(Pointer To UInt32, AddressOf lock)
        Dim rflags As UInt64 = 0
        Do
            ' Read-only spin check with pause hint
            Do While lock.Locked <> 0
                Asm "pause" : : : "memory"
            Loop

            ' Capture RFLAGS and disable interrupts
            Asm "pushfq\n\tpopq %0\n\tcli" : "=r"(rflags) : : "memory"

            ' Attempt atomic claim with early-clobber =&r
            Dim prevVal As UInt32 = 0
            Asm "movl $1, %0\n\txchgl %0, (%1)" : "=&r"(prevVal) : "r"(lockPtr) : "memory"
            If prevVal = 0 Then
                AcquireIrqSave = rflags
                Exit Function
            End If

            ' Contention: restore interrupts if they were enabled
            If (rflags And &H200) <> 0 Then
                Asm "sti" : : : "memory"
            End If
            Asm "pause" : : : "memory"
        Loop
        AcquireIrqSave = 0
    End Function

    ' IRQ-safe spinlock release restoring RFLAGS
    Public Unsafe Sub ReleaseIrqRestore(ByRef lock As Spinlock, ByVal rflags As UInt64)
        lock.Locked = 0
        Asm "" : : : "memory"
        If (rflags And &H200) <> 0 Then
            Asm "sti" : : : "memory"
        End If
    End Sub

End Module
