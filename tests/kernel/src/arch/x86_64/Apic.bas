' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Apic.bas
' Summary: Local APIC driver with x2APIC CPUID detection.
'          Matches PRK apic.c: upgrades from MMIO to MSR interface when CPUID ECX bit 21 is set.

Module Arch.X86_64.Apic

    Import Arch.X86_64.PortIO
    Use Drivers.SerialUart As Serial

    ' Local APIC Physical MMIO Base Address
    Public Const LAPIC_BASE_PHYS As UInt64 = &HFEE00000

    ' x2APIC MSR base (register offset >> 4 + 0x800)
    Public Const X2APIC_MSR_BASE As UInt32 = &H800

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
    Public Const IA32_APIC_BASE_MSR  As UInt32 = &H1B
    Public Const APIC_ENABLE_BIT     As UInt64 = &H800
    Public Const APIC_X2APIC_ENABLE  As UInt64 = &H400  ' Bit 10

    ' Runtime flag: True when x2APIC MSR mode is active
    Private x2ApicActive As Boolean = False

    ' Calibrated ticks for 10ms (100 Hz) tick rate
    Private calibratedTickCount As UInt32 = 0

    ''
    ' @brief Check whether Local APIC is currently in x2APIC (MSR) mode.
    ' @return True if x2APIC active, False if legacy MMIO mode.
    ''
    Public Function IsX2Apic() As Boolean
        IsX2Apic = x2ApicActive
    End Function

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

    ''
    ' @brief Read a LAPIC register. Routes through MSR in x2APIC mode, MMIO otherwise.
    ' @param regOffset Standard LAPIC register offset (e.g. 0x020 for ID).
    ' @return Register value.
    ''
    Public Unsafe Function LapicRead(ByVal regOffset As UInt32) As UInt32
        If x2ApicActive Then
            LapicRead = CType(UInt32, RdMsr(X2APIC_MSR_BASE + (regOffset RShift 4)))
        Else
            Dim ptr As Volatile Pointer To UInt32
            ptr = CPtr(Volatile Pointer To UInt32, LAPIC_BASE_PHYS + CType(UInt64, regOffset))
            LapicRead = ptr(0)
        End If
    End Function

    ''
    ' @brief Write a LAPIC register. Routes through MSR in x2APIC mode, MMIO otherwise.
    ' @param regOffset Standard LAPIC register offset.
    ' @param val       Value to write.
    ''
    Public Unsafe Sub LapicWrite(ByVal regOffset As UInt32, ByVal val As UInt32)
        If x2ApicActive Then
            WrMsr X2APIC_MSR_BASE + (regOffset RShift 4), CType(UInt64, val)
        Else
            Dim ptr As Volatile Pointer To UInt32
            ptr = CPtr(Volatile Pointer To UInt32, LAPIC_BASE_PHYS + CType(UInt64, regOffset))
            ptr(0) = val
        End If
    End Sub

    ' Send End of Interrupt (EOI) to LAPIC
    Public Unsafe Sub SendEoi()
        If x2ApicActive Then
            WrMsr X2APIC_MSR_BASE + &H0B, 0   ' EOI MSR offset 0xB0 >> 4 = 0x0B
        Else
            LapicWrite LAPIC_EOI_REG, 0
        End If
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

    ''
    ' @brief Get the Local APIC ID of the current core.
    '        x2APIC mode returns full 32-bit ID; MMIO mode shifts bits 31:24.
    ''
    Public Unsafe Function GetLapicId() As UInt32
        If x2ApicActive Then
            GetLapicId = LapicRead(LAPIC_ID_REG)  ' x2APIC: full 32-bit ID
        Else
            GetLapicId = (LapicRead(LAPIC_ID_REG) RShift 24) And &HFF
        End If
    End Function

    ''
    ' @brief Send an Inter-Processor Interrupt (IPI).
    '        In x2APIC mode, writes 64-bit MSR 0x830 (destination APIC ID in bits 63:32, command in bits 31:0).
    '        In MMIO mode, polls delivery status, writes target ID to 0x310, and flags to 0x300.
    '        Mirrors PRK lapic_send_ipi().
    ' @param targetApicId Physical APIC ID of destination core.
    ' @param vectorFlags  ICR command flags (delivery mode, vector, assert).
    ''
    Public Unsafe Sub SendIpi(ByVal targetApicId As UInt32, ByVal vectorFlags As UInt32)
        If x2ApicActive Then
            Dim icr As UInt64 = (CType(UInt64, targetApicId) LShift 32) Or CType(UInt64, vectorFlags)
            WrMsr X2APIC_MSR_BASE + &H30, icr
        Else
            Dim timeout As UInt32 = 100000
            While ((LapicRead(&H300) And &H1000) <> 0) And timeout > 0
                Asm "pause" : : : "memory"
                timeout = timeout - 1
            Wend
            LapicWrite &H310, targetApicId LShift 24
            LapicWrite &H300, vectorFlags
        End If
    End Sub

    ''
    ' @brief Initialize Local APIC on BSP core.
    '        Detects x2APIC via CPUID ECX bit 21 (mirrors PRK apic_init).
    '        Upgrades from MMIO to MSR interface if x2APIC is supported.
    ''
    Public Unsafe Sub Initialize()
        ' Disable legacy 8259 PIC first
        DisableLegacyPic

        ' CPUID leaf 1: check ECX bit 21 for x2APIC support
        Dim cpuEax As UInt32 = 0
        Dim cpuEbx As UInt32 = 0
        Dim cpuEcx As UInt32 = 0
        Dim cpuEdx As UInt32 = 0
        Asm "cpuid" : "=a"(cpuEax), "=b"(cpuEbx), "=c"(cpuEcx), "=d"(cpuEdx) : "0"(CType(UInt32, 1)) : "memory"

        Dim apicBase As UInt64 = RdMsr(IA32_APIC_BASE_MSR)

        If (cpuEcx And &H200000) <> 0 Then
            ' x2APIC supported: enable both APIC enable (bit 11) and x2APIC (bit 10)
            apicBase = apicBase Or APIC_ENABLE_BIT Or APIC_X2APIC_ENABLE
            WrMsr IA32_APIC_BASE_MSR, apicBase
            x2ApicActive = True
            Serial.PrintF "[APIC] x2APIC detected. Using MSR interface.\r\n"
        Else
            apicBase = apicBase Or APIC_ENABLE_BIT
            WrMsr IA32_APIC_BASE_MSR, apicBase
            x2ApicActive = False
            Serial.PrintF "[APIC] x2APIC not supported. Using MMIO interface.\r\n"
        End If

        ' Software enable LAPIC + Spurious Vector 0xFF
        LapicWrite LAPIC_SVR_REG, &H1FF

        ' Mask all LVT entries to prevent stray vector 0 IRQs
        LapicWrite LAPIC_LVT_THERMAL, &H10000
        LapicWrite LAPIC_LVT_PERF,    &H10000
        LapicWrite LAPIC_LVT_LINT0,   &H10000
        LapicWrite LAPIC_LVT_LINT1,   &H10000
        LapicWrite LAPIC_LVT_ERROR,   &H10000
    End Sub

    ''
    ' @brief Calibrate LAPIC timer using PIT Channel 2 for an exact 10ms tick interval.
    '        Measures elapsed LAPIC ticks over 11932 PIT cycles (10ms at 1.193182 MHz).
    ' @return Number of LAPIC ticks per 10ms.
    ''
    Public Unsafe Function CalibrateTimer() As UInt32
        ' 1. Configure PIT Channel 2 (one-shot mode 0, 16-bit binary)
        ' Command 0xB0: Channel 2, LSB then MSB, Mode 0, Binary
        Arch.X86_64.PortIO.OutB &H43, &HB0

        ' Count = 11932 (10ms = 1193182 / 100)
        Arch.X86_64.PortIO.OutB &H42, CType(Byte, 11932 And &HFF)
        Arch.X86_64.PortIO.OutB &H42, CType(Byte, (11932 RShift 8) And &HFF)

        ' 2. Prepare PIT Channel 2 Gate on Port 0x61
        Dim p61 As Byte = Arch.X86_64.PortIO.InB(&H61)
        Arch.X86_64.PortIO.OutB &H61, (p61 And &HFC) Or &H01 ' Gate high, speaker disabled

        ' 3. Start LAPIC timer counting down from maximum (divide by 16)
        LapicWrite LAPIC_TIMER_DIV, 3
        LapicWrite LAPIC_TIMER_LVT, &H10020 ' Masked, vector 32
        LapicWrite LAPIC_TIMER_INIT, &HFFFFFFFF

        ' 4. Reset PIT gate to initiate countdown
        Arch.X86_64.PortIO.OutB &H61, Arch.X86_64.PortIO.InB(&H61) And &HFE
        Arch.X86_64.PortIO.OutB &H61, Arch.X86_64.PortIO.InB(&H61) Or &H01

        ' 5. Wait for PIT Channel 2 OUT to go HIGH (bit 5 of Port 0x61)
        Dim timeout As UInt32 = 1000000
        While ((Arch.X86_64.PortIO.InB(&H61) And &H20) = 0) And timeout > 0
            timeout = timeout - 1
        Wend

        ' 6. Read elapsed LAPIC ticks
        Dim currVal As UInt32 = LapicRead(LAPIC_TIMER_CURR)
        Dim elapsed As UInt32 = &HFFFFFFFF - currVal

        ' 7. Reset and mask PIT Channel 2 gate
        Arch.X86_64.PortIO.OutB &H61, Arch.X86_64.PortIO.InB(&H61) And &HFC

        ' Stop LAPIC one-shot timer
        LapicWrite LAPIC_TIMER_INIT, 0

        If timeout > 0 And elapsed > 1000 And elapsed < &H20000000 Then
            Serial.PrintF "[APIC] Calibrated LAPIC Timer via PIT: %u ticks per 10ms (100 Hz)\r\n", elapsed
            calibratedTickCount = elapsed
            CalibrateTimer = elapsed
        Else
            Serial.PrintF "[APIC] PIT calibration fallback: count = 0x100000\r\n"
            calibratedTickCount = &H100000
            CalibrateTimer = &H100000
        End If
    End Function

    ''
    ' @brief Get the cached calibrated tick count for 10ms.
    ''
    Public Function GetCalibratedTicks() As UInt32
        If calibratedTickCount = 0 Then calibratedTickCount = &H100000
        GetCalibratedTicks = calibratedTickCount
    End Function

    ''
    ' @brief Initialize Local APIC Periodic Timer (Vector 32).
    '        Matches PRK apic_timer_init(): divide by 16, periodic vector 32.
    ''
    Public Unsafe Sub InitializeTimer(ByVal divideVal As UInt32, ByVal initCount As UInt32)
        Dim count As UInt32 = initCount
        If count = 0 Then count = GetCalibratedTicks()

        ' Set timer divide configuration (3 = divide by 16)
        LapicWrite LAPIC_TIMER_DIV, divideVal

        ' Vector 32 (0x20) in periodic mode (bit 17 = 0x20000)
        LapicWrite LAPIC_TIMER_LVT, 32 Or &H20000

        ' Initial tick counter
        LapicWrite LAPIC_TIMER_INIT, count
    End Sub

End Module
