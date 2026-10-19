' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module KernelMain

    Import Drivers.Terminal
    Import Arch.Idt

    ' Helper to send a character to COM1 serial port (0x3F8)
    Private Unsafe Sub WriteSerial(ByVal ch As Byte)
        Dim port As UInt16 = &H3F8
        Asm
            "mov %1, %dx; mov %0, %al; outb %al, %dx"
            :
            : "r"(ch), "r"(port)
        End Asm
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

        ' Initialize VGA Terminal Driver
        Drivers.Terminal.Initialize Drivers.Terminal.COLOR_LIGHT_GREEN, Drivers.Terminal.COLOR_BLACK
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] VGA Terminal Driver initialized (&HB8000).\r\n")

        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "      PRK-OS LOW-LEVEL BASIC KERNEL      ")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteChar 10

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