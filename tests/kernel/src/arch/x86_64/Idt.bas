' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Idt.bas
' Summary: 64-bit Interrupt Descriptor Table (IDT) configuration and ISR routing.

Module Arch.Idt

    Import Arch.X86_64.Apic

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

        ' For timer interrupts (Vector 32) which trigger preemptive rescheduling and context switches,
        ' send EOI to the Local APIC immediately before the handler executes. This ensures the APIC
        ' In-Service Register (ISR) bit and Processor Priority Register (PPR) are cleared, preventing
        ' keyboard (Vector 33) and mouse (Vector 44) interrupts from being hardware-blocked!
        If vector = 32 Then
            Arch.X86_64.Apic.SendEoi
        End If

        ' Check if a handler is registered for this vector
        If isrHandlers(vector) <> CPtr(Pointer To Byte, 0) Then
            Dim handlerFunc As InterruptHandler
            handlerFunc = CType(InterruptHandler, isrHandlers(vector))
            handlerFunc(frame)
        Else
            ' Unhandled Interrupt Warning output to VGA Memory
            Dim vga As Pointer To UInt16
            vga = CPtr(Pointer To UInt16, &HB8000)
            
            ' Render "UNHANDLED INT" indicator at top right corner
            vga(78) = CType(UInt16, 85) Or CType(UInt16, &H4F00) ' 'U' in Red
            vga(79) = CType(UInt16, 73) Or CType(UInt16, &H4F00) ' 'I' in Red
        End If

        ' Send End of Interrupt (EOI) for all other hardware interrupts (Vectors > 32)
        If vector > 32 Then
            Arch.X86_64.Apic.SendEoi
        End If
    End Sub

    ' External Assembly Stub Symbols
    Public Declare Sub isr_stub_0()
    Public Declare Sub isr_stub_13()
    Public Declare Sub isr_stub_14()
    Public Declare Sub isr_stub_32()
    Public Declare Sub isr_stub_33()
    Public Declare Sub isr_stub_44()

    ' Initialize and load the IDT
    Public Unsafe Sub Initialize()
        ' Zero out handler dispatcher array
        Dim i As UInt32
        For i = 0 To 255
            isrHandlers(i) = CPtr(Pointer To Byte, 0)
        Next i

        ' Bind Stubs to IDT Vectors (0x08 = Kernel Code Segment, 0x8E = Interrupt Gate)
        SetGate 0, @isr_stub_0, &H08, &H8E    ' Vector 0: Divide Error
        SetGate 13, @isr_stub_13, &H08, &H8E  ' Vector 13: General Protection Fault
        SetGate 14, @isr_stub_14, &H08, &H8E  ' Vector 14: Page Fault
        SetGate 32, @isr_stub_32, &H08, &H8E  ' Vector 32: Timer Interrupt
        SetGate 33, @isr_stub_33, &H08, &H8E  ' Vector 33: Keyboard Interrupt
        SetGate 44, @isr_stub_44, &H08, &H8E  ' Vector 44: PS/2 Mouse Interrupt

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