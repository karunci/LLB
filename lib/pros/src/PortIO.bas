' Project Name: LibPROS / Low-Level Basic
' Filename: lib/pros/src/PortIO.bas
' Summary: Microkernel-arbitrated hardware port I/O primitives for Ring 3 drivers.

Import Pros.Sys
Import Pros.Sys.RawSyscall

Namespace Pros.IO

    Public Module Port

        ''
        ' @brief Read 8-bit byte from I/O port via microkernel SYS_PORT_IN.
        ''
        Public Unsafe Function In8(ByVal port As UInt16) As Byte
            In8 = Byte(Pros.Sys.RawSyscall.Call2(SYS_PORT_IN, UInt64(port), 1) And &HFF)
        End Function

        ''
        ' @brief Read 16-bit word from I/O port via microkernel SYS_PORT_IN.
        ''
        Public Unsafe Function In16(ByVal port As UInt16) As UInt16
            In16 = UInt16(Pros.Sys.RawSyscall.Call2(SYS_PORT_IN, UInt64(port), 2) And &HFFFF)
        End Function

        ''
        ' @brief Read 32-bit dword from I/O port via microkernel SYS_PORT_IN.
        ''
        Public Unsafe Function In32(ByVal port As UInt16) As UInt32
            In32 = UInt32(Pros.Sys.RawSyscall.Call2(SYS_PORT_IN, UInt64(port), 4) And &HFFFFFFFF)
        End Function

        ''
        ' @brief Write 8-bit byte to I/O port via microkernel SYS_PORT_OUT.
        ''
        Public Unsafe Sub Out8(ByVal port As UInt16, ByVal val As Byte)
            Pros.Sys.RawSyscall.Call3 SYS_PORT_OUT, UInt64(port), 1, UInt64(val)
        End Sub

        ''
        ' @brief Write 16-bit word to I/O port via microkernel SYS_PORT_OUT.
        ''
        Public Unsafe Sub Out16(ByVal port As UInt16, ByVal val As UInt16)
            Pros.Sys.RawSyscall.Call3 SYS_PORT_OUT, UInt64(port), 2, UInt64(val)
        End Sub

        ''
        ' @brief Write 32-bit dword to I/O port via microkernel SYS_PORT_OUT.
        ''
        Public Unsafe Sub Out32(ByVal port As UInt16, ByVal val As UInt32)
            Pros.Sys.RawSyscall.Call3 SYS_PORT_OUT, UInt64(port), 4, UInt64(val)
        End Sub

    End Module

End Namespace
