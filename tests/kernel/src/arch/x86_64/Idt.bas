' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Idt.bas
' Summary: 64-bit Interrupt Descriptor Table (IDT) configuration and ISR routing.

Module Arch.Idt

    Import Arch.X86_64.Apic
    Import Sched
    Use Drivers.SerialUart As Serial
    Use Sched.Scheduler As SchedEngine
    Use Mem.VirtualMemoryManager As VmmEngine
    Use Mem.BuddyAllocator As Buddy

    ' Exact 16-byte x86_64 IDT Entry Gate Descriptor
    <Packed>
    Public Structure IdtEntry
        Public BaseLow As UInt16         ' Target Offset bits 0..15
        Public Selector As UInt16        ' Code Segment Selector in GDT (0x08)
        Public Ist As Byte               ' Interrupt Stack Table offset (0 for default)
        Public TypeAttributes As Byte    ' Gate Type (0x8E = Interrupt Gate, Present, Ring 0)
        Public BaseMid As UInt16         ' Target Offset bits 16..31
        Public BaseHigh As UInt32        ' Target Offset bits 32..63
        Public Reserved As UInt32        ' Reserved (0)
    End Structure

    #Assert SizeOf(IdtEntry) = 16, "IdtEntry must be exactly 16 bytes on x86_64"

    ' IDT Pointer structure passed to 'lidt' instruction
    <Packed>
    Public Structure IdtPtr
        Public Limit As UInt16
        Public Base As Pointer To IdtEntry
    End Structure

    ' CPU Register Context pushed onto stack by hardware and isr_common_stub
    <Packed>
    Public Structure InterruptFrame
        ' Pushed by isr_common_stub
        Public R15 As UInt64
        Public R14 As UInt64
        Public R13 As UInt64
        Public R12 As UInt64
        Public R11 As UInt64
        Public R10 As UInt64
        Public R9 As UInt64
        Public R8 As UInt64
        Public Rbp As UInt64
        Public Rdi As UInt64
        Public Rsi As UInt64
        Public Rdx As UInt64
        Public Rcx As UInt64
        Public Rbx As UInt64
        Public Rax As UInt64

        ' Pushed by stub
        Public Vector As UInt64
        Public ErrorCode As UInt64

        ' Pushed automatically by CPU hardware
        Public Rip As UInt64
        Public Cs As UInt64
        Public Rflags As UInt64
        Public Rsp As UInt64
        Public Ss As UInt64
    End Structure

    ' Static IDT array (256 vectors) and IDTR pointer
    Private idtEntries(256) As IdtEntry
    Private idtr As IdtPtr

    ' Custom Function Pointer Prototype for Interrupt Handlers
    Public Delegate Sub InterruptHandler(ByRef frame As InterruptFrame)
    
    ' Dispatch table for custom handler callbacks
    Private isrHandlers(256) As Pointer To Byte

    ' Set up an individual IDT Gate Descriptor
    Public Unsafe Sub SetGate(ByVal vector As Byte, ByVal handlerAddr As Pointer To Byte, ByVal selector As UInt16, ByVal flags As Byte)
        Dim addr As UInt64
        addr = CType(UInt64, handlerAddr)

        idtEntries(vector).BaseLow = CType(UInt16, addr And &HFFFF)
        idtEntries(vector).Selector = selector
        idtEntries(vector).Ist = 0
        idtEntries(vector).TypeAttributes = flags
        idtEntries(vector).BaseMid = CType(UInt16, (addr RShift 16) And &HFFFF)
        idtEntries(vector).BaseHigh = CType(UInt32, (addr RShift 32) And &HFFFFFFFF)
        idtEntries(vector).Reserved = 0
    End Sub

    ' Register a custom LLB handler for a specific vector
    Public Unsafe Sub RegisterHandler(ByVal vector As Byte, ByVal handler As Pointer To Byte)
        isrHandlers(vector) = handler
    End Sub

    ' Central ISR Dispatcher called from isr_common_stub
    Public Unsafe Sub IsrDispatcher(ByRef frame As InterruptFrame)
        Dim vector As UInt64
        vector = frame.Vector

        ' For hardware interrupts (Vectors >= 32), send End of Interrupt (EOI)
        ' BEFORE dispatching to handlers. This is essential for preemptive multitasking
        ' so that if the handler switches context (Yield/Schedule), the Local APIC
        ' in-service register is already cleared and future timer ticks can fire.
        ' Note: Vector 255 is the APIC spurious interrupt vector; per x86 spec,
        ' no EOI should be sent for spurious interrupts.
        If vector >= 32 And vector <> 255 Then
            Arch.X86_64.Apic.SendEoi
        End If

        ' Check if a handler is registered for this vector
        If isrHandlers(vector) <> CPtr(Pointer To Byte, 0) Then
            Dim handlerFunc As InterruptHandler
            handlerFunc = CType(InterruptHandler, isrHandlers(vector))
            handlerFunc(frame)
        ElseIf vector < 32 Then
            ' CPU Exception Handler
            If vector = 14 Then
                Dim cr2Val As UInt64 = 0
                Asm "mov %%cr2, %0" : "=r"(cr2Val) : : "memory"

                ' 1. Demand Paging: Stack auto-expansion down to 0x6C000000
                If cr2Val >= &H6C000000 And cr2Val < &H70000000 Then
                    Dim pageVaddr As UInt64 = cr2Val And &HFFFFFFFFFFFFF000
                    Dim physFrame As UInt64 = Buddy.AllocPages(0)
                    If physFrame <> 0 Then
                        Dim curCr3 As UInt64 = 0
                        Asm "mov %%cr3, %0" : "=r"(curCr3) : : "memory"
                        VmmEngine.MapPage curCr3, pageVaddr, physFrame, &H07
                        Asm "invlpg (%0)" : : "r"(pageVaddr) : "memory"
                        Exit Sub ' Return cleanly and resume faulting instruction
                    End If
                End If

                ' 2. Process Isolation for Ring 3 user faults
                If (frame.Cs And 3) = 3 Then
                    Serial.PrintF "\r\n[CPU FAULT] Ring 3 User Process Fault: RIP: 0x%lx | CR2: 0x%lx | Error: 0x%x | Terminating Task Cleanly.\r\n", _
                                  frame.Rip, cr2Val, CType(UInt32, frame.ErrorCode And &HFFFFFFFF)
                    SchedEngine.ExitCurrentTask 1
                    Exit Sub
                End If

                ' Kernel Ring 0 Fault: Halt
                Serial.PrintF "\r\n[CPU EXCEPTION] Fatal Ring 0 Vector: 14 (Page Fault) | CR2: 0x%lx | Error: 0x%x | RIP: 0x%lx | CS: 0x%x | RSP: 0x%lx\r\n", _
                              cr2Val, CType(UInt32, frame.ErrorCode And &HFFFFFFFF), frame.Rip, CType(UInt32, frame.Cs), frame.Rsp
                Do
                    Asm "cli\n\thlt" : : : "memory"
                Loop
            Else
                If (frame.Cs And 3) = 3 Then
                    Serial.PrintF "\r\n[CPU FAULT] Ring 3 Exception Vector: %u | RIP: 0x%lx | Error: 0x%x | Terminating Task Cleanly.\r\n", _
                                  CType(UInt32, vector), frame.Rip, CType(UInt32, frame.ErrorCode And &HFFFFFFFF)
                    SchedEngine.ExitCurrentTask 1
                    Exit Sub
                End If
                Serial.PrintF "\r\n[CPU EXCEPTION] Fatal Vector: %u | Error: 0x%x | RIP: 0x%lx | CS: 0x%x | RSP: 0x%lx\r\n", _
                              CType(UInt32, vector), CType(UInt32, frame.ErrorCode And &HFFFFFFFF), frame.Rip, CType(UInt32, frame.Cs), frame.Rsp
                Do
                    Asm "cli\n\thlt" : : : "memory"
                Loop
            End If
        End If
    End Sub

    ' External Assembly Stub Function
    Public Declare Function get_isr_stub Lib "kernel" (ByVal vector As UInt64) As Pointer To Byte

    ' Initialize and load the IDT
    Public Unsafe Sub Initialize()
        ' Zero out handler dispatcher array
        Dim i As UInt32
        For i = 0 To 255
            isrHandlers(i) = CPtr(Pointer To Byte, 0)
        Next i

        ' Populate all 256 IDT Gates with hardened stubs from get_isr_stub
        For i = 0 To 255
            SetGate CType(Byte, i), get_isr_stub(CType(UInt64, i)), &H08, &H8E
        Next i

        ' Set up IDTR Pointer
        idtr.Limit = CType(UInt16, (256 * 16) - 1)
        idtr.Base = @idtEntries(0)

        ' Load IDT via inline assembly
        Dim ptrAddr As Pointer To IdtPtr
        ptrAddr = @idtr
        
        Asm
            "lidt (%0)"
            : : "r"(ptrAddr)
        End Asm
    End Sub

    ''
    ' @brief Reload the existing IDT pointer on the current CPU core.
    '        Mirrors PRK idt_load(). Used by AP cores during bring-up.
    ''
    Public Unsafe Sub ReloadIdt()
        Dim ptrAddr As Pointer To IdtPtr
        ptrAddr = @idtr
        Asm "lidt (%0)" : : "r"(ptrAddr) : "memory"
    End Sub

End Module