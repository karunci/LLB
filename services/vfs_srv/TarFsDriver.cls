' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/vfs_srv/TarFsDriver.cls
' Summary: High-performance read-only USTAR initrd filesystem driver for Ring 3 VFS.

Import "../../include/pros.bas"

Namespace Storage.TarFS

    <Packed>
    Public Structure TarBlockHeader
        Public FileName(100) As Byte     ' File path/name (100 bytes)
        Public Mode(8)       As Byte     ' File mode octal (8 bytes)
        Public Uid(8)        As Byte     ' User ID octal (8 bytes)
        Public Gid(8)        As Byte     ' Group ID octal (8 bytes)
        Public FileSize(12)  As Byte     ' Size in bytes octal (12 bytes)
        Public Mtime(12)     As Byte     ' Modification time octal (12 bytes)
        Public Chksum(8)     As Byte     ' Header checksum octal (8 bytes)
        Public TypeFlag      As Byte     ' Link/file type flag ('0'=file, '5'=dir)
        Public LinkName(100) As Byte     ' Linked file name (100 bytes)
        Public Magic(6)      As Byte     ' "ustar\0" (6 bytes)
        Public Version(2)    As Byte     ' USTAR version (2 bytes)
        Public Uname(32)     As Byte     ' User name (32 bytes)
        Public Gname(32)     As Byte     ' Group name (32 bytes)
        Public DevMajor(8)   As Byte     ' Device major number (8 bytes)
        Public DevMinor(8)   As Byte     ' Device minor number (8 bytes)
        Public Prefix(155)   As Byte     ' Filename prefix (155 bytes)
        Public Padding(12)   As Byte     ' Alignment padding to 512 bytes (12 bytes)
    End Structure

    <Packed>
    Public Structure TarIndexedEntry
        Public Path(128)     As Byte     ' Normalized path without leading slash
        Public PathLen       As UInt32
        Public DataPtr       As Pointer To Byte
        Public SizeBytes     As UInt32
        Public IsDirectory   As Boolean
        Public InUse         As Boolean
    End Structure

    <Instancing(SingleUse)>
    Public Class TarFsDriver

        Private Const MAX_TAR_ENTRIES As UInt32 = 128

        Private entries(128) As TarIndexedEntry
        Private entryCount   As UInt32
        Private isMounted    As Boolean

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
                val = (val LShift 3) + UInt64(strPtr(i) - 48)
                i = i + 1
            Wend
            ParseOctal = val
        End Function

        ''
        ' @brief Normalize a USTAR path (converts forward slashes to backslashes, strips leading slash).
        ' @param src Pointer to raw TAR file path.
        ' @param dst Destination buffer.
        ' @param maxLen Maximum capacity.
        ' @return Normalized path length.
        ''
        Private Unsafe Function NormalizeTarPath(ByVal src As Pointer To Byte, ByVal dst As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
            If src = 0 Or dst = 0 Or maxLen = 0 Then
                NormalizeTarPath = 0
                Exit Function
            End If

            Dim rIdx As UInt32 = 0
            While src(rIdx) = 47 Or src(rIdx) = 92 Or src(rIdx) = 46 ' Skip leading '/', '\', '.'
                rIdx = rIdx + 1
            Wend

            Dim wIdx As UInt32 = 0
            While src(rIdx) <> 0 And wIdx + 1 < maxLen
                Dim c As Byte = src(rIdx)
                If c = 47 Then c = 92 ' Unify '/' to '\'
                dst(wIdx) = c
                wIdx = wIdx + 1
                rIdx = rIdx + 1
            Wend

            ' Strip trailing slash on directories for uniform matching
            If wIdx > 0 And dst(wIdx - 1) = 92 Then
                wIdx = wIdx - 1
            End If

            dst(wIdx) = 0
            NormalizeTarPath = wIdx
        End Function

        ''
        ' @brief Mount and index the memory-mapped USTAR archive.
        ' @param vaddr Virtual base address where initrd is mapped (e.g. 0x58000000).
        ' @param sizeBytes Total byte size of the initrd.
        ' @return True if successfully mounted and indexed, False otherwise.
        ''
        Public Unsafe Function Mount(ByVal vaddr As UInt64, ByVal sizeBytes As UInt64) As Boolean
            entryCount = 0
            isMounted = False

            If vaddr = 0 Or sizeBytes < 512 Then
                Mount = False
                Exit Function
            End If

            Dim currentAddr As UInt64 = vaddr
            Dim endAddr As UInt64 = vaddr + sizeBytes

            While currentAddr + 512 <= endAddr And entryCount < MAX_TAR_ENTRIES
                Dim header As Pointer To TarBlockHeader = Pointer To TarBlockHeader(currentAddr)

                ' End of archive is marked by two consecutive 512-byte zero blocks
                If header.FileName(0) = 0 Then
                    Exit While
                End If

                ' Validate USTAR magic ("ustar")
                If header.Magic(0) = 117 And header.Magic(1) = 115 And header.Magic(2) = 116 And _
                   header.Magic(3) = 97  And header.Magic(4) = 114 Then

                    Dim fSize As UInt64 = Me.ParseOctal(@header.FileSize(0), 12)
                    Dim isDir As Boolean = (header.TypeFlag = 53) ' '5' = Directory

                    Dim entry As Pointer To TarIndexedEntry = @entries(entryCount)
                    entry.PathLen = Me.NormalizeTarPath(@header.FileName(0), @entry.Path(0), 128)
                    entry.DataPtr = Pointer To Byte(currentAddr + 512)
                    entry.SizeBytes = UInt32(fSize)
                    entry.IsDirectory = isDir
                    entry.InUse = True

                    entryCount = entryCount + 1

                    ' Advance to next 512-byte aligned record
                    Dim blocks As UInt64 = (fSize + 511) / 512
                    currentAddr = currentAddr + 512 + (blocks * 512)
                Else
                    currentAddr = currentAddr + 512
                End If
            Wend

            isMounted = (entryCount > 0)
            Mount = isMounted
        End Function

        ''
        ' @brief Find an entry by relative normalized path (e.g. "System\Configurations\environment.cfg").
        ' @param path Relative path to look up.
        ' @return Entry index (0..entryCount-1) or -1 if not found.
        ''
        Public Unsafe Function Lookup(ByVal path As String) As Int32
            If Not isMounted Or path = 0 Then
                Lookup = -1
                Exit Function
            End If

            Dim normBuf(128) As Byte
            Dim nLen As UInt32 = Me.NormalizeTarPath(Pointer To Byte(path), @normBuf(0), 128)

            ' Root lookup
            If nLen = 0 Then
                Lookup = -2
                Exit Function
            End If

            Dim i As UInt32
            For i = 0 To entryCount - 1
                Dim entry As Pointer To TarIndexedEntry = @entries(i)
                If entry.InUse And entry.PathLen = nLen Then
                    If StrEquals(@entry.Path(0), @normBuf(0)) Then
                        Lookup = Int32(i)
                        Exit Function
                    End If
                End If
            Next i

            ' Fallback: directory prefix match
            For i = 0 To entryCount - 1
                Dim entry2 As Pointer To TarIndexedEntry = @entries(i)
                If entry2.InUse And entry2.PathLen > nLen And entry2.Path(nLen) = 92 Then
                    If StrStartsWith(@entry2.Path(0), @normBuf(0)) Then
                        Lookup = -2
                        Exit Function
                    End If
                End If
            Next i

            Lookup = -1
        End Function

        ''
        ' @brief Query metadata for an indexed entry.
        ' @param entryIdx Index of the entry (-2 for root/synthetic directory).
        ' @param outKind Receives VFS kind (1 = File, 2 = Directory).
        ' @param outSize Receives file size in bytes.
        ' @param outPerm Receives file permissions (&H0755).
        ' @return True if valid entry index.
        ''
        Public Unsafe Function Stat(ByVal entryIdx As Int32, ByRef outKind As UInt32, ByRef outSize As UInt32, ByRef outPerm As UInt32) As Boolean
            If entryIdx = -2 Then
                outKind = 2 ' VFS_KIND_DIR
                outSize = 0
                outPerm = &H0755
                Stat = True
                Exit Function
            End If

            If entryIdx < 0 Or UInt32(entryIdx) >= entryCount Then
                Stat = False
                Exit Function
            End If

            Dim entry As Pointer To TarIndexedEntry = @entries(entryIdx)
            If entry.IsDirectory Then
                outKind = 2 ' VFS_KIND_DIR
                outSize = 0
                outPerm = &H0755
            Else
                outKind = 1 ' VFS_KIND_FILE
                outSize = entry.SizeBytes
                outPerm = &H0755
            End If
            Stat = True
        End Function

        ''
        ' @brief Read bytes from an indexed file entry.
        ' @param entryIdx Index of the entry.
        ' @param offset Byte offset within the file payload.
        ' @param count Maximum bytes to read.
        ' @param outBuf Destination memory buffer.
        ' @return Number of bytes actually read.
        ''
        Public Unsafe Function Read(ByVal entryIdx As Int32, ByVal offset As UInt32, ByVal count As UInt32, ByVal outBuf As Pointer To Byte) As UInt32
            If entryIdx < 0 Or UInt32(entryIdx) >= entryCount Or outBuf = 0 Then
                Read = 0
                Exit Function
            End If

            Dim entry As Pointer To TarIndexedEntry = @entries(entryIdx)
            If entry.IsDirectory Or offset >= entry.SizeBytes Then
                Read = 0
                Exit Function
            End If

            Dim avail As UInt32 = entry.SizeBytes - offset
            Dim toRead As UInt32 = count
            If toRead > avail Then toRead = avail

            Dim src As Pointer To Byte = entry.DataPtr + offset
            Dim i As UInt32
            For i = 0 To toRead - 1
                outBuf(i) = src(i)
            Next i

            Read = toRead
        End Function

        ''
        ' @brief List direct children of a directory path.
        ' @param dirPath Directory path to inspect (e.g. "System\Apps" or empty string for root).
        ' @param outBuf Buffer receiving null-separated child names.
        ' @param maxLen Maximum byte size of outBuf.
        ' @return Number of child entries found.
        ''
        Public Unsafe Function ListDirectory(ByVal dirPath As String, ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32) As UInt32
            If Not isMounted Or outBuf = 0 Or maxLen = 0 Then
                ListDirectory = 0
                Exit Function
            End If

            Dim normDir(128) As Byte
            Dim dirLen As UInt32 = 0
            If dirPath <> 0 Then
                dirLen = Me.NormalizeTarPath(Pointer To Byte(dirPath), @normDir(0), 128)
            End If

            Dim foundCount As UInt32 = 0
            Dim wIdx As UInt32 = 0

            Dim i As UInt32
            For i = 0 To entryCount - 1
                Dim entry As Pointer To TarIndexedEntry = @entries(i)
                If entry.InUse Then
                    Dim isMatched As Boolean = False
                    Dim childNameStart As UInt32 = 0

                    If dirLen = 0 Then
                        ' Root listing: entry must NOT contain any backslash before its end
                        Dim hasSlash As Boolean = False
                        Dim j As UInt32 = 0
                        While entry.Path(j) <> 0
                            If entry.Path(j) = 92 Then hasSlash = True
                            j = j + 1
                        Wend
                        If Not hasSlash Then
                            isMatched = True
                            childNameStart = 0
                        End If
                    Else
                        ' Child directory listing: must start with normDir + "\"
                        If entry.PathLen > dirLen And entry.Path(dirLen) = 92 Then
                            If StrStartsWith(@entry.Path(0), @normDir(0)) Then
                                ' Ensure it's a direct child (no subsequent slashes)
                                Dim k As UInt32 = dirLen + 1
                                Dim hasSubSlash As Boolean = False
                                While entry.Path(k) <> 0
                                    If entry.Path(k) = 92 Then hasSubSlash = True
                                    k = k + 1
                                Wend
                                If Not hasSubSlash Then
                                    isMatched = True
                                    childNameStart = dirLen + 1
                                End If
                            End If
                        End If
                    End If

                    If isMatched Then
                        ' Append child name + null terminator to outBuf
                        Dim cIdx As UInt32 = childNameStart
                        While entry.Path(cIdx) <> 0 And wIdx + 2 < maxLen
                            outBuf(wIdx) = entry.Path(cIdx)
                            wIdx = wIdx + 1
                            cIdx = cIdx + 1
                        Wend
                        outBuf(wIdx) = 0
                        wIdx = wIdx + 1
                        foundCount = foundCount + 1
                    End If
                End If
            Next

            If wIdx < maxLen Then outBuf(wIdx) = 0
            ListDirectory = foundCount
        End Function

        ''
        ' @brief Get total number of indexed entries in archive.
        ''
        Public Function GetEntryCount() As UInt32
            GetEntryCount = entryCount
        End Function

    End Class

End Namespace
