' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/sys/HardwareInfo.cls
' Summary: CPUID-based CPU topology and feature query module.
'          Ports PRK hwinfo.c: vendor string, brand string, feature flags, invariant TSC.

Use Drivers.SerialUart As Serial

Namespace Sys

<Instancing(SingleUse)>
Class HardwareInfo

    ' -------------------------------------------------------------------------
    ' CPUID helper: execute leaf, capture all four output registers.
    ' -------------------------------------------------------------------------

    ''
    ' @brief Execute x86 CPUID instruction for a given leaf.
    ' @param leaf   CPUID leaf number (EAX input).
    ' @param outEax Output EAX register.
    ' @param outEbx Output EBX register.
    ' @param outEcx Output ECX register.
    ' @param outEdx Output EDX register.
    ''
    Private Unsafe Sub Cpuid(ByVal leaf As UInt32, _
                              ByRef outEax As UInt32, ByRef outEbx As UInt32, _
                              ByRef outEcx As UInt32, ByRef outEdx As UInt32)
        Asm "cpuid" : "=a"(outEax), "=b"(outEbx), "=c"(outEcx), "=d"(outEdx) : "0"(leaf) : "memory"
    End Sub

    ' -------------------------------------------------------------------------
    ' Public Interface
    ' -------------------------------------------------------------------------

    ''
    ' @brief Dump CPU vendor, brand string, feature flags, and invariant TSC status to serial.
    '        Mirrors PRK hwinfo_dump_cpu().
    ''
    Public Unsafe Sub DumpCpu()
        Dim eax As UInt32 = 0
        Dim ebx As UInt32 = 0
        Dim ecx As UInt32 = 0
        Dim edx As UInt32 = 0

        ' --- Vendor String (leaf 0): EBX+EDX+ECX = 12 ASCII bytes ---
        Cpuid 0, eax, ebx, ecx, edx

        ' vendor string: 12 ASCII chars + null = 16 bytes aligned
        Dim vendor(16) As Byte
        Dim i As Int32
        For i = 0 To 15
            vendor(i) = 0
        Next i

        Dim vPtr As Volatile Pointer To UInt32
        vPtr = CPtr(Volatile Pointer To UInt32, CType(UInt64, CPtr(Pointer To Byte, vendor)))
        vPtr(0) = ebx
        vPtr(1) = edx
        vPtr(2) = ecx
        vendor(12) = 0  ' null terminator
        Serial.PrintF "[CPU] Vendor: %s\r\n", CPtr(Pointer To Byte, vendor)

        ' --- Brand String (leaves 0x80000002-4): 48 ASCII bytes ---
        Cpuid &H80000000, eax, ebx, ecx, edx
        If eax >= &H80000004 Then
            ' brand string: 48 ASCII chars + null = 49 bytes
            Dim brand(49) As Byte
            Dim bPtr As Volatile Pointer To UInt32
            bPtr = CPtr(Volatile Pointer To UInt32, CType(UInt64, CPtr(Pointer To Byte, brand)))

            Dim t0 As UInt32 = 0
            Dim t1 As UInt32 = 0
            Dim t2 As UInt32 = 0
            Dim t3 As UInt32 = 0

            Cpuid &H80000002, t0, t1, t2, t3
            bPtr(0) = t0 : bPtr(1) = t1 : bPtr(2) = t2 : bPtr(3) = t3

            Cpuid &H80000003, t0, t1, t2, t3
            bPtr(4) = t0 : bPtr(5) = t1 : bPtr(6) = t2 : bPtr(7) = t3

            Cpuid &H80000004, t0, t1, t2, t3
            bPtr(8) = t0 : bPtr(9) = t1 : bPtr(10) = t2 : bPtr(11) = t3

            brand(48) = 0
            Serial.PrintF "[CPU] Model : %s\r\n", CPtr(Pointer To Byte, brand)
        End If

        ' --- Feature Flags (leaf 1) ---
        Cpuid 1, eax, ebx, ecx, edx
        Serial.PrintF "[CPU] Features:"
        If (edx And 1) <> 0       Then Serial.PrintF " FPU"
        If (edx And &H200) <> 0   Then Serial.PrintF " APIC"
        If (edx And &H2000000) <> 0 Then Serial.PrintF " SSE"
        If (edx And &H4000000) <> 0 Then Serial.PrintF " SSE2"
        If (ecx And 1) <> 0       Then Serial.PrintF " SSE3"
        If (ecx And &H10000000) <> 0 Then Serial.PrintF " AVX"
        Serial.PrintF "\r\n"

        ' --- Invariant TSC (leaf 0x80000007 EDX bit 8) ---
        Cpuid &H80000000, eax, ebx, ecx, edx
        If eax >= &H80000007 Then
            Cpuid &H80000007, eax, ebx, ecx, edx
            If (edx And &H100) <> 0 Then
                Serial.PrintF "[CPU] Invariant TSC detected (constant-rate clock).\r\n"
            End If
        End If
    End Sub

End Class

End Namespace
