' Project Name: PRK-LLB (Personal Research Kernel) / Low-Level Basic
' Filename: tests/kernel/src/fs/TarArchive.cls
' Summary: High-performance in-memory USTAR initrd filesystem parser (zero dynamic allocation).

Use Drivers.SerialUart As Serial

Namespace Fs

    <Packed>
    Public Structure TarHeader
        Public FileName(100) As Byte     ' File path/name (100 bytes)
        Public Mode(8)       As Byte     ' File mode octal (8 bytes)
        Public Uid(8)        As Byte     ' User ID octal (8 bytes)
        Public Gid(8)        As Byte     ' Group ID octal (8 bytes)
        Public FileSize(12)  As Byte     ' Size in bytes octal (12 bytes)
        Public Mtime(12)     As Byte     ' Modification time octal (12 bytes)
        Public Chksum(8)     As Byte     ' Header checksum octal (8 bytes)
        Public TypeFlag      As Byte     ' Link/file type flag (1 byte)
        Public LinkName(100) As Byte     ' Linked file name (100 bytes)
        Public Magic(6)      As Byte     ' "ustar\0" or "ustar " (6 bytes)
        Public Version(2)    As Byte     ' USTAR version (2 bytes)
        Public Uname(32)     As Byte     ' User name (32 bytes)
        Public Gname(32)     As Byte     ' Group name (32 bytes)
        Public DevMajor(8)   As Byte     ' Device major number (8 bytes)
        Public DevMinor(8)   As Byte     ' Device minor number (8 bytes)
        Public Prefix(155)   As Byte     ' Filename prefix (155 bytes)
        Public Padding(12)   As Byte     ' Alignment padding to 512 bytes (12 bytes)
    End Structure

    #Assert SizeOf(TarHeader) = 512, "TarHeader must be exactly 512 bytes"

    <Instancing(SingleUse)>
    Public Class TarArchive

        ''
        ' @brief Parse octal ASCII string from TAR header into 64-bit integer.
        ' @param strPtr Pointer to ASCII string.
        ' @param maxLen Maximum characters to parse.
        ' @return Decoded integer value.
        ''
        Private Unsafe Function ParseOctal(ByVal strPtr As Pointer To Byte, ByVal maxLen As UInt32) As UInt64
            Dim val As UInt64 = 0
            Dim i As UInt32 = 0
            While i < maxLen And strPtr(i) >= 48 And strPtr(i) <= 55
                val = (val LShift 3) + CType(UInt64, strPtr(i) - 48)
                i = i + 1
            Wend
            ParseOctal = val
        End Function

        ''
        ' @brief Compare two null-terminated strings for exact match.
        ' @param s1 First string.
        ' @param s2 Second string.
        ' @return True if strings match, False otherwise.
        ''
        Private Unsafe Function StringEqual(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Boolean
            Dim i As UInt32 = 0
            While s1(i) <> 0 And s2(i) <> 0
                If s1(i) <> s2(i) Then
                    StringEqual = False
                    Exit Function
                End If
                i = i + 1
            Wend
            StringEqual = (s1(i) = 0 And s2(i) = 0)
        End Function

        Private Unsafe Function MatchFilename(ByVal tarPath As Pointer To Byte, ByVal searchName As Pointer To Byte) As Boolean
            If Me.StringEqual(tarPath, searchName) Then
                MatchFilename = True
                Exit Function
            End If

            ' If searchName does not contain a slash, compare against basename of tarPath
            Dim hasSlash As Boolean = False
            Dim si As UInt32 = 0
            While searchName(si) <> 0
                If searchName(si) = 47 Then hasSlash = True
                si = si + 1
            Wend

            If Not hasSlash Then
                Dim lastSlash As Int32 = -1
                Dim ti As UInt32 = 0
                While tarPath(ti) <> 0
                    If tarPath(ti) = 47 Then lastSlash = CType(Int32, ti)
                    ti = ti + 1
                Wend
                If lastSlash >= 0 Then
                    Dim basePtr As Pointer To Byte = tarPath + (lastSlash + 1)
                    If Me.StringEqual(basePtr, searchName) Then
                        MatchFilename = True
                        Exit Function
                    End If
                End If
            End If

            MatchFilename = False
        End Function

        ''
        ' @brief Find a file inside an in-memory USTAR archive by filename with path normalization.
        ' @param archivePhys Starting physical/virtual address of the TAR archive.
        ' @param filename Target filename to locate (e.g. "user_app.bax" or "./user_app.bax").
        ' @param outSize ByRef parameter receiving the discovered file size in bytes.
        ' @return Pointer to the beginning of the file's data payload, or 0 if not found.
        ''
        Public Unsafe Function FindFile(ByVal archivePhys As UInt64, ByVal filename As Pointer To Byte, ByRef outSize As UInt64) As UInt64
            outSize = 0
            If archivePhys = 0 Or filename = 0 Then
                FindFile = 0
                Exit Function
            End If

            ' Normalize search filename: strip leading "./" or "/"
            Dim searchPtr As Pointer To Byte = filename
            If searchPtr(0) = 46 And searchPtr(1) = 47 Then ' "./"
                searchPtr = searchPtr + 2
            ElseIf searchPtr(0) = 47 Then ' "/"
                searchPtr = searchPtr + 1
            End If

            Dim currentAddr As UInt64 = archivePhys

            Do
                Dim header As Pointer To TarHeader = CPtr(Pointer To TarHeader, currentAddr)

                ' End of archive: header filename begins with null
                If header.FileName(0) = 0 Then
                    Exit Do
                End If

                ' Validate USTAR signature (allow standard "ustar" or all-zeroes legacy tar)
                Dim isUstar As Boolean = (header.Magic(0) = 117 And header.Magic(1) = 115 And header.Magic(2) = 116 And header.Magic(3) = 97 And header.Magic(4) = 114)
                Dim isZeroMagic As Boolean = (header.Magic(0) = 0 And header.Magic(1) = 0)
                If Not isUstar And Not isZeroMagic Then
                    Exit Do
                End If

                ' Parse file size from octal ASCII (offset 124 in TarHeader)
                Dim fileSize As UInt64 = Me.ParseOctal(CPtr(Pointer To Byte, currentAddr + 124), 12)
                Dim fileDataAddr As UInt64 = currentAddr + 512

                ' Normalize filename in tar header (offset 0 in TarHeader)
                Dim tarNamePtr As Pointer To Byte = CPtr(Pointer To Byte, currentAddr)
                If tarNamePtr(0) = 46 And tarNamePtr(1) = 47 Then
                    tarNamePtr = tarNamePtr + 2
                ElseIf tarNamePtr(0) = 47 Then
                    tarNamePtr = tarNamePtr + 1
                End If

                If Me.MatchFilename(tarNamePtr, searchPtr) Then
                    outSize = fileSize
                    FindFile = fileDataAddr
                    Exit Function
                End If

                ' Advance to next 512-byte aligned block: 1 header block + ceil(fileSize / 512) data blocks
                Dim blocks As UInt64 = (fileSize + 511) / 512
                currentAddr = currentAddr + ((blocks + 1) * 512)
            Loop

            FindFile = 0
        End Function

    End Class

End Namespace
