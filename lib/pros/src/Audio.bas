' Project Name: LibPROS / Low-Level Basic
' Filename: lib/pros/src/Audio.bas
' Summary: High-level client API for PROS Audio Subsystem and multi-channel sound playback.

Import Pros.Sys
Import Pros.Nodes
Import Pros.Sys.Shmem

Namespace Pros.Audio

    <Packed>
    Public Structure AudioSamplePacket
        Public SampleRate As UInt32
        Public Channels   As UInt16
        Public Bits       As UInt16
        Public Length     As UInt32
        Public Volume     As Byte
        Public Separation As Byte
        Public Pitch      As UInt16
        Public ChannelId  As Int32
        Public ShmId      As UInt64
        Public ShmOffset  As UInt32
        Public Reserved   As UInt32
    End Structure

    Public Module Audio

        Private audioNodeId   As UInt64 = 0
        Private audioSynapse  As UInt64 = 0
        Private myNodeId      As UInt64 = 0
        Private initialized   As Boolean = False

        ''
        ' @brief Connect to the system audio service daemon (srv.audio).
        ' @return True if connected successfully.
        ''
        Public Unsafe Function Initialize() As Boolean
            If initialized Then
                Initialize = True
                Exit Function
            End If

            audioNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.audio")
            If audioNodeId = 0 Then
                Initialize = False
                Exit Function
            End If

            myNodeId = Pros.Nodes.NodeRegistry.Register(1, "audio.client", 7)
            If myNodeId = 0 Then
                Initialize = False
                Exit Function
            End If

            audioSynapse = Pros.Nodes.NodeRegistry.Connect(myNodeId, audioNodeId, 7)
            If audioSynapse = 0 Then
                Initialize = False
                Exit Function
            End If

            initialized = True
            Initialize = True
        End Function

        ''
        ' @brief Submit a digital PCM sound effect sample for mixed playback.
        ' @param sampleRate Sampling frequency in Hz (e.g. 11025, 22050, 44100).
        ' @param channels Channel count (1 = Mono, 2 = Stereo).
        ' @param bits Bit depth (8 = 8-bit unsigned, 16 = 16-bit signed).
        ' @param pData Pointer to raw PCM sample buffer.
        ' @param length Length of sample buffer in bytes.
        ' @param volume Volume attenuation (0 = Mute, 127 = Max).
        ' @param separation Stereo panning (0 = Full Left, 128 = Center, 255 = Full Right).
        ' @return Channel ID or -1 on error.
        ''
        Public Unsafe Function PlaySample(ByVal sampleRate As UInt32, ByVal channels As UInt16, _
                                         ByVal bits As UInt16, ByVal pData As Pointer To Byte, _
                                         ByVal length As UInt32, ByVal volume As Byte, _
                                         ByVal separation As Byte) As Int32
            If Not initialized Then
                If Not Initialize() Then
                    PlaySample = -1
                    Exit Function
                End If
            End If

            Dim pkt As AxonPacket
            pkt.Sequence = 1
            pkt.PacketType = 61 ' AUDIO_CMD_PLAY_SAMPLE
            pkt.SourceNode = myNodeId
            pkt.TargetNode = audioNodeId

            Dim pSample As Pointer To AudioSamplePacket = CPtr(Pointer To AudioSamplePacket, @pkt.Payload(0))
            pSample.SampleRate = sampleRate
            pSample.Channels = channels
            pSample.Bits = bits
            pSample.Length = length
            pSample.Volume = volume
            pSample.Separation = separation
            pSample.Pitch = 128
            pSample.ChannelId = -1
            pSample.ShmId = 0
            pSample.ShmOffset = 0
            pSample.Reserved = 0

            ' If payload fits inline (up to 200 bytes), copy inline
            Dim headerSize As UInt32 = SizeOf(AudioSamplePacket)
            If length <= (256 - headerSize) And pData <> 0 Then
                Dim pDst As Pointer To Byte = @pkt.Payload(headerSize)
                Dim i As UInt32 = 0
                While i < length
                    pDst(i) = pData(i)
                    i = i + 1
                Wend
                pkt.PayloadLength = headerSize + length
            Else
                ' Passed via pointer / buffer reference
                pkt.PayloadLength = headerSize
            End If

            If Pros.Nodes.NodeRegistry.Push(audioSynapse, pkt) Then
                PlaySample = 0
            Else
                PlaySample = -1
            End If
        End Function

        ''
        ' @brief Stop audio playback on a specific hardware/mixer channel.
        ' @param channel Channel index.
        ''
        Public Unsafe Sub StopChannel(ByVal channel As Int32)
            If Not initialized Then Exit Sub

            Dim pkt As AxonPacket
            pkt.Sequence = 1
            pkt.PacketType = 62 ' AUDIO_CMD_STOP_SAMPLE
            pkt.SourceNode = myNodeId
            pkt.TargetNode = audioNodeId

            Dim pCh As Pointer To Int32 = CPtr(Pointer To Int32, @pkt.Payload(0))
            pCh(0) = channel
            pkt.PayloadLength = 4
            Pros.Nodes.NodeRegistry.Push audioSynapse, pkt
        End Sub

        ''
        ' @brief Set global master audio volume.
        ' @param volume Volume level (0..127).
        ''
        Public Unsafe Sub SetMasterVolume(ByVal volume As Byte)
            If Not initialized Then Exit Sub

            Dim pkt As AxonPacket
            pkt.Sequence = 1
            pkt.PacketType = 64 ' AUDIO_CMD_SET_VOLUME
            pkt.SourceNode = myNodeId
            pkt.TargetNode = audioNodeId
            pkt.Payload(0) = volume
            pkt.PayloadLength = 1
            Pros.Nodes.NodeRegistry.Push audioSynapse, pkt
        End Sub

    End Module

End Namespace
