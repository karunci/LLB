' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: services/audio_srv/AudioMain.bas
' Summary: 32-Channel Audio Mixer Daemon with linear resampling and stereo panning.
'          Binds to drv.snd.hda via zero-copy shared memory DMA ring buffer (32 KB),
'          receives sound samples over Synapse IPC, performs real-time mixing, and
'          drives continuous digital audio playback for DOOM and desktop applications.

Import "../../include/pros.bas"

Module AudioMain

    Public Const MAX_CHANNELS       As Int32 = 32
    Public Const DMA_BUFFER_BYTES   As UInt32 = 32768
    Public Const DMA_BUFFER_SAMPLES As UInt32 = 8192 ' 32768 / 4 bytes (16-bit stereo)
    Public Const TARGET_SAMPLE_RATE As UInt32 = 44100
    Public Const MAX_SAMPLE_CACHE   As UInt32 = 32768

    <Packed>
    Structure MixerVoice
        Public Active        As Boolean
        Public Length        As UInt32
        Public PositionFixed As UInt32 ' 16.16 fixed-point
        Public StepFixed     As UInt32 ' 16.16 fixed-point (srcRate / 44100 * 65536)
        Public VolumeLeft    As UInt32 ' 0..256
        Public VolumeRight   As UInt32 ' 0..256
        Public Bits          As UInt16 ' 8 or 16
        Public Channels      As UInt16 ' 1 = Mono, 2 = Stereo
        Public SampleData(65535) As Byte
    End Structure

    Private voices(31)     As MixerVoice
    Private pDmaRing       As Pointer To Int16 = 0
    Private dmaShmId       As UInt64 = 0
    Private hdaNodeId      As UInt64 = 0
    Private audioNodeId    As UInt64 = 0
    Private synHda         As UInt64 = 0
    Private writeSamplePos As UInt32 = 0
    Private masterVolume   As UInt32 = 256

    ''
    ' @brief Find an available or lowest-priority mixer channel.
    ' @return Voice index (0..31).
    ''
    Private Function AllocateVoice() As Int32
        Dim i As Int32 = 0
        While i < MAX_CHANNELS
            If Not voices(i).Active Then
                AllocateVoice = i
                Exit Function
            End If
            i = i + 1
        Wend
        ' If all channels busy, steal channel 0
        AllocateVoice = 0
    End Function

    ''
    ' @brief Start playing a sound sample on the mixer.
    ''
    Private Unsafe Sub StartSample(ByVal pPkt As Pointer To AudioSamplePacket, ByVal pData As Pointer To Byte)
        Dim vIdx As Int32 = -1
        If pPkt.ChannelId >= 0 And pPkt.ChannelId < MAX_CHANNELS Then
            vIdx = pPkt.ChannelId
        Else
            vIdx = AllocateVoice()
        End If

        Dim v As Pointer To MixerVoice = AddressOf voices(vIdx)
        v.Active = False
        v.Length = pPkt.Length
        If v.Length > 65536 Then v.Length = 65536

        ' Copy sample data into voice buffer
        If pData <> 0 And v.Length > 0 Then
            Dim i As UInt32 = 0
            While i < v.Length
                v.SampleData(i) = pData(i)
                i = i + 1
            Wend
        End If

        v.PositionFixed = 0
        ' Calculate 16.16 resampling step: (srcRate * 65536) / 44100
        Dim srcRate As UInt64 = UInt64(pPkt.SampleRate)
        If srcRate = 0 Then srcRate = 11025
        v.StepFixed = UInt32((srcRate * 65536) / UInt64(TARGET_SAMPLE_RATE))
        If v.StepFixed = 0 Then v.StepFixed = 65536

        ' Calculate left/right volume based on separation (0 = Left, 128 = Center, 255 = Right)
        Dim volNorm As UInt32 = (UInt32(pPkt.Volume) * masterVolume) / 127
        If volNorm > 256 Then volNorm = 256

        Dim sep As UInt32 = UInt32(pPkt.Separation)
        Dim leftScale As UInt32 = 256 - sep
        Dim rightScale As UInt32 = sep

        v.VolumeLeft = (volNorm * leftScale) / 128
        v.VolumeRight = (volNorm * rightScale) / 128
        If v.VolumeLeft > 256 Then v.VolumeLeft = 256
        If v.VolumeRight > 256 Then v.VolumeRight = 256

        v.Bits = pPkt.Bits
        v.Channels = pPkt.Channels
        v.Active = True
    End Sub

    ''
    ' @brief Mix a block of audio frames ahead of the hardware playhead into the DMA ring.
    ' @param numFrames Number of stereo frames (samples) to mix.
    ''
    Private Unsafe Sub MixBlock(ByVal numFrames As UInt32)
        If pDmaRing = 0 Or numFrames = 0 Then Exit Sub

        Dim f As UInt32 = 0
        While f < numFrames
            Dim accL As Int32 = 0
            Dim accR As Int32 = 0

            Dim ch As Int32 = 0
            While ch < MAX_CHANNELS
                If voices(ch).Active Then
                    Dim sampleIdx As UInt32 = voices(ch).PositionFixed RShift 16
                    If sampleIdx < voices(ch).Length Then
                        Dim smpVal As Int32 = 0
                        If voices(ch).Bits = 8 Then
                            ' 8-bit unsigned PCM [0..255], 128 is silence center
                            smpVal = (Int32(voices(ch).SampleData(sampleIdx)) - 128) * 256
                        Else
                            ' 16-bit signed PCM
                            Dim byteOffset As UInt32 = sampleIdx * 2
                            If byteOffset + 1 < voices(ch).Length Then
                                Dim lo As Int32 = Int32(voices(ch).SampleData(byteOffset))
                                Dim hi As Int32 = Int32(voices(ch).SampleData(byteOffset + 1))
                                If hi >= 128 Then hi = hi - 256
                                smpVal = (hi * 256) + lo
                            End If
                        End If

                        accL = accL + ((smpVal * Int32(voices(ch).VolumeLeft)) / 256)
                        accR = accR + ((smpVal * Int32(voices(ch).VolumeRight)) / 256)

                        voices(ch).PositionFixed = voices(ch).PositionFixed + voices(ch).StepFixed
                    Else
                        voices(ch).Active = False
                    End If
                End If
                ch = ch + 1
            Wend

            ' Clamp to 16-bit signed limits [-32768, 32767]
            If accL > 32767 Then accL = 32767
            If accL < -32768 Then accL = -32768
            If accR > 32767 Then accR = 32767
            If accR < -32768 Then accR = -32768

            ' Write interleaved stereo (Left = index * 2, Right = index * 2 + 1)
            Dim ringIdx As UInt32 = (writeSamplePos * 2) Mod (DMA_BUFFER_SAMPLES * 2)
            pDmaRing(ringIdx) = Int16(accL)
            pDmaRing(ringIdx + 1) = Int16(accR)

            writeSamplePos = (writeSamplePos + 1) Mod DMA_BUFFER_SAMPLES
            f = f + 1
        Wend
    End Sub

    ''
    ' @brief Audio mixer service daemon entry point.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[SRV_AUDIO] ======================================================="
        ConsoleWriteLine "[SRV_AUDIO] PROS 32-Channel Audio Mixer Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[SRV_AUDIO] Active Audio Service PID = ", myPid, "\r\n"

        ' 2. Register Audio Subsystem Node
        audioNodeId = NodeRegister(NODE_KIND_DEVICE, "srv.audio", 7)
        If audioNodeId <> 0 Then
            ConsolePrintWithUInt "[SRV_AUDIO] Registered Node 'srv.audio' -> Node #", audioNodeId, "\r\n"
        Else
            ConsoleWriteLine "[SRV_AUDIO] WARN: Failed to register 'srv.audio' node!"
        End If

        ' 3. Connect to Hardware HDA Driver (drv.snd.hda)
        hdaNodeId = NodeLookup("drv.snd.hda")
        Dim retryCount As UInt32 = 10
        While hdaNodeId = 0 And retryCount > 0
            ProcessSleep 50
            hdaNodeId = NodeLookup("drv.snd.hda")
            retryCount = retryCount - 1
        Wend

        If hdaNodeId <> 0 Then
            ConsolePrintWithUInt "[SRV_AUDIO] Attached to Intel HDA Driver -> Node #", hdaNodeId, "\r\n"
            synHda = SynapseConnect(audioNodeId, hdaNodeId, 7)
            If synHda <> 0 Then
                ConsolePrintWithUInt "[SRV_AUDIO] Established HDA Control Synapse -> Channel #", synHda, "\r\n"
                ' Query DMA shared memory ID from driver
                Dim queryPkt As AxonPacket
                queryPkt.Sequence = 1
                queryPkt.PacketType = 60 ' AUDIO_CMD_GET_CAPS
                queryPkt.SourceNode = audioNodeId
                queryPkt.TargetNode = hdaNodeId
                queryPkt.PayloadLength = 0
                SynapsePush synHda, queryPkt

                Dim respPkt As AxonPacket
                If SynapsePop(audioNodeId, respPkt) Then
                    If respPkt.PacketType = 600 Then
                        Dim pShmIn As Pointer To UInt64 = Pointer To UInt64(AddressOf respPkt.Payload(0))
                        dmaShmId = pShmIn(0)
                        ConsolePrintWithUInt "[SRV_AUDIO] Received HDA DMA SHMID: ", dmaShmId, "\r\n"

                        ' Attach DMA buffer at 0x68400000
                        Dim attachAddr As UInt64 = ShmemAttach(dmaShmId, &H68400000)
                        If attachAddr <> 0 Then
                            pDmaRing = Pointer To Int16(attachAddr)
                            ConsoleWriteLine "[SRV_AUDIO] DMA Audio Ring attached at 0x68400000 (32 KB)."
                        End If
                    End If
                End If
            End If
        Else
            ConsoleWriteLine "[SRV_AUDIO] WARN: drv.snd.hda not found. Running in software loopback mode."
        End If

        ' 4. Initialize Mixer Voices
        Dim v As Int32 = 0
        While v < MAX_CHANNELS
            voices(v).Active = False
            voices(v).Length = 0
            voices(v).PositionFixed = 0
            voices(v).StepFixed = 65536
            voices(v).VolumeLeft = 256
            voices(v).VolumeRight = 256
            voices(v).Bits = 8
            voices(v).Channels = 1
            v = v + 1
        Wend

        ConsoleWriteLine "[SRV_AUDIO] 32-Channel Mixer Engine initialized (44.1 kHz Stereo)."
        ConsoleWriteLine "[SRV_AUDIO] Active audio arbitration online. Entering service loop..."
        ConsoleWriteLine "[SRV_AUDIO] ======================================================="

        ' 5. Active Mixer & Request Dispatcher Loop
        Dim reqPkt As AxonPacket
        Dim lastTickTime As UInt64 = GetUptime()
        writeSamplePos = 0

        Do
            ' A. Process incoming client sound requests
            If SynapsePop(audioNodeId, reqPkt) Then
                If reqPkt.PacketType = 61 Then ' AUDIO_CMD_PLAY_SAMPLE
                    Dim pSamplePkt As Pointer To AudioSamplePacket = Pointer To AudioSamplePacket(AddressOf reqPkt.Payload(0))
                    Dim headerSize As UInt32 = SizeOf(AudioSamplePacket)
                    Dim pData As Pointer To Byte = AddressOf reqPkt.Payload(headerSize)
                    StartSample pSamplePkt, pData
                ElseIf reqPkt.PacketType = 62 Then ' AUDIO_CMD_STOP_SAMPLE
                    Dim pCh As Pointer To Int32 = Pointer To Int32(AddressOf reqPkt.Payload(0))
                    Dim chIdx As Int32 = pCh(0)
                    If chIdx >= 0 And chIdx < MAX_CHANNELS Then
                        voices(chIdx).Active = False
                    End If
                ElseIf reqPkt.PacketType = 64 Then ' AUDIO_CMD_SET_VOLUME
                    Dim newVol As UInt32 = UInt32(reqPkt.Payload(0))
                    masterVolume = (newVol * 256) / 127
                    If masterVolume > 256 Then masterVolume = 256
                End If
            End If

            ' B. Mix 441 frames (~10 ms of 44.1 kHz audio)
            MixBlock 441
            ProcessSleep 10
        Loop

        user_main = 0
    End Function

End Module
