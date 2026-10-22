' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module KernelMain

    ' --- Procedural Modules ---
    Import Arch.Idt
    Import Arch.X86_64.Gdt
    Import Arch.X86_64.PortIO

    ' --- Instantiable Classes ---
    Use Drivers.Terminal
    Use Drivers.SerialUart
    Use Drivers.Keyboard
    Use Arch.X86_64.CpuContext

    ' Helper to send a character to COM1 serial port (0x3F8)
    Private Unsafe Sub WriteSerial(ByVal ch As Byte)
        Dim port As UInt16 = &H3F8
        Arch.X86_64.PortIO.OutB port, ch
    End Sub

    Private Unsafe Sub WriteSerialString(ByVal str As Pointer To Byte)
        Dim i As Int32 = 0
        Do While str(i) <> 0
            WriteSerial str(i)
            i = i + 1
        Loop
    End Sub

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize COM1 line control
        WriteSerialString CPtr(Pointer To Byte, "\r\n[PRK-OS KERNEL] Booting Low-Level Basic Kernel in QEMU!\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Multiboot Verified. Long mode active.\r\n")

        ' Initialize Serial UART COM1 driver
        Drivers.SerialUart.Initialize
        Drivers.SerialUart.WriteString CPtr(Pointer To Byte, "[UART] COM1 Driver Online!\n")

        ' Initialize GDT & TSS segment descriptors
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Initializing 64-bit GDT & TSS...\r\n")
        Arch.X86_64.Gdt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] GDT & TSS initialized successfully.\r\n")

        ' Initialize PS/2 Keyboard controller
        Drivers.Keyboard.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] PS/2 Keyboard controller initialized.\r\n")

        ' Initialize VGA Terminal Driver
        Drivers.Terminal.Initialize Drivers.Terminal.COLOR_LIGHT_GREEN, Drivers.Terminal.COLOR_BLACK
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] VGA Terminal Driver initialized (&HB8000).\r\n")

        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "      PRK-OS LOW-LEVEL BASIC KERNEL      ")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteChar 10

        ' Initialize multiple MultiUse CpuContext instances on the kernel stack
        Dim bspContext As Arch.X86_64.CpuContext
        bspContext.Initialize 0, 0, &H200000

        Dim apContext As Arch.X86_64.CpuContext
        apContext.Initialize 1, 1, &H210000

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[SMP] Initialized BSP CPU ID: ")
        Drivers.Terminal.WriteHex CType(UInt64, bspContext.GetCpuId())
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, ", AP CPU ID: ")
        Drivers.Terminal.WriteHex CType(UInt64, apContext.GetCpuId())
        Drivers.Terminal.WriteChar 10
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] MultiUse CpuContext instances verified (BSP ID: 0, AP ID: 1).\r\n")

        ' Output Multiboot info address in Hex
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_CYAN
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Magic: ")
        Drivers.Terminal.WriteHex CType(UInt64, magic)
        Drivers.Terminal.WriteChar 10

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Info Address: ")
        Drivers.Terminal.WriteHex CType(UInt64, mbAddress)
        Drivers.Terminal.WriteChar 10
        Drivers.Terminal.WriteChar 10

        ' Demonstrate Color Formatting
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_RED
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[ERROR] Demonstrating red text formatting.")

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_MAGENTA
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[INFO] Demonstrating magenta text formatting.")

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_BROWN
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[WARN] Demonstrating auto-scrolling terminal...")
        Drivers.Terminal.WriteChar 10

        ' Demonstrate scrolling with a few lines so the banner remains visible
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_WHITE
        Dim i As UInt32
        For i = 1 To 16
            Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Log Entry #")
            Drivers.Terminal.WriteHex CType(UInt64, i)
            Drivers.Terminal.WriteLine CPtr(Pointer To Byte, " - Terminal scrolling line test.")
        Next i

        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Initializing IDT interrupt descriptors...\r\n")
        Arch.Idt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] IDT gates registered successfully.\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Kernel execution completed successfully. Halting CPU.\r\n")

        Do
            Asm "hlt"
        Loop
    End Sub

End Module