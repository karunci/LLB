' Project Name: Low-Level Basic Empirical Challenge ABI Test Suite
' Filename: tests/challenge_abi_test/src/ChallengeMain.bas
' Summary: Comprehensive adversarial stress test for TypeAliases, enums, null string semantics, and ABI safety.

Import "../../../include/pros.bas"

Module ChallengeAbiMain

    TypeAlias Level1 = UInt64
    TypeAlias Level2 = Level1
    TypeAlias Level3 = Level2

    Dim g_passCount As UInt32 = 0
    Dim g_failCount As UInt32 = 0

    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        ' Microkernel syscall 1
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        ' Linux stdout syscall 1
        Asm "movq $1, %%rax; movq $1, %%rdi; movq %0, %%rsi; movq %1, %%rdx; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rdx", "rcx", "r11", "memory"
    End Sub

    Private Unsafe Sub PrintMsg(ByVal s As String)
        DualPrint s
        DualPrint "\r\n"
    End Sub

    Unsafe Sub AssertBool(ByVal cond As Boolean, ByVal name As String)
        If cond Then
            g_passCount = g_passCount + 1
            DualPrint "  [PASS] "
            PrintMsg name
        Else
            g_failCount = g_failCount + 1
            DualPrint "  [FAIL] "
            PrintMsg name
        End If
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[CHALLENGE-ABI] Adversarial ABI & Type Stress Test Suite"
        PrintMsg "========================================================"

        ' ---------------------------------------------------------------------
        ' Section 1: Chained TypeAliases, Pointers & Arrays
        ' ---------------------------------------------------------------------
        Dim val3 As Level3 = 987654321
        AssertBool val3 = 987654321, "#1 - Level3 chained TypeAlias value correct"

        Dim pVal As Pointer To Level3 = AddressOf(val3)
        pVal(0) = 11223344
        AssertBool val3 = 11223344, "#2 - Pointer To Level3 dereference and mutation"

        Dim arr(4) As Level2
        arr(0) = 100
        arr(1) = 200
        arr(2) = 300
        arr(3) = 400
        Dim sumArr As Level1 = arr(0) + arr(1) + arr(2) + arr(3)
        AssertBool sumArr = 1000, "#3 - Array of TypeAlias elements sum correctly"

        ' ---------------------------------------------------------------------
        ' Section 2: Imported Semantic TypeAliases
        ' ---------------------------------------------------------------------
        Dim pid As ProcessId = 55
        Dim tid As ThreadId = 77
        Dim hnd As Handle = &HDEADBEEF
        Dim vaddr As VirtualAddress = &H70000000
        Dim paddr As PhysicalAddress = &H8000000
        Dim nid As NodeId = 1005
        Dim synId As SynapseId = 5012
        Dim shm As ShmId = 9

        Dim combined As UInt64 = pid + tid + nid + synId + shm
        AssertBool combined = 55 + 77 + 1005 + 5012 + 9, "#4 - Arithmetic across 5 distinct semantic TypeAliases"
        AssertBool hnd = &HDEADBEEF, "#5 - Handle 64-bit value preservation"
        AssertBool vaddr = &H70000000, "#6 - VirtualAddress preservation"
        AssertBool paddr = &H8000000, "#7 - PhysicalAddress preservation"

        ' ---------------------------------------------------------------------
        ' Section 3: Strongly-Typed Public Enums
        ' ---------------------------------------------------------------------
        AssertBool NodeKind.Client = 1, "#8 - NodeKind.Client == 1"
        AssertBool NodeKind.Device = 2, "#9 - NodeKind.Device == 2"
        AssertBool NodeKind.Storage = 3, "#10 - NodeKind.Storage == 3"
        AssertBool NodeKind.Router = 4, "#11 - NodeKind.Router == 4"

        AssertBool SynapseCapability.Read = 1, "#12 - SynapseCapability.Read == 1"
        AssertBool SynapseCapability.Write = 2, "#13 - SynapseCapability.Write == 2"
        AssertBool SynapseCapability.Notify = 4, "#14 - SynapseCapability.Notify == 4"
        AssertBool SynapseCapability.All = 7, "#15 - SynapseCapability.All == 7"

        AssertBool InputEventType.KeyDown = 1, "#16 - InputEventType.KeyDown == 1"
        AssertBool InputEventType.KeyUp = 2, "#17 - InputEventType.KeyUp == 2"
        AssertBool InputEventType.MouseMove = 3, "#18 - InputEventType.MouseMove == 3"
        AssertBool InputEventType.MouseButton = 4, "#19 - InputEventType.MouseButton == 4"

        AssertBool WmCommand.CreateWindow = 31, "#20 - WmCommand.CreateWindow == 31"
        AssertBool WmCommand.DestroyWindow = 32, "#21 - WmCommand.DestroyWindow == 32"
        AssertBool WmCommand.WindowDirty = 35, "#22 - WmCommand.WindowDirty == 35"
        AssertBool WmResponse.Ok = 200, "#23 - WmResponse.Ok == 200"
        AssertBool WmResponse.Error = 201, "#24 - WmResponse.Error == 201"
        AssertBool WindowState.Normal = 0, "#25 - WindowState.Normal == 0"
        AssertBool WindowState.Minimized = 1, "#26 - WindowState.Minimized == 1"
        AssertBool WindowState.Maximized = 2, "#27 - WindowState.Maximized == 2"

        AssertBool VfsKind.File = 1, "#28 - VfsKind.File == 1"
        AssertBool VfsKind.Directory = 2, "#29 - VfsKind.Directory == 2"
        AssertBool VfsKind.Device = 3, "#30 - VfsKind.Device == 3"
        AssertBool VfsCommand.Lookup = 10, "#31 - VfsCommand.Lookup == 10"
        AssertBool VfsCommand.Stat = 11, "#32 - VfsCommand.Stat == 11"
        AssertBool VfsCommand.List = 12, "#33 - VfsCommand.List == 12"
        AssertBool VfsResponse.Ok = 100, "#34 - VfsResponse.Ok == 100"
        AssertBool VfsResponse.Error = 101, "#35 - VfsResponse.Error == 101"

        AssertBool DevCommand.GetTree = 30, "#36 - DevCommand.GetTree == 30"
        AssertBool DevCommand.Query = 31, "#37 - DevCommand.Query == 31"
        AssertBool DevResponse.Ok = 300, "#38 - DevResponse.Ok == 300"
        AssertBool DevResponse.Error = 301, "#39 - DevResponse.Error == 301"

        AssertBool PlexusCommand.Status = 40, "#40 - PlexusCommand.Status == 40"
        AssertBool PlexusCommand.Ping = 41, "#41 - PlexusCommand.Ping == 41"
        AssertBool PlexusResponse.Ok = 400, "#42 - PlexusResponse.Ok == 400"
        AssertBool PlexusResponse.Error = 401, "#43 - PlexusResponse.Error == 401"

        AssertBool SyscallNumber.ConsoleWrite = 1, "#44 - SyscallNumber.ConsoleWrite == 1"
        AssertBool SyscallNumber.ProcessYield = 2, "#45 - SyscallNumber.ProcessYield == 2"
        AssertBool SyscallNumber.ProcessSleep = 3, "#46 - SyscallNumber.ProcessSleep == 3"
        AssertBool SyscallNumber.ProcessGetPid = 6, "#47 - SyscallNumber.ProcessGetPid == 6"
        AssertBool SyscallNumber.ProcessExit = 16, "#48 - SyscallNumber.ProcessExit == 16"
        AssertBool SyscallNumber.MemAllocPages = 26, "#49 - SyscallNumber.MemAllocPages == 26"
        AssertBool SyscallNumber.TimeUptime = 28, "#50 - SyscallNumber.TimeUptime == 28"
        AssertBool SyscallNumber.SmpCoreCount = 34, "#51 - SyscallNumber.SmpCoreCount == 34"
        AssertBool SyscallNumber.NodeRegister = 50, "#52 - SyscallNumber.NodeRegister == 50"
        AssertBool SyscallNumber.SynapseConnect = 51, "#53 - SyscallNumber.SynapseConnect == 51"
        AssertBool SyscallNumber.SynapsePush = 52, "#54 - SyscallNumber.SynapsePush == 52"
        AssertBool SyscallNumber.SynapsePop = 53, "#55 - SyscallNumber.SynapsePop == 53"
        AssertBool SyscallNumber.NodeLookup = 55, "#56 - SyscallNumber.NodeLookup == 55"
        AssertBool SyscallNumber.ShmemCreate = 60, "#57 - SyscallNumber.ShmemCreate == 60"
        AssertBool SyscallNumber.ShmemAttach = 61, "#58 - SyscallNumber.ShmemAttach == 61"
        AssertBool SyscallNumber.ShmemDetach = 62, "#59 - SyscallNumber.ShmemDetach == 62"
        AssertBool SyscallNumber.FbGetInfo = 70, "#60 - SyscallNumber.FbGetInfo == 70"
        AssertBool SyscallNumber.FbMap = 71, "#61 - SyscallNumber.FbMap == 71"

        ' ---------------------------------------------------------------------
        ' Section 4: Adversarial String & Null Checking Semantics
        ' ---------------------------------------------------------------------
        Dim sNull As String = 0
        Dim sText As String = "adversarial"
        Dim sEmpty As String = ""

        Dim isNull1 As Boolean = (sNull = 0)
        Dim isNull2 As Boolean = (0 = sNull)
        Dim notNull1 As Boolean = (sNull <> 0)
        Dim notNull2 As Boolean = (0 <> sNull)
        AssertBool isNull1, "#62 - sNull = 0 is True"
        AssertBool isNull2, "#63 - 0 = sNull is True"
        AssertBool notNull1 = False, "#64 - sNull <> 0 is False"
        AssertBool notNull2 = False, "#65 - 0 <> sNull is False"

        Dim textIsNull1 As Boolean = (sText = 0)
        Dim textIsNull2 As Boolean = (0 = sText)
        Dim textNotNull1 As Boolean = (sText <> 0)
        Dim textNotNull2 As Boolean = (0 <> sText)
        AssertBool textIsNull1 = False, "#66 - sText = 0 is False"
        AssertBool textIsNull2 = False, "#67 - 0 = sText is False"
        AssertBool textNotNull1, "#68 - sText <> 0 is True"
        AssertBool textNotNull2, "#69 - 0 <> sText is True"

        Dim eqEmpty As Boolean = (sText = "")
        Dim neqEmpty As Boolean = (sText <> "")
        AssertBool eqEmpty = False, "#70 - sText = '' is False"
        AssertBool neqEmpty, "#71 - sText <> '' is True"

        ' Standard library null safety:
        AssertBool StrLen(sNull) = 0, "#72 - StrLen(sNull) == 0"
        AssertBool StrLen(sText) = 11, "#73 - StrLen('adversarial') == 11"
        AssertBool StrEquals(sNull, sNull), "#74 - StrEquals(sNull, sNull) == True"
        AssertBool StrEquals(sNull, sText) = False, "#75 - StrEquals(sNull, sText) == False"
        AssertBool StrEquals(sText, sNull) = False, "#76 - StrEquals(sText, sNull) == False"
        AssertBool StrEquals(sText, "adversarial"), "#77 - StrEquals(sText, 'adversarial') == True"

        Dim buf(32) As Byte
        Dim outIdx As UInt32 = 0
        AppendStr sNull, AddressOf(buf(0)), outIdx
        AssertBool outIdx = 0, "#78 - AppendStr(sNull) does not alter outIdx"

        Dim trimLen As UInt64 = Trim(sNull, AddressOf(buf(0)))
        AssertBool trimLen = 0, "#79 - Trim(sNull) returns 0"

        ' ---------------------------------------------------------------------
        ' Section 5: Modernized WindowDescriptor Struct
        ' ---------------------------------------------------------------------
        Dim desc As WindowDescriptor
        desc.WinId = 101
        desc.OwnerPid = 202
        desc.ShmId = 303
        desc.ClientVaddr = &H48000000
        desc.X = 50
        desc.Y = 60
        desc.Width = 800
        desc.Height = 600
        desc.State = WindowState.Normal

        AssertBool desc.WinId = 101, "#80 - WindowDescriptor.WinId == 101"
        AssertBool desc.OwnerPid = 202, "#81 - WindowDescriptor.OwnerPid == 202"
        AssertBool desc.ShmId = 303, "#82 - WindowDescriptor.ShmId == 303"
        AssertBool desc.ClientVaddr = &H48000000, "#83 - WindowDescriptor.ClientVaddr == 0x48000000"
        AssertBool desc.Width = 800, "#84 - WindowDescriptor.Width == 800"
        AssertBool desc.State = WindowState.Normal, "#85 - WindowDescriptor.State == WindowState.Normal"

        PrintMsg "--------------------------------------------------------"
        If g_failCount = 0 Then
            PrintMsg "[CHALLENGE-ABI] ALL 85 ADVERSARIAL STRESS TESTS PASSED!"
        Else
            PrintMsg "[CHALLENGE-ABI] ADVERSARIAL FAILURES DETECTED!"
        End If
        PrintMsg "========================================================"

        user_main = g_failCount
    End Function

End Module
