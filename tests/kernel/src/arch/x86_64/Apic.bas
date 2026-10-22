' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Apic.bas
' Summary: Local APIC (Advanced Programmable Interrupt Controller) hardware driver.

Module Arch.X86_64.Apic

    Import Arch.X86_64.PortIO

    ' Local APIC Physical MMIO Base Address
    Public Const LAPIC_BASE_PHYS As UInt64 = &HFEE00000

    ' Standard Local APIC MMIO Register Offsets
    Public Const LAPIC_ID_REG       As UInt32 = &H020
    Public Const LAPIC_EOI_REG      As UInt32 = &H0B0
    Public Const LAPIC_SVR_REG      As UInt32 = &H0F0
    Public Const LAPIC_ICR_LOW      As UInt32 = &H300
    Public Const LAPIC_ICR_HIGH     As UInt32 = &H310
    Public Const LAPIC_TIMER_LVT    As UInt32 = &H320
    Public Const LAPIC_LVT_THERMAL  As UInt32 = &H330
    Public Const LAPIC_LVT_PERF     As UInt32 = &H340
    Public Const LAPIC_LVT_LINT0    As UInt32 = &H350
    Public Const LAPIC_LVT_LINT1    As UInt32 = &H360
    Public Const LAPIC_LVT_ERROR    As UInt32 = &H370
    Public Const LAPIC_TIMER_INIT   As UInt32 = &H380
    Public Const LAPIC_TIMER_CURR   As UInt32 = &H390
    Public Const LAPIC_TIMER_DIV    As UInt32 = &H3E0

    ' MSR Definitions
    Public Const IA32_APIC_BASE_MSR As UInt32 = &H1B
    Public Const APIC_ENABLE_BIT    As UInt64 = &H800

    ' Read 64-bit Model-Specific Register
    Public Unsafe Function RdMsr(ByVal msr As UInt32) As UInt64
        Dim lo As UInt32 = 0
        Dim hi As UInt32 = 0
        Asm "rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr) : "memory"
        Dim result As UInt64 = (CType(UInt64, hi) LShift 32) Or CType(UInt64, lo)
        RdMsr = result
    End Function

    ' Write 64-bit Model-Specific Register
    Public Unsafe Sub WrMsr(ByVal msr As UInt32, ByVal val As UInt64)
        Dim lo As UInt32 = CType(UInt32, val And &HFFFFFFFF)
        Dim hi As UInt32 = CType(UInt32, (val RShift 32) And &HFFFFFFFF)
        Asm "wrmsr" : : "c"(msr), "a"(lo), "d"(hi) : "memory"
    End Sub

    ' Read from Local APIC MMIO Register
    Public Unsafe Function LapicRead(ByVal regOffset As UInt32) As UInt32
        Dim ptr As Volatile Pointer To UInt32
        ptr = CPtr(Volatile Pointer To UInt32, LAPIC_BASE_PHYS + regOffset)
        LapicRead = ptr(0)
    End Function

    ' Write to Local APIC MMIO Register
    Public Unsafe Sub LapicWrite(ByVal regOffset As UInt32, ByVal val As UInt32)
        Dim ptr As Volatile Pointer To UInt32
        ptr = CPtr(Volatile Pointer To UInt32, LAPIC_BASE_PHYS + regOffset)
        ptr(0) = val
    End Sub

    ' Send End of Interrupt (EOI) signal to LAPIC
    Public Unsafe Sub SendEoi()
        LapicWrite LAPIC_EOI_REG, 0
    End Sub

    ' Remap and mask legacy 8259 PIC to prevent ghost vector 0 interrupts
    Public Unsafe Sub DisableLegacyPic()
        ' ICW1: Begin initialization sequence
        Arch.X86_64.PortIO.OutB &H20, &H11
        Arch.X86_64.PortIO.IoWait
        Arch.X86_64.PortIO.OutB &HA0, &H11
        Arch.X86_64.PortIO.IoWait

        ' ICW2: Remap IRQ bases out of CPU exception range (Master -> 32, Slave -> 40)
        Arch.X86_64.PortIO.OutB &H21, &H20
        Arch.X86_64.PortIO.IoWait
        Arch.X86_64.PortIO.OutB &HA1, &H28
        Arch.X86_64.PortIO.IoWait

        ' ICW3: Cascade setup
        Arch.X86_64.PortIO.OutB &H21, &H04
        Arch.X86_64.PortIO.IoWait
        Arch.X86_64.PortIO.OutB &HA1, &H02
        Arch.X86_64.PortIO.IoWait

        ' ICW4: 8086 mode
        Arch.X86_64.PortIO.OutB &H21, &H01
        Arch.X86_64.PortIO.IoWait
        Arch.X86_64.PortIO.OutB &HA1, &H01
        Arch.X86_64.PortIO.IoWait

        ' Mask all lines on both 8259 PICs
        Arch.X86_64.PortIO.OutB &H21, &HFF
        Arch.X86_64.PortIO.OutB &HA1, &HFF
    End Sub

    ' Get the LAPIC ID of the current core
    Public Unsafe Function GetLapicId() As UInt32
        Dim idReg As UInt32 = LapicRead(LAPIC_ID_REG)
        GetLapicId = (idReg RShift 24) And &HFF
    End Function

    ' Initialize Local APIC on BSP core
    Public Unsafe Sub Initialize()
        ' Disable old legacy 8259 PIC
        DisableLegacyPic

        ' Ensure APIC is enabled in IA32_APIC_BASE MSR
        Dim apicBase As UInt64 = RdMsr(IA32_APIC_BASE_MSR)
        apicBase = apicBase Or APIC_ENABLE_BIT
        WrMsr IA32_APIC_BASE_MSR, apicBase

        ' Software enable Local APIC + Set Spurious Interrupt Vector to 255 (0xFF | 0x100)
        LapicWrite LAPIC_SVR_REG, &H1FF

        ' Mask all Local Vector Table (LVT) entries initially to prevent spurious traps
        LapicWrite LAPIC_LVT_THERMAL, &H10000
        LapicWrite LAPIC_LVT_PERF,    &H10000
        LapicWrite LAPIC_LVT_LINT0,   &H10000
        LapicWrite LAPIC_LVT_LINT1,   &H10000
        LapicWrite LAPIC_LVT_ERROR,   &H10000
    End Sub

    ' Initialize Local APIC Periodic Timer (Vector 32)
    Public Unsafe Sub InitializeTimer(ByVal divideVal As UInt32, ByVal initCount As UInt32)
        ' Set timer divide configuration
        LapicWrite LAPIC_TIMER_DIV, divideVal

        ' Vector 32 (0x20) in periodic mode (bit 17 = 0x20000)
        LapicWrite LAPIC_TIMER_LVT, 32 Or &H20000

        ' Initial tick counter
        LapicWrite LAPIC_TIMER_INIT, initCount
    End Sub

End Module
