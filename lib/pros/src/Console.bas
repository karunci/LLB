' Project Name: Personal Research Operating System (PROS) / Low-Level Basic
' Filename: lib/pros/src/Console.bas
' Summary: High-level Console I/O, formatted printing, and TTY Synapse dispatch for Ring 3 applications.

Import Pros.Sys.RawSyscall
Import Pros.Nodes In "Node.bas"
Import Format In "../metal/src/Format.bas"

Namespace Pros.IO

    Public Module Console

        ' Active TTY Synapse Channel (0 = fallback to microkernel SYS_CONSOLE_WRITE)
        Private g_ttySynapseId As UInt64 = 0

        ''
        ' @brief Set the active TTY Synapse Channel for console output redirection.
        ' @param channelId Synapse channel connected to the terminal or console daemon.
        ''
        Public Sub SetTtyChannel(ByVal channelId As UInt64)
            g_ttySynapseId = channelId
        End Sub

        ''
        ' @brief Get the active TTY Synapse Channel ID.
        ' @return Synapse channel handle, or 0 if writing directly to system console.
        ''
        Public Function GetTtyChannel() As UInt64
            GetTtyChannel = g_ttySynapseId
        End Function

        ''
        ' @brief Write raw byte buffer to the active console / TTY channel.
        ' @param buf Pointer to byte array.
        ' @param count Number of bytes to transfer.
        ' @return Number of bytes written.
        ''
        Public Unsafe Function WriteBytes(ByVal buf As Pointer To Byte, ByVal count As UInt64) As UInt64
            If buf = 0 Or count = 0 Then
                WriteBytes = 0
                Exit Function
            End If

            ' Path 1: Route to attached TTY window via Synapse IPC
            If g_ttySynapseId <> 0 Then
                Dim offset As UInt64 = 0
                While offset < count
                    Dim chunk As UInt32 = UInt32(count - offset)
                    If chunk > 255 Then chunk = 255

                    Dim pkt As Pros.Nodes.AxonPacket
                    pkt.Sequence = 0
                    pkt.PacketType = &H0501 ' MSG_TTY_WRITE
                    pkt.PayloadLength = chunk
                    pkt.SourceNode = 0
                    pkt.TargetNode = 0

                    Dim i As UInt32 = 0
                    While i < chunk
                        pkt.Payload(i) = buf(offset + UInt64(i))
                        i = i + 1
                    Wend

                    Pros.Nodes.NodeRegistry.Push g_ttySynapseId, pkt
                    offset = offset + UInt64(chunk)
                Wend
                WriteBytes = count
                Exit Function
            End If

            ' Path 2: Fallback to microkernel SYS_CONSOLE_WRITE (COM1 serial UART)
            Pros.Sys.RawSyscall.Call2 Pros.Sys.SYS_CONSOLE_WRITE, UInt64(buf), count
            WriteBytes = count
        End Function

        ''
        ' @brief Write null-terminated ASCII string to console / TTY.
        ' @param strPtr Pointer to null-terminated ASCII string.
        ''
        Public Unsafe Sub Write(ByVal strPtr As Pointer To Byte)
            If strPtr = 0 Then Exit Sub
            Dim length As UInt64 = 0
            While strPtr(length) <> 0
                length = length + 1
            Wend
            WriteBytes strPtr, length
        End Sub

        ''
        ' @brief Write string followed by carriage return and newline (\r\n) atomically.
        ' @param strPtr Pointer to null-terminated ASCII string.
        ''
        Public Unsafe Sub WriteLine(ByVal strPtr As Pointer To Byte)
            If strPtr = 0 Then Exit Sub
            Write strPtr
            Dim crlf(4) As Byte
            crlf(0) = 13 ' \r
            crlf(1) = 10 ' \n
            crlf(2) = 0
            WriteBytes Pointer To Byte(crlf), 2
        End Sub

        ''
        ' @brief Write zero-allocation formatted string with variadic arguments.
        ' @param fmt Pointer to printf-style format string.
        ' @param args Variadic format parameters.
        ' @return Number of formatted bytes written.
        ''
        Public Unsafe Function PrintF(ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
            If fmt = 0 Then
                PrintF = 0
                Exit Function
            End If
            Dim outBuf(512) As Byte
            Dim written As UInt32 = Format.SprintF(Pointer To Byte(outBuf), 512, fmt, args)
            If written > 0 Then
                WriteBytes Pointer To Byte(outBuf), UInt64(written)
            End If
            PrintF = written
        End Function

        ''
        ' @brief Format an unsigned 64-bit integer into a destination ASCII buffer.
        ''
        Public Unsafe Sub FormatUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte)
            Format.ToUInt val, buf
        End Sub

        ''
        ' @brief Print a compound message with an integer atomically.
        ''
        Public Unsafe Sub PrintWithUInt(ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)
            Dim lineBuf(256) As Byte
            Dim written As UInt32 = Format.SprintF(Pointer To Byte(lineBuf), 256, "%s%u%s", prefix, val, suffix)
            If written > 0 Then
                WriteBytes Pointer To Byte(lineBuf), UInt64(written)
            End If
        End Sub

    End Module

End Namespace
