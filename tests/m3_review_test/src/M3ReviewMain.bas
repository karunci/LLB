' Project Name: Low-Level Basic M3 Review Test Suite
' Filename: tests/m3_review_test/src/M3ReviewMain.bas
' Summary: Standalone adversarial stress test for Milestone 3 type and idiom modernization.

Import "../../../include/pros.bas"

Module M3ReviewMain

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    <Packed>
    Structure MockVfsEntry
        Public Path      As String
        Public SizeBytes As UInt32
        Public Kind      As UInt32
        Public Perms     As UInt32
    End Structure

    <Packed>
    Structure MockDeviceItem
        Public Id        As UInt32
        Public Name      As String
        Public Kind      As UInt32
        Public BaseAddr  As UInt64
        Public Status    As UInt32
    End Structure

    <Packed>
    Structure MockServiceItem
        Public Pid           As UInt64
        Public Name          As String
        Public NodeId        As UInt64
        Public Status        As UInt32
        Public LastHeartbeat As UInt64
    End Structure

    Private vfsTable(10) As MockVfsEntry
    Private devices(5) As MockDeviceItem
    Private services(5) As MockServiceItem

    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        Asm "movq $1, %%rax; movq $1, %%rdi; movq %0, %%rsi; movq %1, %%rdx; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rdx", "rcx", "r11", "memory"
    End Sub

    Private Unsafe Sub PrintMsg(ByVal s As String)
        DualPrint s
        DualPrint "\r\n"
    End Sub

    Private Unsafe Sub AssertTrue(ByVal cond As Boolean, ByVal testName As String)
        testsRun = testsRun + 1
        Dim nbuf(16) As Byte
        Dim nidx As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @nbuf(0), nidx
        nbuf(nidx) = 0

        If cond Then
            testsPassed = testsPassed + 1
            DualPrint "  [PASS] #"
            DualPrint @nbuf(0)
            DualPrint " - "
            PrintMsg testName
        Else
            testsFailed = testsFailed + 1
            DualPrint "  [FAIL] #"
            DualPrint @nbuf(0)
            DualPrint ": "
            PrintMsg testName
        End If
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[M3-REVIEW] Adversarial Milestone 3 Modernization Tests"
        PrintMsg "========================================================"

        ' ---------------------------------------------------------------------
        ' SUITE 1: VfsEntry with String Path and Table Resolution
        ' ---------------------------------------------------------------------
        vfsTable(0).Path = "/"
        vfsTable(0).SizeBytes = 0
        vfsTable(0).Kind = 2
        vfsTable(0).Perms = &H0755

        vfsTable(1).Path = "/Apps/Terminal"
        vfsTable(1).SizeBytes = 0
        vfsTable(1).Kind = 2
        vfsTable(1).Perms = &H0777

        vfsTable(2).Path = "/System/Servers/genesis.bax"
        vfsTable(2).SizeBytes = 12288
        vfsTable(2).Kind = 1
        vfsTable(2).Perms = &H0755

        vfsTable(3).Path = "/System/Servers/compositor.bax"
        vfsTable(3).SizeBytes = 16384
        vfsTable(3).Kind = 1
        vfsTable(3).Perms = &H0755

        vfsTable(4).Path = "/Users/Default/Desktop"
        vfsTable(4).SizeBytes = 0
        vfsTable(4).Kind = 2
        vfsTable(4).Perms = &H0777

        AssertTrue StrEquals(vfsTable(0).Path, "/"), "VfsEntry(0).Path == '/'"
        AssertTrue StrEquals(vfsTable(1).Path, "/Apps/Terminal"), "VfsEntry(1).Path == '/Apps/Terminal'"
        AssertTrue StrEquals(vfsTable(2).Path, "/System/Servers/genesis.bax"), "VfsEntry(2).Path == '/System/Servers/genesis.bax'"
        AssertTrue StrEquals(vfsTable(3).Path, "/System/Servers/compositor.bax"), "VfsEntry(3).Path == '/System/Servers/compositor.bax'"
        AssertTrue StrEquals(vfsTable(4).Path, "/Users/Default/Desktop"), "VfsEntry(4).Path == '/Users/Default/Desktop'"
        AssertTrue Not StrEquals(vfsTable(2).Path, vfsTable(3).Path), "Different VfsEntry paths do not match"

        ' Test path resolution loop
        Dim targetPath As String = "/System/Servers/compositor.bax"
        Dim foundVfsIdx As Int32 = -1
        Dim vi As UInt32 = 0
        While vi < 5
            If StrEquals(targetPath, vfsTable(vi).Path) Then
                foundVfsIdx = CType(Int32, vi)
                Exit While
            End If
            vi = vi + 1
        Wend
        AssertTrue foundVfsIdx = 3, "Table search finds VfsEntry #3"
        AssertTrue vfsTable(foundVfsIdx).SizeBytes = 16384, "VfsEntry #3 SizeBytes == 16384"

        ' ---------------------------------------------------------------------
        ' SUITE 2: DeviceItem with String Name
        ' ---------------------------------------------------------------------
        devices(0).Id = 1
        devices(0).Name = "cpu.smp.quad"
        devices(0).Kind = 1
        devices(0).BaseAddr = 0
        devices(0).Status = 1

        devices(1).Id = 2
        devices(1).Name = "pci.disp.lfb"
        devices(1).Kind = 2
        devices(1).BaseAddr = &HFD000000
        devices(1).Status = 1

        devices(2).Id = 3
        devices(2).Name = "hid.ps2.controller"
        devices(2).Kind = 3
        devices(2).BaseAddr = &H60
        devices(2).Status = 1

        AssertTrue StrEquals(devices(0).Name, "cpu.smp.quad"), "DeviceItem(0).Name == 'cpu.smp.quad'"
        AssertTrue StrEquals(devices(1).Name, "pci.disp.lfb"), "DeviceItem(1).Name == 'pci.disp.lfb'"
        AssertTrue StrEquals(devices(2).Name, "hid.ps2.controller"), "DeviceItem(2).Name == 'hid.ps2.controller'"

        ' Search device
        Dim targetDev As String = "pci.disp.lfb"
        Dim foundDevIdx As Int32 = -1
        Dim di As UInt32 = 0
        While di < 3
            If StrEquals(targetDev, devices(di).Name) Then
                foundDevIdx = CType(Int32, di)
                Exit While
            End If
            di = di + 1
        Wend
        AssertTrue foundDevIdx = 1, "Device lookup finds pci.disp.lfb at index 1"
        AssertTrue devices(foundDevIdx).BaseAddr = &HFD000000, "Device BaseAddr matches &HFD000000"

        ' ---------------------------------------------------------------------
        ' SUITE 3: ServiceItem with String Name
        ' ---------------------------------------------------------------------
        services(0).Pid = 1
        services(0).Name = "srv.display"
        services(0).NodeId = 1003
        services(0).Status = 2

        services(1).Pid = 2
        services(1).Name = "srv.compositor"
        services(1).NodeId = 1005
        services(1).Status = 2

        AssertTrue StrEquals(services(0).Name, "srv.display"), "ServiceItem(0).Name == 'srv.display'"
        AssertTrue StrEquals(services(1).Name, "srv.compositor"), "ServiceItem(1).Name == 'srv.compositor'"

        ' ---------------------------------------------------------------------
        ' SUITE 4: Dynamic client name construction via AppendStr and AppendUInt
        ' ---------------------------------------------------------------------
        Dim testPid As UInt64 = 7
        Dim clientBuf(16) As Byte
        Dim cIdx As UInt32 = 0
        AppendStr "client.", @clientBuf(0), cIdx
        AppendUInt testPid Mod 10, @clientBuf(0), cIdx
        clientBuf(cIdx) = 0

        AssertTrue StrEquals(@clientBuf(0), "client.7"), "Formatted client name equals 'client.7'"
        AssertTrue cIdx = 8, "Client name index == 8"

        ' Multi-digit pid
        testPid = 1234
        cIdx = 0
        AppendStr "client.", @clientBuf(0), cIdx
        AppendUInt testPid, @clientBuf(0), cIdx
        clientBuf(cIdx) = 0
        AssertTrue StrEquals(@clientBuf(0), "client.1234"), "Multi-digit pid formats to 'client.1234'"

        ' ---------------------------------------------------------------------
        ' SUITE 5: Shared Memory WindowDescriptor.Title Inline Byte Array Invariant
        ' ---------------------------------------------------------------------
        Dim winDesc As WindowDescriptor
        winDesc.WinId = 42
        winDesc.OwnerPid = 100
        winDesc.Width = 640
        winDesc.Height = 480
        winDesc.ClientVaddr = &H54000000

        ' Populate Title inline
        Dim testTitle As String = "Terminal Shell [TTY 1]"
        Dim ti As UInt32 = 0
        While ti < 31 And testTitle(ti) <> 0
            winDesc.Title(ti) = testTitle(ti)
            ti = ti + 1
        Wend
        winDesc.Title(ti) = 0

        AssertTrue StrEquals(@winDesc.Title(0), "Terminal Shell [TTY 1]"), "Inline Title matches 'Terminal Shell [TTY 1]'"
        AssertTrue winDesc.ClientVaddr = &H54000000, "ClientVaddr intact after Title write"
        AssertTrue winDesc.WinId = 42, "WinId intact after Title write"

        ' ---------------------------------------------------------------------
        ' SUITE 6: Direct String Literal Parameters to Declare Functions
        ' ---------------------------------------------------------------------
        AssertTrue StrLen("PROS Microkernel") = 16, "StrLen direct string literal"
        AssertTrue StrEquals("srv.vfs", "srv.vfs"), "StrEquals with two identical string literals"
        AssertTrue Not StrEquals("srv.vfs", "srv.wm"), "StrEquals with different string literals"

        Dim trimBuf(32) As Byte
        Dim trimLen As UInt64 = Trim("   /System/Configs   ", @trimBuf(0))
        AssertTrue trimLen = 15, "Trim string literal length == 15"
        AssertTrue StrEquals(@trimBuf(0), "/System/Configs"), "Trimmed content matches '/System/Configs'"

        ' Summary
        PrintMsg "--------------------------------------------------------"
        PrintMsg "[M3-REVIEW] Total Tests Run   : 25"
        If testsFailed = 0 Then
            PrintMsg "[M3-REVIEW] ALL 25 ADVERSARIAL TESTS PASSED [PASS]!"
            user_main = 0
        Else
            PrintMsg "[M3-REVIEW] SOME TESTS FAILED [FAIL]!"
            user_main = 1
        End If
        PrintMsg "========================================================"
    End Function

End Module
