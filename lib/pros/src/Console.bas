' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Console.bas
' Summary: High-level Console I/O and text printing procedures for Ring 3 applications.

Import Pros.Sys.RawSyscall

Namespace Pros.IO

    Public Module Console

        ''
        ' @brief Write raw string bytes to console via SYS_CONSOLE_WRITE.
        ' @param strPtr Pointer to null-terminated ASCII string.
        ''
        Public Unsafe Sub Write(ByVal strPtr As Pointer To Byte)
            If strPtr = 0 Then Exit Sub
            Dim length As UInt64 = 0
            While strPtr(length) <> 0
                length = length + 1
            Wend
            Pros.Sys.RawSyscall.Call2 Pros.Sys.SYS_CONSOLE_WRITE, CType(UInt64, strPtr), length
        End Sub

        ''
        ' @brief Write string bytes followed by carriage return and newline atomically.
        ''
        Public Unsafe Sub WriteLine(ByVal strPtr As Pointer To Byte)
            If strPtr = 0 Then Exit Sub
            Dim lineBuf(192) As Byte
            Dim outIdx As UInt32 = 0
            While strPtr(outIdx) <> 0 And outIdx < 188
                lineBuf(outIdx) = strPtr(outIdx)
                outIdx = outIdx + 1
            Wend
            lineBuf(outIdx) = 13 ' \r
            outIdx = outIdx + 1
            lineBuf(outIdx) = 10 ' \n
            outIdx = outIdx + 1
            lineBuf(outIdx) = 0
            Pros.Sys.RawSyscall.Call2 Pros.Sys.SYS_CONSOLE_WRITE, CType(UInt64, @lineBuf(0)), outIdx
        End Sub

        ''
        ' @brief Format an unsigned 64-bit integer into a destination ASCII buffer.
        ''
        Public Unsafe Sub FormatUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte)
            If val = 0 Then
                buf(0) = 48 ' '0'
                buf(1) = 0
                Exit Sub
            End If

            Dim tmp(23) As Byte
            Dim idx As UInt32 = 0
            Dim v As UInt64 = val
            While v > 0
                tmp(idx) = CType(Byte, (v Mod 10) + 48)
                v = v / 10
                idx = idx + 1
            Wend

            Dim outIdx As UInt32 = 0
            While idx > 0
                idx = idx - 1
                buf(outIdx) = tmp(idx)
                outIdx = outIdx + 1
            Wend
            buf(outIdx) = 0
        End Sub

        ''
        ' @brief Print a compound message with an integer atomically.
        ''
        Public Unsafe Sub PrintWithUInt(ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)
            Dim lineBuf(128) As Byte
            Dim outIdx As UInt32 = 0

            Dim pIdx As UInt32 = 0
            While prefix(pIdx) <> 0 And outIdx < 96
                lineBuf(outIdx) = prefix(pIdx)
                outIdx = outIdx + 1
                pIdx = pIdx + 1
            Wend

            Dim numBuf(24) As Byte
            FormatUInt val, @numBuf(0)
            Dim nIdx As UInt32 = 0
            While numBuf(nIdx) <> 0 And outIdx < 112
                lineBuf(outIdx) = numBuf(nIdx)
                outIdx = outIdx + 1
                nIdx = nIdx + 1
            Wend

            If suffix <> 0 Then
                Dim sIdx As UInt32 = 0
                While suffix(sIdx) <> 0 And outIdx < 126
                    lineBuf(outIdx) = suffix(sIdx)
                    outIdx = outIdx + 1
                    sIdx = sIdx + 1
                Wend
            End If

            lineBuf(outIdx) = 0
            Pros.Sys.RawSyscall.Call2 Pros.Sys.SYS_CONSOLE_WRITE, CType(UInt64, @lineBuf(0)), outIdx
        End Sub

    End Module

End Namespace
