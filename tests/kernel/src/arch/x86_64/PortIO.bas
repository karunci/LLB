' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/PortIO.bas
' Summary: Low-level x86_64 port I/O primitives and CPU execution control.

Module Arch.X86_64.PortIO

    ' Byte-level port input (inb)
        Public Unsafe Function InB(ByVal port As UInt16) As Byte
            Dim result As Byte = 0
            Asm "inb %1, %0" : "=a"(result) : "Nd"(port) : "memory"
            InB = result
        End Function

        ' Byte-level port output (outb)
        Public Unsafe Sub OutB(ByVal port As UInt16, ByVal val As Byte)
            Asm "outb %0, %1" : : "a"(val), "Nd"(port) : "memory"
        End Sub

        ' Word-level port input (inw)
        Public Unsafe Function InW(ByVal port As UInt16) As UInt16
            Dim result As UInt16 = 0
            Asm "inw %1, %0" : "=a"(result) : "Nd"(port) : "memory"
            InW = result
        End Function

        ' Word-level port output (outw)
        Public Unsafe Sub OutW(ByVal port As UInt16, ByVal val As UInt16)
            Asm "outw %0, %1" : : "a"(val), "Nd"(port) : "memory"
        End Sub

        ' 32-bit dword port input (inl)
        Public Unsafe Function InL(ByVal port As UInt16) As UInt32
            Dim result As UInt32 = 0
            Asm "inl %1, %0" : "=a"(result) : "Nd"(port) : "memory"
            InL = result
        End Function

        ' 32-bit dword port output (outl)
        Public Unsafe Sub OutL(ByVal port As UInt16, ByVal val As UInt32)
            Asm "outl %0, %1" : : "a"(val), "Nd"(port) : "memory"
        End Sub

        ' Small I/O bus delay via POST diagnostics port 0x80
        Public Unsafe Sub IoWait()
            OutB &H80, 0
        End Sub

        ' CPU execution halt
        Public Unsafe Sub Hlt()
            Asm "hlt"
        End Sub

        ' Disable CPU hardware interrupts
        Public Unsafe Sub Cli()
            Asm "cli"
        End Sub

        ' Enable CPU hardware interrupts
    Public Unsafe Sub Sti()
        Asm "sti"
    End Sub

    ' Read CR2 register (Page Fault Linear Address)
    Public Unsafe Function ReadCr2() As UInt64
        Dim val As UInt64 = 0
        Asm "mov %%cr2, %0" : "=r"(val) : : "memory"
        ReadCr2 = val
    End Function

    ' Read CR3 register (PML4 base address)
    Public Unsafe Function ReadCr3() As UInt64
        Dim val As UInt64 = 0
        Asm "mov %%cr3, %0" : "=r"(val) : : "memory"
        ReadCr3 = val
    End Function

    ' Write CR3 register (Switch address space / flush TLB)
    Public Unsafe Sub WriteCr3(ByVal val As UInt64)
        Asm "mov %0, %%cr3" : : "r"(val) : "memory"
    End Sub

    ' Invalidate TLB entry for a virtual page (invlpg)
    Public Unsafe Sub Invlpg(ByVal virtAddr As UInt64)
        Asm "invlpg (%0)" : : "r"(virtAddr) : "memory"
    End Sub

End Module
