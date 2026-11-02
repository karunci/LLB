' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: drivers/snd/hda/HdaDriverMain.bas
' Summary: Intel High Definition Audio (ICH6 HDA) hardware sound driver daemon.
'          Probes PCI 0x8086:0x2668, configures MMIO BAR0, initializes codec widgets
'          via Immediate Commands, establishes cyclic DMA ping-pong buffers, and
'          exposes hardware audio streaming interfaces to srv.audio over Synapse IPC.

Import "../../../include/pros.bas"

Module HdaDriverMain

    ' Intel HDA Controller Register Offsets (MMIO BAR0)
    Public Const HDA_REG_GCAP         As UInt32 = &H00
    Public Const HDA_REG_VMIN         As UInt32 = &H02
    Public Const HDA_REG_VMAJ         As UInt32 = &H03
    Public Const HDA_REG_OUTPAY       As UInt32 = &H04
    Public Const HDA_REG_INPAY        As UInt32 = &H06
    Public Const HDA_REG_GCTL         As UInt32 = &H08
    Public Const HDA_REG_WAKEEN       As UInt32 = &H0C
    Public Const HDA_REG_STATESTS     As UInt32 = &H0E
    Public Const HDA_REG_GSTS         As UInt32 = &H10
    Public Const HDA_REG_INTCTL       As UInt32 = &H20
    Public Const HDA_REG_INTSTS       As UInt32 = &H24

    ' Immediate Command / Response Registers
    Public Const HDA_REG_IC           As UInt32 = &H60
    Public Const HDA_REG_IR           As UInt32 = &H64
    Public Const HDA_REG_ICS          As UInt32 = &H68

    ' Stream Descriptor Offsets (Relative to Stream Base)
    Public Const HDA_SD_CTL           As UInt32 = &H00
    Public Const HDA_SD_STS           As UInt32 = &H03
    Public Const HDA_SD_LPIB          As UInt32 = &H04
    Public Const HDA_SD_CBL           As UInt32 = &H08
    Public Const HDA_SD_LVI           As UInt32 = &H0C
    Public Const HDA_SD_FIFOW         As UInt32 = &H0E
    Public Const HDA_SD_FIFOS         As UInt32 = &H10
    Public Const HDA_SD_FMT           As UInt32 = &H12
    Public Const HDA_SD_BDLPL         As UInt32 = &H18
    Public Const HDA_SD_BDLPU         As UInt32 = &H1C

    ' Buffer Descriptor List Structure (16 Bytes per Entry)
    <Packed>
    Structure HdaBdlEntry
        Public PhysAddrLow  As UInt32
        Public PhysAddrHigh As UInt32
        Public BufferLength As UInt32
        Public Flags        As UInt32 ' Bit 0 = Interrupt on Completion (IOC)
    End Structure

    ' Driver State
    Private pMmio        As Pointer To Byte = 0
    Private outStreamBase As UInt32 = &H100
    Private dmaShmId     As UInt64 = 0
    Private pDmaBuffer   As Pointer To Byte = 0
    Private dmaPhysBase  As UInt64 = 0
    Private bdlShmId     As UInt64 = 0
    Private pBdl         As Pointer To HdaBdlEntry = 0
    Private bdlPhysBase  As UInt64 = 0
    Private numIss       As UInt32 = 4
    Private numOss       As UInt32 = 4

    ''
    ' @brief Read 32-bit DWORD from HDA MMIO space.
    ''
    Private Unsafe Function ReadMmio32(ByVal offset As UInt32) As UInt32
        Dim pReg As Pointer To UInt32 = *UInt32(CPtr(Pointer To Byte, pMmio + offset))
        ReadMmio32 = pReg(0)
    End Function

    ''
    ' @brief Write 32-bit DWORD to HDA MMIO space.
    ''
    Private Unsafe Sub WriteMmio32(ByVal offset As UInt32, ByVal val As UInt32)
        Dim pReg As Pointer To UInt32 = *UInt32(CPtr(Pointer To Byte, pMmio + offset))
        pReg(0) = val
    End Sub

    ''
    ' @brief Read 16-bit WORD from HDA MMIO space.
    ''
    Private Unsafe Function ReadMmio16(ByVal offset As UInt32) As UInt16
        Dim pReg As Pointer To UInt16 = *UInt16(CPtr(Pointer To Byte, pMmio + offset))
        ReadMmio16 = pReg(0)
    End Function

    ''
    ' @brief Write 16-bit WORD to HDA MMIO space.
    ''
    Private Unsafe Sub WriteMmio16(ByVal offset As UInt32, ByVal val As UInt16)
        Dim pReg As Pointer To UInt16 = *UInt16(CPtr(Pointer To Byte, pMmio + offset))
        pReg(0) = val
    End Sub

    ''
    ' @brief Read 8-bit BYTE from HDA MMIO space.
    ''
    Private Unsafe Function ReadMmio8(ByVal offset As UInt32) As Byte
        Dim pReg As Pointer To Byte = CPtr(Pointer To Byte, pMmio + offset)
        ReadMmio8 = pReg(0)
    End Function

    ''
    ' @brief Write 8-bit BYTE to HDA MMIO space.
    ''
    Private Unsafe Sub WriteMmio8(ByVal offset As UInt32, ByVal val As Byte)
        Dim pReg As Pointer To Byte = CPtr(Pointer To Byte, pMmio + offset)
        pReg(0) = val
    End Sub

    ''
    ' @brief Transmit a 32-bit codec command verb via Immediate Command registers (IC/IR).
    ' @param verb 32-bit encoded verb (CodecAddr << 28 | Node << 20 | Verb << 8 | Param).
    ' @return 32-bit response from codec.
    ''
    Private Unsafe Function SendCodecVerb(ByVal verb As UInt32) As UInt32
        ' Wait until Immediate Command is not busy (ICB bit 0 == 0)
        Dim timeout As UInt32 = 100000
        While timeout > 0 And (ReadMmio16(HDA_REG_ICS) And 1) <> 0
            timeout = timeout - 1
        Wend

        ' Clear IRV (bit 1) by writing 1 to bit 1
        WriteMmio16 HDA_REG_ICS, 2

        WriteMmio32 HDA_REG_IC, verb
        WriteMmio16 HDA_REG_ICS, 1 ' Set ICB to initiate command

        timeout = 100000
        While timeout > 0 And (ReadMmio16(HDA_REG_ICS) And 1) <> 0
            timeout = timeout - 1
        Wend

        SendCodecVerb = ReadMmio32(HDA_REG_IR)
    End Function

    ''
    ' @brief Main driver daemon entry point.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleSetTtyChannel 0
        ConsoleWriteLine "[DRV_HDA] ======================================================="
        ConsoleWriteLine "[DRV_HDA] Intel High Definition Audio (ICH6 HDA) Driver Online (CPL=3)"

        ' 1. Query PID
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DRV_HDA] Active Driver PID = ", myPid, "\r\n"

        ' 2. Probe PCI for Intel HDA Controller (0x8086:0x2668 or Class 0x04 / SubClass 0x03)
        Dim devCount As UInt32 = PciGetDeviceCount()
        Dim dIdx As UInt32 = 0
        Dim targetDev As PciDevice
        Dim found As Boolean = False

        While dIdx < devCount
            Dim dev As PciDevice
            If PciGetDevice(dIdx, dev) Then
                If (dev.VendorId = &H8086 And dev.DeviceId = &H2668) Or (dev.ClassCode = 4 And dev.SubClass = 3) Then
                    targetDev = dev
                    found = True
                    Exit While
                End If
            End If
            dIdx = dIdx + 1
        Wend

        If Not found Then
            ConsoleWriteLine "[DRV_HDA] ERR: Intel HDA Controller not detected on PCI bus!"
            user_main = 1
            Exit Function
        End If

        ConsolePrintWithUInt "[DRV_HDA] Detected Intel HDA Controller at PCI [", UInt64(targetDev.Bus), ":"
        ConsolePrintWithUInt "", UInt64(targetDev.Slot), "."
        ConsolePrintWithUInt "", UInt64(targetDev.Func), "]\r\n"

        ' 3. Map BAR0 MMIO Aperture into Ring 3 address space at 0x79000000
        Dim mmioTarget As UInt64 = &H79000000
        Dim pBar0 As Pointer To UInt32 = PciMapBar(dIdx, 0, mmioTarget, False)
        If pBar0 = 0 Then
            ConsoleWriteLine "[DRV_HDA] ERR: Failed to map HDA BAR0 MMIO aperture!"
            user_main = 1
            Exit Function
        End If
        pMmio = CPtr(Pointer To Byte, mmioTarget)
        ConsolePrintWithUInt "[DRV_HDA] BAR0 MMIO mapped at 0x79000000 (Phys: 0x", targetDev.Bar0.PhysBase, ")\r\n"

        ' 4. Read Global Capabilities (GCAP)
        Dim gcap As UInt16 = ReadMmio16(HDA_REG_GCAP)
        numIss = (UInt32(gcap) RShift 8) And &H0F
        numOss = (UInt32(gcap) RShift 12) And &H0F
        ConsolePrintWithUInt "[DRV_HDA] Global Capabilities: ", UInt64(gcap), " ("
        ConsolePrintWithUInt "Input Streams: ", UInt64(numIss), ", "
        ConsolePrintWithUInt "Output Streams: ", UInt64(numOss), ")\r\n"

        ' Calculate Output Stream 0 descriptor offset: 0x80 + (numIss * 0x20)
        outStreamBase = &H80 + (numIss * &H20)
        ConsolePrintWithUInt "[DRV_HDA] Output Stream #0 MMIO Base: 0x", UInt64(outStreamBase), "\r\n"

        ' 5. Perform Controller Global Reset
        ConsoleWriteLine "[DRV_HDA] Resetting HDA Controller..."
        Dim gctl As UInt32 = ReadMmio32(HDA_REG_GCTL)
        WriteMmio32 HDA_REG_GCTL, gctl And (Not UInt32(1)) ' Clear CRST bit
        ProcessSleep 2

        Dim resetTimeout As UInt32 = 10000
        While resetTimeout > 0 And (ReadMmio32(HDA_REG_GCTL) And 1) <> 0
            resetTimeout = resetTimeout - 1
        Wend

        ' Exit reset state
        WriteMmio32 HDA_REG_GCTL, ReadMmio32(HDA_REG_GCTL) Or 1 ' Set CRST bit
        ProcessSleep 5

        resetTimeout = 10000
        While resetTimeout > 0 And (ReadMmio32(HDA_REG_GCTL) And 1) = 0
            resetTimeout = resetTimeout - 1
        Wend

        If (ReadMmio32(HDA_REG_GCTL) And 1) = 0 Then
            ConsoleWriteLine "[DRV_HDA] WARN: Controller failed to exit reset state!"
        Else
            ConsoleWriteLine "[DRV_HDA] Controller reset completed successfully."
        End If

        ' 6. Detect Codecs
        ProcessSleep 5
        Dim stateSts As UInt16 = ReadMmio16(HDA_REG_STATESTS)
        ConsolePrintWithUInt "[DRV_HDA] Codec State Status (STATESTS): 0x", UInt64(stateSts), "\r\n"

        ' 7. Configure Codec 0 Widgets via Immediate Verbs
        ConsoleWriteLine "[DRV_HDA] Configuring Codec 0 Output Widgets..."
        ' Node 1 (Audio Function Group): Set Power State D0 (0x705 = 0x00)
        SendCodecVerb &H00170500

        ' Node 2 (Audio Output Converter / DAC):
        ' Power State D0
        SendCodecVerb &H00270500
        ' Format 44.1 kHz, 16-bit, Stereo (0x4011)
        SendCodecVerb &H00224011
        ' Stream 1, Channel 0
        SendCodecVerb &H00270610
        ' Unmute Converter Amp (Gain 0 dB = 0x7F)
        SendCodecVerb &H0023B07F

        ' Node 3 (Pin Widget - Line Out):
        ' Power State D0
        SendCodecVerb &H00370500
        ' Enable Output Pin (PIN_OUT = 0x40)
        SendCodecVerb &H00370740
        ' Unmute Pin Amp (Output Amp Gain / Unmute = 0x7F)
        SendCodecVerb &H0033B07F

        ConsoleWriteLine "[DRV_HDA] Codec 0 DAC & Output Pin unmuted and configured."

        ' 8. Allocate Cyclic DMA Ring Buffer (32 KB = 8 Pages) at 0x68000000
        dmaShmId = ShmemCreate(32768, &H68000000)
        pDmaBuffer = CPtr(Pointer To Byte, &H68000000)
        ' Zero DMA buffer (silence = 0 for 16-bit signed PCM)
        MemSet pDmaBuffer, 0, 32768
        dmaPhysBase = MemVirtToPhys(&H68000000)
        ConsolePrintWithUInt "[DRV_HDA] Cyclic DMA Buffer (32 KB): 0x68000000 (Phys: 0x", dmaPhysBase, ")\r\n"

        ' 9. Allocate Buffer Descriptor List (BDL) (4 KB = 1 Page) at 0x68010000
        bdlShmId = ShmemCreate(4096, &H68010000)
        pBdl = CPtr(Pointer To HdaBdlEntry, &H68010000)
        bdlPhysBase = MemVirtToPhys(&H68010000)
        ConsolePrintWithUInt "[DRV_HDA] BDL Table (4 KB): 0x68010000 (Phys: 0x", bdlPhysBase, ")\r\n"

        ' Build 2-entry ping-pong BDL (each 16 KB)
        pBdl(0).PhysAddrLow = UInt32(dmaPhysBase And &HFFFFFFFF)
        pBdl(0).PhysAddrHigh = UInt32(dmaPhysBase RShift 32)
        pBdl(0).BufferLength = 16384
        pBdl(0).Flags = 1 ' Interrupt on Completion

        pBdl(1).PhysAddrLow = UInt32((dmaPhysBase + 16384) And &HFFFFFFFF)
        pBdl(1).PhysAddrHigh = UInt32((dmaPhysBase + 16384) RShift 32)
        pBdl(1).BufferLength = 16384
        pBdl(1).Flags = 1 ' Interrupt on Completion

        ' 10. Configure Output Stream #0
        ' Stop stream
        WriteMmio32 outStreamBase + HDA_SD_CTL, 0
        ' Clear stream status
        WriteMmio8 outStreamBase + HDA_SD_STS, &H1C

        ' Program BDL pointer
        WriteMmio32 outStreamBase + HDA_SD_BDLPL, UInt32(bdlPhysBase And &HFFFFFFFF)
        WriteMmio32 outStreamBase + HDA_SD_BDLPU, UInt32(bdlPhysBase RShift 32)

        ' Program Cyclic Buffer Length (32768 bytes)
        WriteMmio32 outStreamBase + HDA_SD_CBL, 32768

        ' Program Last Valid Index (1 = 2 descriptors)
        WriteMmio16 outStreamBase + HDA_SD_LVI, 1

        ' Program Stream Format: 44.1 kHz, 16-bit, Stereo = 0x4011
        WriteMmio16 outStreamBase + HDA_SD_FMT, &H4011

        ' Assign Stream ID = 1 and enable RUN bit (Bit 1)
        Dim ctlVal As UInt32 = (&H01 LShift 20) Or &H02
        WriteMmio32 outStreamBase + HDA_SD_CTL, ctlVal

        ConsoleWriteLine "[DRV_HDA] Output Stream #0 DMA Engine running (44.1 kHz 16-bit Stereo)."

        ' 11. Register Hardware Driver Node
        Dim hdaNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, "drv.snd.hda", 7)
        ConsolePrintWithUInt "[DRV_HDA] Registered Node 'drv.snd.hda' -> Node #", hdaNodeId, "\r\n"

        ConsoleWriteLine "[DRV_HDA] Hardware sound engine active. Entering dispatch loop..."
        ConsoleWriteLine "[DRV_HDA] ======================================================="

        ' 12. Driver Event Loop
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket

        Do
            If SynapsePop(hdaNodeId, reqPkt) Then
                If reqPkt.PacketType = 60 Then ' AUDIO_CMD_GET_CAPS
                    respPkt.Sequence = reqPkt.Sequence
                    respPkt.PacketType = 600 ' AUDIO_RESP_OK
                    respPkt.SourceNode = hdaNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    Dim pShmOut As Pointer To UInt64 = CPtr(Pointer To UInt64, @respPkt.Payload(0))
                    pShmOut(0) = dmaShmId
                    pShmOut(1) = 32768
                    respPkt.PayloadLength = 16
                    Dim replyChan As UInt64 = SynapseConnect(hdaNodeId, reqPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If
                ElseIf reqPkt.PacketType = 65 Then ' AUDIO_CMD_GET_POSITION
                    respPkt.Sequence = reqPkt.Sequence
                    respPkt.PacketType = 600
                    respPkt.SourceNode = hdaNodeId
                    respPkt.TargetNode = reqPkt.SourceNode
                    Dim lpib As UInt32 = ReadMmio32(outStreamBase + HDA_SD_LPIB)
                    Dim pPosOut As Pointer To UInt32 = CPtr(Pointer To UInt32, @respPkt.Payload(0))
                    pPosOut(0) = lpib
                    respPkt.PayloadLength = 4
                    Dim replyChan2 As UInt64 = SynapseConnect(hdaNodeId, reqPkt.SourceNode, 7)
                    If replyChan2 <> 0 Then
                        SynapsePush replyChan2, respPkt
                    End If
                End If
            Else
                ProcessSleep 20
            End If
        Loop

        user_main = 0
    End Function

End Module
