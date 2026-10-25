' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/IoApic.bas
' Summary: I/O APIC (Input/Output APIC) hardware redirection controller.

Module Arch.X86_64.IoApic

    ' Standard Physical MMIO Base Address for I/O APIC
    Public Const IOAPIC_BASE_PHYS As UInt64 = &HFEC00000

    ' I/O APIC Direct MMIO Register Offsets
    Public Const IOREGSEL As UInt32 = &H00
    Public Const IOWIN    As UInt32 = &H10

    ' Standard Hardware IRQ Mappings
    Public Const IRQ_TIMER    As Byte = 0
    Public Const IRQ_KEYBOARD As Byte = 1
    Public Const IRQ_COM2     As Byte = 3
    Public Const IRQ_COM1     As Byte = 4
    Public Const IRQ_MOUSE    As Byte = 12

    ' Write to indexed I/O APIC register
    Public Unsafe Sub WriteReg(ByVal reg As UInt32, ByVal val As UInt32)
        Dim selPtr As Volatile Pointer To UInt32
        selPtr = CPtr(Volatile Pointer To UInt32, IOAPIC_BASE_PHYS + IOREGSEL)
        selPtr(0) = reg

        Dim winPtr As Volatile Pointer To UInt32
        winPtr = CPtr(Volatile Pointer To UInt32, IOAPIC_BASE_PHYS + IOWIN)
        winPtr(0) = val
    End Sub

    ' Read from indexed I/O APIC register
    Public Unsafe Function ReadReg(ByVal reg As UInt32) As UInt32
        Dim selPtr As Volatile Pointer To UInt32
        selPtr = CPtr(Volatile Pointer To UInt32, IOAPIC_BASE_PHYS + IOREGSEL)
        selPtr(0) = reg

        Dim winPtr As Volatile Pointer To UInt32
        winPtr = CPtr(Volatile Pointer To UInt32, IOAPIC_BASE_PHYS + IOWIN)
        ReadReg = winPtr(0)
    End Function

    ' Map hardware IRQ line to IDT interrupt vector on target CPU
    Public Unsafe Sub MapIrq(ByVal irq As Byte, ByVal vector As Byte, ByVal targetCpu As UInt32, ByVal isMasked As Boolean)
        Dim regLow As UInt32 = CType(UInt32, vector)
        If isMasked Then
            regLow = regLow Or &H10000 ' Bit 16: Masked
        End If

        Dim regHigh As UInt32 = targetCpu LShift 24 ' Destination LAPIC ID

        Dim regOffset As UInt32 = &H10 + (CType(UInt32, irq) * 2)
        WriteReg regOffset, regLow
        WriteReg regOffset + 1, regHigh
    End Sub

    ' Unmask IRQ line
    Public Unsafe Sub UnmaskIrq(ByVal irq As Byte)
        Dim regOffset As UInt32 = &H10 + (CType(UInt32, irq) * 2)
        Dim regLow As UInt32 = ReadReg(regOffset)
        regLow = regLow And (Not &H10000)
        WriteReg regOffset, regLow
    End Sub

    ' Mask IRQ line
    Public Unsafe Sub MaskIrq(ByVal irq As Byte)
        Dim regOffset As UInt32 = &H10 + (CType(UInt32, irq) * 2)
        Dim regLow As UInt32 = ReadReg(regOffset)
        regLow = regLow Or &H10000
        WriteReg regOffset, regLow
    End Sub

    ' Initialize I/O APIC by masking all 24 hardware redirection table entries
    Public Unsafe Sub Initialize()
        Dim i As Byte
        For i = 0 To 23
            ' Set dummy vector 255 (0xFF) while masked to prevent ghost vector 0 warnings in hypervisors
            Dim regOffset As UInt32 = &H10 + (CType(UInt32, i) * 2)
            WriteReg regOffset, &H100FF ' Masked (bit 16) | Vector 255
            WriteReg regOffset + 1, 0
        Next i
    End Sub

    ' Route PS/2 keyboard IRQ 1 to IDT vector 33 on CPU 0
    Public Unsafe Sub EnableKeyboard()
        MapIrq IRQ_KEYBOARD, 33, 0, False
    End Sub

    ' Route PS/2 mouse IRQ 12 to IDT vector 44 on CPU 0
    Public Unsafe Sub EnableMouse()
        MapIrq IRQ_MOUSE, 44, 0, False
    End Sub

End Module
