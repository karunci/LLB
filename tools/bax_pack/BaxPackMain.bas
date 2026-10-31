' Project Name: Low-Level Basic / PROS Toolchain
' Filename: tools/bax_pack/BaxPackMain.bas
' Summary: Native Low-Level Basic ELF64 to NEO/PE-BAX binary packager.
'          Converts ELF64 binaries into native NEO/PE-BAX executable containers
'          with optional embedded manifest resources.

Module BaxPackMain

    ' =========================================================================
    ' 1. C Standard Library Declarations (Hosted Platform)
    ' =========================================================================
    Public Declare Function fopen Lib "c" (ByVal filename As Pointer To Byte, ByVal mode As Pointer To Byte) As Pointer To Byte
    Public Declare Function fclose Lib "c" (ByVal stream As Pointer To Byte) As Int32
    Public Declare Function fread Lib "c" (ByVal ptr As Pointer To Byte, ByVal size As UInt64, ByVal count As UInt64, ByVal stream As Pointer To Byte) As UInt64
    Public Declare Function fwrite Lib "c" (ByVal ptr As Pointer To Byte, ByVal size As UInt64, ByVal count As UInt64, ByVal stream As Pointer To Byte) As UInt64
    Public Declare Function fseek Lib "c" (ByVal stream As Pointer To Byte, ByVal offset As Int64, ByVal origin As Int32) As Int32
    Public Declare Function ftell Lib "c" (ByVal stream As Pointer To Byte) As Int64
    Public Declare Function malloc Lib "c" (ByVal size As UInt64) As Pointer To Byte
    Public Declare Sub free Lib "c" (ByVal ptr As Pointer To Byte)
    Public Declare Function memset Lib "c" (ByVal s As Pointer To Byte, ByVal c As Int32, ByVal n As UInt64) As Pointer To Byte
    Public Declare Function memcpy Lib "c" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal n As UInt64) As Pointer To Byte
    Public Declare Function printf Lib "c" (ByVal fmt As Pointer To Byte) As Int32
    Public Declare Function strcmp Lib "c" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
    Public Declare Function strlen Lib "c" (ByVal s As Pointer To Byte) As UInt64

    ' =========================================================================
    ' 2. BAX Specification Constants
    ' =========================================================================
    Public Const BAX_FORMAT_VERSION         As UInt16 = 1
    Public Const BAX_ARCH_X86_64            As UInt16 = 1

    Public Const SUBSYSTEM_CONSOLE          As UInt16 = 1
    Public Const SUBSYSTEM_GUI              As UInt16 = 2
    Public Const SUBSYSTEM_NEURAL_NODE      As UInt16 = 3

    Public Const ASSET_MANIFEST             As UInt32 = 1
    Public Const ASSET_ICON                 As UInt32 = 2
    Public Const ASSET_IMAGE                As UInt32 = 3
    Public Const ASSET_FONT                 As UInt32 = 4
    Public Const ASSET_CUSTOM               As UInt32 = 5

    Public Const DEFAULT_RESOURCE_VIRT_ADDR As UInt64 = &H50000000

    ' =========================================================================
    ' 3. Internal Segment & Resource Structures
    ' =========================================================================
    Structure SegmentInfo
        Public VirtAddr   As UInt64
        Public FileSize   As UInt64
        Public MemSize    As UInt64
        Public Flags      As UInt32
        Public ElfOffset  As UInt64
        Public BaxOffset  As UInt64
    End Structure

    Structure ResourceInfo
        Public ResType    As UInt32
        Public ResId      As UInt32
        Public VirtAddr   As UInt64
        Public ByteLength As UInt64
        Public BaxOffset  As UInt64
        Public DataPtr    As Pointer To Byte
        Public Name(16)   As Byte
    End Structure

    Private g_segments(32)  As SegmentInfo
    Private g_numSegments   As UInt32 = 0
    Private g_resources(8)  As ResourceInfo
    Private g_numResources  As UInt32 = 0

    Private g_elfBuffer     As Pointer To Byte = 0
    Private g_elfSize       As UInt64 = 0

    ''
    ' @brief Print helper for string output.
    ''
    Private Sub PrintStr(ByVal msg As Pointer To Byte)
        printf msg
    End Sub

    ''
    ' @brief Load an entire file into newly allocated memory.
    ''
    Private Function ReadEntireFile(ByVal path As Pointer To Byte, ByRef outSize As UInt64) As Pointer To Byte
        Dim fp As Pointer To Byte = fopen(path, CPtr(Pointer To Byte, "rb"))
        If fp = 0 Then
            outSize = 0
            ReadEntireFile = 0
            Exit Function
        End If

        fseek fp, 0, 2 ' SEEK_END
        Dim sz As Int64 = ftell(fp)
        fseek fp, 0, 0 ' SEEK_SET

        If sz <= 0 Then
            fclose fp
            outSize = 0
            ReadEntireFile = 0
            Exit Function
        End If

        Dim buf As Pointer To Byte = malloc(UInt64(sz))
        If buf = 0 Then
            fclose fp
            outSize = 0
            ReadEntireFile = 0
            Exit Function
        End If

        fread buf, 1, UInt64(sz), fp
        fclose fp

        outSize = UInt64(sz)
        ReadEntireFile = buf
    End Function

    ''
    ' @brief Align a value up to a power-of-two boundary.
    ''
    Private Function AlignUp(ByVal val As UInt64, ByVal align As UInt64) As UInt64
        If (val And (align - 1)) = 0 Then
            AlignUp = val
        Else
            AlignUp = (val + align) And (Not (align - 1))
        End If
    End Function

    ''
    ' @brief Parse ELF64 header and loadable (PT_LOAD) segments.
    ''
    Private Function ParseElf64(ByVal elfBuf As Pointer To Byte, ByVal elfSize As UInt64, _
                                ByRef outEntry As UInt64, ByRef outBase As UInt64, ByRef outImageSize As UInt64) As Boolean
        If elfSize < 64 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: ELF file is too small.\n")
            ParseElf64 = False
            Exit Function
        End If

        ' Magic check: 0x7F, 'E', 'L', 'F'
        If elfBuf(0) <> &H7F Or elfBuf(1) <> 69 Or elfBuf(2) <> 76 Or elfBuf(3) <> 70 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: Invalid ELF magic.\n")
            ParseElf64 = False
            Exit Function
        End If

        ' Verify 64-bit (EI_CLASS=2) and Little-Endian (EI_DATA=1)
        If elfBuf(4) <> 2 Or elfBuf(5) <> 1 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: ELF must be 64-bit Little-Endian.\n")
            ParseElf64 = False
            Exit Function
        End If

        ' e_entry at offset 24 (UInt64)
        Dim pEntry As Pointer To UInt64 = *UInt64(elfBuf + 24)
        outEntry = pEntry(0)

        ' e_phoff at offset 32 (UInt64)
        Dim pPhoff As Pointer To UInt64 = *UInt64(elfBuf + 32)
        Dim phoff As UInt64 = pPhoff(0)

        ' e_phentsize at offset 54 (UInt16)
        Dim pPhentsize As Pointer To UInt16 = *UInt16(elfBuf + 54)
        Dim phentsize As UInt64 = UInt64(pPhentsize(0))

        ' e_phnum at offset 56 (UInt16)
        Dim pPhnum As Pointer To UInt16 = *UInt16(elfBuf + 56)
        Dim phnum As UInt32 = UInt32(pPhnum(0))

        Dim minVaddr As UInt64 = &HFFFFFFFFFFFFFFFF
        Dim maxVaddr As UInt64 = 0
        g_numSegments = 0

        Dim i As UInt32 = 0
        While i < phnum And g_numSegments < 32
            Dim phAddr As Pointer To Byte = elfBuf + phoff + (UInt64(i) * phentsize)

            ' p_type at phAddr + 0 (UInt32)
            Dim pTypePtr As Pointer To UInt32 = *UInt32(phAddr + 0)
            Dim pType As UInt32 = pTypePtr(0)

            ' p_flags at phAddr + 4 (UInt32)
            Dim pFlagsPtr As Pointer To UInt32 = *UInt32(phAddr + 4)
            Dim pFlags As UInt32 = pFlagsPtr(0)

            ' p_offset at phAddr + 8 (UInt64)
            Dim pOffsetPtr As Pointer To UInt64 = *UInt64(phAddr + 8)
            Dim pOffset As UInt64 = pOffsetPtr(0)

            ' p_vaddr at phAddr + 16 (UInt64)
            Dim pVaddrPtr As Pointer To UInt64 = *UInt64(phAddr + 16)
            Dim pVaddr As UInt64 = pVaddrPtr(0)

            ' p_filesz at phAddr + 32 (UInt64)
            Dim pFileszPtr As Pointer To UInt64 = *UInt64(phAddr + 32)
            Dim pFilesz As UInt64 = pFileszPtr(0)

            ' p_memsz at phAddr + 40 (UInt64)
            Dim pMemszPtr As Pointer To UInt64 = *UInt64(phAddr + 40)
            Dim pMemsz As UInt64 = pMemszPtr(0)

            ' PT_LOAD is type 1
            If pType = 1 And pMemsz > 0 Then
                Dim segIdx As UInt32 = g_numSegments
                g_segments(segIdx).VirtAddr = pVaddr
                g_segments(segIdx).FileSize = pFilesz
                g_segments(segIdx).MemSize = pMemsz
                g_segments(segIdx).ElfOffset = pOffset

                ' Map ELF flags to BAX flags: PF_R=4 -> 1, PF_W=2 -> 2, PF_X=1 -> 4
                Dim baxFlags As UInt32 = 0
                If (pFlags And 4) <> 0 Then baxFlags = baxFlags Or 1
                If (pFlags And 2) <> 0 Then baxFlags = baxFlags Or 2
                If (pFlags And 1) <> 0 Then baxFlags = baxFlags Or 4
                g_segments(segIdx).Flags = baxFlags

                If pVaddr < minVaddr Then minVaddr = pVaddr
                Dim segEnd As UInt64 = pVaddr + pMemsz
                If segEnd > maxVaddr Then maxVaddr = segEnd

                g_numSegments = g_numSegments + 1
            End If

            i = i + 1
        Wend

        If g_numSegments = 0 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: No loadable (PT_LOAD) segments found.\n")
            ParseElf64 = False
            Exit Function
        End If

        outBase = minVaddr
        outImageSize = maxVaddr - minVaddr
        ParseElf64 = True
    End Function

    ''
    ' @brief Pack parsed ELF segments and manifest into BAX container file.
    ''
    Public Function PackBax(ByVal elfBuf As Pointer To Byte, ByVal outBaxPath As Pointer To Byte, _
                            ByVal subsystem As UInt16, ByVal entryPoint As UInt64, _
                            ByVal imageBase As UInt64, ByVal imageSize As UInt64) As Boolean
        Dim headerSize As UInt64 = 64
        Dim segTableSize As UInt64 = UInt64(g_numSegments) * 48
        Dim resDirSize As UInt64 = 0
        If g_numResources > 0 Then
            resDirSize = UInt64(g_numResources) * 48
        End If

        ' Calculate offsets
        Dim curOffset As UInt64 = headerSize + segTableSize + resDirSize
        curOffset = AlignUp(curOffset, 16)

        Dim s As UInt32 = 0
        While s < g_numSegments
            g_segments(s).BaxOffset = curOffset
            curOffset = curOffset + g_segments(s).FileSize
            curOffset = AlignUp(curOffset, 16)
            s = s + 1
        Wend

        Dim resVirtBase As UInt64 = 0
        If g_numResources > 0 Then
            resVirtBase = DEFAULT_RESOURCE_VIRT_ADDR
            Dim resVirtCur As UInt64 = resVirtBase + resDirSize
            resVirtCur = AlignUp(resVirtCur, 16)

            Dim r As UInt32 = 0
            While r < g_numResources
                g_resources(r).BaxOffset = curOffset
                g_resources(r).VirtAddr = resVirtCur

                curOffset = curOffset + g_resources(r).ByteLength
                curOffset = AlignUp(curOffset, 16)

                resVirtCur = resVirtCur + g_resources(r).ByteLength
                resVirtCur = AlignUp(resVirtCur, 16)
                r = r + 1
            Wend
        End If

        ' Allocate container buffer
        Dim outBuf As Pointer To Byte = malloc(curOffset)
        If outBuf = 0 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: Memory allocation failed for output BAX.\n")
            PackBax = False
            Exit Function
        End If
        memset outBuf, 0, curOffset

        ' 1. Write BAX Header (64 bytes)
        ' Magic: "NEO/BAX\0"
        outBuf(0) = 78  ' 'N'
        outBuf(1) = 69  ' 'E'
        outBuf(2) = 79  ' 'O'
        outBuf(3) = 47  ' '/'
        outBuf(4) = 66  ' 'B'
        outBuf(5) = 65  ' 'A'
        outBuf(6) = 88  ' 'X'
        outBuf(7) = 0

        Dim pVer As Pointer To UInt16 = *UInt16(outBuf + 8)
        pVer(0) = BAX_FORMAT_VERSION
        Dim pArch As Pointer To UInt16 = *UInt16(outBuf + 10)
        pArch(0) = BAX_ARCH_X86_64
        Dim pSubsys As Pointer To UInt16 = *UInt16(outBuf + 12)
        pSubsys(0) = subsystem
        Dim pFlags As Pointer To UInt16 = *UInt16(outBuf + 14)
        pFlags(0) = 1 ' ASLR_OK

        Dim pEntry As Pointer To UInt64 = *UInt64(outBuf + 16)
        pEntry(0) = entryPoint
        Dim pBase As Pointer To UInt64 = *UInt64(outBuf + 24)
        pBase(0) = imageBase
        Dim pSize As Pointer To UInt64 = *UInt64(outBuf + 32)
        pSize(0) = imageSize

        Dim pSegOff As Pointer To UInt32 = *UInt32(outBuf + 40)
        pSegOff(0) = UInt32(headerSize)
        Dim pSegCount As Pointer To UInt16 = *UInt16(outBuf + 44)
        pSegCount(0) = UInt16(g_numSegments)
        Dim pResCount As Pointer To UInt16 = *UInt16(outBuf + 46)
        pResCount(0) = UInt16(g_numResources)

        Dim pResOff As Pointer To UInt32 = *UInt32(outBuf + 48)
        If g_numResources > 0 Then
            pResOff(0) = UInt32(headerSize + segTableSize)
        Else
            pResOff(0) = 0
        End If

        Dim pResVirt As Pointer To UInt64 = *UInt64(outBuf + 52)
        pResVirt(0) = resVirtBase

        ' 2. Write Segment Table
        Dim segTableOff As UInt64 = headerSize
        s = 0
        While s < g_numSegments
            Dim pEntryPtr As Pointer To Byte = outBuf + segTableOff + (UInt64(s) * 48)
            ' Segment name: .segN\0
            pEntryPtr(0) = 46 ' '.'
            pEntryPtr(1) = 115 ' 's'
            pEntryPtr(2) = 101 ' 'e'
            pEntryPtr(3) = 103 ' 'g'
            pEntryPtr(4) = 48 + Byte(s)
            pEntryPtr(5) = 0

            Dim pFOff As Pointer To UInt64 = *UInt64(pEntryPtr + 8)
            pFOff(0) = g_segments(s).BaxOffset

            Dim pFSz As Pointer To UInt64 = *UInt64(pEntryPtr + 16)
            pFSz(0) = g_segments(s).FileSize

            Dim pVAddr As Pointer To UInt64 = *UInt64(pEntryPtr + 24)
            pVAddr(0) = g_segments(s).VirtAddr

            Dim pMSz As Pointer To UInt64 = *UInt64(pEntryPtr + 32)
            pMSz(0) = g_segments(s).MemSize

            Dim pFlg As Pointer To UInt32 = *UInt32(pEntryPtr + 40)
            pFlg(0) = g_segments(s).Flags

            s = s + 1
        Wend

        ' 3. Write Resource Directory (if any)
        If g_numResources > 0 Then
            Dim resDirOff As UInt64 = headerSize + segTableSize
            r = 0
            While r < g_numResources
                Dim pResPtr As Pointer To Byte = outBuf + resDirOff + (UInt64(r) * 48)

                Dim pType As Pointer To UInt32 = *UInt32(pResPtr + 0)
                pType(0) = g_resources(r).ResType

                Dim pId As Pointer To UInt32 = *UInt32(pResPtr + 4)
                pId(0) = g_resources(r).ResId

                ' Copy resource name (up to 15 bytes)
                Dim n As UInt32 = 0
                While n < 15 And g_resources(r).Name(n) <> 0
                    pResPtr(8 + n) = g_resources(r).Name(n)
                    n = n + 1
                Wend
                pResPtr(8 + n) = 0

                Dim pROff As Pointer To UInt64 = *UInt64(pResPtr + 24)
                pROff(0) = g_resources(r).BaxOffset

                Dim pRLen As Pointer To UInt64 = *UInt64(pResPtr + 32)
                pRLen(0) = g_resources(r).ByteLength

                Dim pRVirt As Pointer To UInt64 = *UInt64(pResPtr + 40)
                pRVirt(0) = g_resources(r).VirtAddr

                r = r + 1
            Wend
        End If

        ' 4. Copy Segment Data Payloads from ELF
        s = 0
        While s < g_numSegments
            If g_segments(s).FileSize > 0 Then
                Dim srcPtr As Pointer To Byte = elfBuf + g_segments(s).ElfOffset
                Dim dstPtr As Pointer To Byte = outBuf + g_segments(s).BaxOffset
                memcpy dstPtr, srcPtr, g_segments(s).FileSize
            End If
            s = s + 1
        Wend

        ' 5. Copy Resource Payloads
        If g_numResources > 0 Then
            r = 0
            While r < g_numResources
                If g_resources(r).ByteLength > 0 And g_resources(r).DataPtr <> 0 Then
                    Dim resDstPtr As Pointer To Byte = outBuf + g_resources(r).BaxOffset
                    memcpy resDstPtr, g_resources(r).DataPtr, g_resources(r).ByteLength
                End If
                r = r + 1
            Wend
        End If

        ' 6. Write final BAX file
        Dim outFp As Pointer To Byte = fopen(outBaxPath, CPtr(Pointer To Byte, "wb"))
        If outFp = 0 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: Failed to open output BAX file for writing.\n")
            free outBuf
            PackBax = False
            Exit Function
        End If

        fwrite outBuf, 1, curOffset, outFp
        fclose outFp
        free outBuf

        PrintStr CPtr(Pointer To Byte, "[BAX-PACK] SUCCESS: Packaged BAX binary -> ")
        PrintStr outBaxPath
        PrintStr CPtr(Pointer To Byte, "\n")
        PackBax = True
    End Function

    ' =========================================================================
    ' 4. Main Entry Point
    ' =========================================================================
    Public Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        If argc < 2 Then
            PrintStr CPtr(Pointer To Byte, "Usage: bax_pack <input.elf> [-o <output.bax>] [--manifest <manifest.json>] [--subsystem <console|gui|node>]\n")
            Main = 1
            Exit Function
        End If

        Dim elfPath As Pointer To Byte = argv(1)
        Dim outBaxPath As Pointer To Byte = 0
        Dim manifestPath As Pointer To Byte = 0
        Dim subsystem As UInt16 = SUBSYSTEM_CONSOLE

        ' Default output path buffer (replace .elf with .bax)
        Dim defaultOutBuf(512) As Byte
        Dim elfLen As UInt64 = strlen(elfPath)
        If elfLen > 500 Then elfLen = 500
        memcpy @defaultOutBuf(0), elfPath, elfLen
        defaultOutBuf(elfLen) = 0

        ' If ends with .elf, replace with .bax
        If elfLen >= 4 Then
            If defaultOutBuf(elfLen - 4) = 46 And defaultOutBuf(elfLen - 3) = 101 And defaultOutBuf(elfLen - 2) = 108 And defaultOutBuf(elfLen - 1) = 102 Then
                defaultOutBuf(elfLen - 3) = 98  ' 'b'
                defaultOutBuf(elfLen - 2) = 97  ' 'a'
                defaultOutBuf(elfLen - 1) = 120 ' 'x'
            Else
                defaultOutBuf(elfLen) = 46     ' '.'
                defaultOutBuf(elfLen + 1) = 98 ' 'b'
                defaultOutBuf(elfLen + 2) = 97 ' 'a'
                defaultOutBuf(elfLen + 3) = 120' 'x'
                defaultOutBuf(elfLen + 4) = 0
            End If
        End If
        outBaxPath = @defaultOutBuf(0)

        ' Parse command line arguments
        Dim argIdx As Int32 = 2
        While argIdx < argc
            Dim argStr As Pointer To Byte = argv(argIdx)

            If strcmp(argStr, CPtr(Pointer To Byte, "-o")) = 0 And (argIdx + 1) < argc Then
                argIdx = argIdx + 1
                outBaxPath = argv(argIdx)
            ElseIf strcmp(argStr, CPtr(Pointer To Byte, "--manifest")) = 0 And (argIdx + 1) < argc Then
                argIdx = argIdx + 1
                manifestPath = argv(argIdx)
            ElseIf strcmp(argStr, CPtr(Pointer To Byte, "--subsystem")) = 0 And (argIdx + 1) < argc Then
                argIdx = argIdx + 1
                Dim subStr As Pointer To Byte = argv(argIdx)
                If strcmp(subStr, CPtr(Pointer To Byte, "gui")) = 0 Then
                    subsystem = SUBSYSTEM_GUI
                ElseIf strcmp(subStr, CPtr(Pointer To Byte, "node")) = 0 Then
                    subsystem = SUBSYSTEM_NEURAL_NODE
                Else
                    subsystem = SUBSYSTEM_CONSOLE
                End If
            End If

            argIdx = argIdx + 1
        Wend

        ' 1. Read input ELF file
        g_elfBuffer = ReadEntireFile(elfPath, g_elfSize)
        If g_elfBuffer = 0 Then
            PrintStr CPtr(Pointer To Byte, "[BAX-PACK] Error: Failed to read input ELF file.\n")
            Main = 1
            Exit Function
        End If

        ' 2. Parse ELF64 headers
        Dim entryPoint As UInt64 = 0
        Dim imageBase As UInt64 = 0
        Dim imageSize As UInt64 = 0
        If Not ParseElf64(g_elfBuffer, g_elfSize, entryPoint, imageBase, imageSize) Then
            free g_elfBuffer
            Main = 1
            Exit Function
        End If

        ' 3. Read manifest resource if specified
        g_numResources = 0
        Dim manifestBuf As Pointer To Byte = 0
        Dim manifestSize As UInt64 = 0
        If manifestPath <> 0 Then
            manifestBuf = ReadEntireFile(manifestPath, manifestSize)
            If manifestBuf <> 0 And manifestSize > 0 Then
                g_resources(0).ResType = ASSET_MANIFEST
                g_resources(0).ResId = 1
                g_resources(0).ByteLength = manifestSize
                g_resources(0).DataPtr = manifestBuf
                ' Name: "manifest.json"
                Dim mName As Pointer To Byte = CPtr(Pointer To Byte, "manifest.json")
                Dim mn As UInt32 = 0
                While mn < 14
                    g_resources(0).Name(mn) = mName(mn)
                    mn = mn + 1
                Wend
                g_resources(0).Name(13) = 0
                g_numResources = 1
            End If
        End If

        ' 4. Pack into BAX binary
        Dim success As Boolean = PackBax(g_elfBuffer, outBaxPath, subsystem, entryPoint, imageBase, imageSize)

        If manifestBuf <> 0 Then free manifestBuf
        free g_elfBuffer

        If success Then
            Main = 0
        Else
            Main = 1
        End If
    End Function

End Module
