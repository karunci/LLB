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

    ''
    ' @brief Query the 12-character CPU vendor string into a caller-provided buffer (min 16 bytes).
    ' @param outBuf Pointer to destination buffer.
    ''
    Public Unsafe Sub GetVendor(ByVal outBuf As Pointer To Byte)
        If outBuf = 0 Then Exit Sub
        Dim eax As UInt32 = 0
        Dim ebx As UInt32 = 0
        Dim ecx As UInt32 = 0
        Dim edx As UInt32 = 0
        Cpuid 0, eax, ebx, ecx, edx

        Dim vPtr As Volatile Pointer To UInt32
        vPtr = CPtr(Volatile Pointer To UInt32, CType(UInt64, outBuf))
        vPtr(0) = ebx
        vPtr(1) = edx
        vPtr(2) = ecx
        outBuf(12) = 0
    End Sub

    ''
    ' @brief Query the CPU model brand string into a caller-provided buffer (min 64 bytes).
    ' @param outBuf Pointer to destination buffer.
    ''
    Public Unsafe Sub GetBrand(ByVal outBuf As Pointer To Byte)
        If outBuf = 0 Then Exit Sub
        Dim eax As UInt32 = 0
        Dim ebx As UInt32 = 0
        Dim ecx As UInt32 = 0
        Dim edx As UInt32 = 0
        Cpuid &H80000000, eax, ebx, ecx, edx
        If eax >= &H80000004 Then
            Dim bPtr As Volatile Pointer To UInt32
            bPtr = CPtr(Volatile Pointer To UInt32, CType(UInt64, outBuf))

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

            outBuf(48) = 0

            ' Skip leading spaces commonly prepended by CPUID brand strings
            Dim s As UInt32 = 0
            While outBuf(s) = 32 And s < 48
                s = s + 1
            Wend
            If s > 0 Then
                Dim k As UInt32 = 0
                While (s + k) < 48 And outBuf(s + k) <> 0
                    outBuf(k) = outBuf(s + k)
                    k = k + 1
                Wend
                outBuf(k) = 0
            End If
        Else
            outBuf(0) = 0
        End If
    End Sub

    ''
    ' @brief Query human-readable CPU feature flags into a caller-provided buffer.
    ' @param outBuf Pointer to destination buffer.
    ' @param maxLen Maximum bytes available in destination buffer.
    ''
    Public Unsafe Sub GetFeatures(ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32)
        If outBuf = 0 Or maxLen < 32 Then Exit Sub
        Dim eax As UInt32 = 0
        Dim ebx As UInt32 = 0
        Dim ecx As UInt32 = 0
        Dim edx As UInt32 = 0
        Cpuid 1, eax, ebx, ecx, edx

        Dim p As UInt32 = 0
        If (edx And 1) <> 0 Then
            outBuf(p) = 70 : outBuf(p+1) = 80 : outBuf(p+2) = 85 : outBuf(p+3) = 32 : p = p + 4 ' "FPU "
        End If
        If (edx And &H200) <> 0 Then
            outBuf(p) = 65 : outBuf(p+1) = 80 : outBuf(p+2) = 73 : outBuf(p+3) = 67 : outBuf(p+4) = 32 : p = p + 5 ' "APIC "
        End If
        If (edx And &H2000000) <> 0 Then
            outBuf(p) = 83 : outBuf(p+1) = 83 : outBuf(p+2) = 69 : outBuf(p+3) = 32 : p = p + 4 ' "SSE "
        End If
        If (edx And &H4000000) <> 0 Then
            outBuf(p) = 83 : outBuf(p+1) = 83 : outBuf(p+2) = 69 : outBuf(p+3) = 50 : outBuf(p+4) = 32 : p = p + 5 ' "SSE2 "
        End If
        If (ecx And 1) <> 0 Then
            outBuf(p) = 83 : outBuf(p+1) = 83 : outBuf(p+2) = 69 : outBuf(p+3) = 51 : outBuf(p+4) = 32 : p = p + 5 ' "SSE3 "
        End If
        If (ecx And &H200000) <> 0 Then
            outBuf(p) = 120 : outBuf(p+1) = 50 : outBuf(p+2) = 65 : outBuf(p+3) = 80 : outBuf(p+4) = 73 : outBuf(p+5) = 67 : outBuf(p+6) = 32 : p = p + 7 ' "x2APIC "
        End If
        If (ecx And &H10000000) <> 0 Then
            outBuf(p) = 65 : outBuf(p+1) = 86 : outBuf(p+2) = 88 : outBuf(p+3) = 32 : p = p + 4 ' "AVX "
        End If
        If p > 0 And outBuf(p - 1) = 32 Then p = p - 1
        outBuf(p) = 0
    End Sub

End Class

End Namespace
