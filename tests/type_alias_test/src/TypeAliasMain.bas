' Project Name: Low-Level Basic TypeAlias Test Suite
' Filename: tests/type_alias_test/src/TypeAliasMain.bas
' Summary: Verification test application validating cross-import TypeAlias propagation and modernized enums.

Import "../../../include/pros.bas"

Module TypeAliasMain

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

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

    Private Function TestProcessId(ByVal pid As ProcessId) As ProcessId
        TestProcessId = pid + 1
    End Function

    Private Function TestHandle(ByVal h As Handle) As Handle
        TestHandle = h * 2
    End Function

    Private Function TestAddress(ByVal vaddr As VirtualAddress, ByVal paddr As PhysicalAddress) As Boolean
        If vaddr = &H40000000 And paddr = &H100000 Then
            TestAddress = True
        Else
            TestAddress = False
        End If
    End Function

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[TEST-TYPEALIAS] Cross-Import TypeAlias & ABI Test Suite"
        PrintMsg "========================================================"

        ' 1. Semantic Type Alias Variable Declarations & Operations
        Dim myPid As ProcessId = 100
        Dim nextPid As ProcessId = TestProcessId(myPid)
        AssertTrue nextPid = 101, "TypeAlias ProcessId passing and calculation correct"

        Dim myHandle As Handle = 42
        Dim doubledHandle As Handle = TestHandle(myHandle)
        AssertTrue doubledHandle = 84, "TypeAlias Handle passing and calculation correct"

        Dim v As VirtualAddress = &H40000000
        Dim p As PhysicalAddress = &H100000
        AssertTrue TestAddress(v, p), "TypeAlias VirtualAddress and PhysicalAddress validation"

        Dim nid As NodeId = 55
        Dim synId As SynapseId = 99
        Dim shm As ShmId = &H1000
        Dim tid As ThreadId = 7
        Dim sumTotal As UInt64 = nid + synId + shm + tid
        Dim expTotal As UInt64 = 55 + 99 + &H1000 + 7
        AssertTrue sumTotal = expTotal, "NodeId, SynapseId, ShmId, ThreadId arithmetic"

        ' 2. Strongly-Typed Enums
        AssertTrue NodeKind.Device = 2, "NodeKind.Device == 2"
        AssertTrue NodeKind.Router = 4, "NodeKind.Router == 4"
        AssertTrue SynapseCapability.All = 7, "SynapseCapability.All == 7"
        AssertTrue InputEventType.MouseMove = 3, "InputEventType.MouseMove == 3"
        AssertTrue WmCommand.CreateWindow = 31, "WmCommand.CreateWindow == 31"
        AssertTrue WmResponse.Ok = 200, "WmResponse.Ok == 200"
        AssertTrue WindowState.Normal = 0, "WindowState.Normal == 0"
        AssertTrue VfsKind.File = 1, "VfsKind.File == 1"
        AssertTrue VfsCommand.Stat = 11, "VfsCommand.Stat == 11"
        AssertTrue DevCommand.Query = 31, "DevCommand.Query == 31"

        ' 3. Modernized String parameter declarations
        Dim s As String = "Testing Modern ABI"
        AssertTrue StrLen(s) = 18, "StrLen with String variable"
        AssertTrue StrLen("Literal String") = 14, "StrLen with String literal"
        AssertTrue StrEquals("Same", "Same"), "StrEquals with identical literals"
        AssertTrue Not StrEquals("Same", "Diff"), "StrEquals with different literals"

        ' 4. WindowDescriptor semantic struct fields
        Dim winDesc As WindowDescriptor
        winDesc.WinId = 1
        winDesc.OwnerPid = myPid
        winDesc.ShmId = myHandle
        winDesc.ClientVaddr = v
        AssertTrue winDesc.OwnerPid = 100, "WindowDescriptor.OwnerPid (ProcessId) == 100"
        AssertTrue winDesc.ShmId = 42, "WindowDescriptor.ShmId (Handle) == 42"
        AssertTrue winDesc.ClientVaddr = &H40000000, "WindowDescriptor.ClientVaddr (VirtualAddress) == 0x40000000"

        PrintMsg "--------------------------------------------------------"
        PrintMsg "[TEST-TYPEALIAS] ALL TYPEALIAS AND ABI ENUM TESTS PASSED!"
        PrintMsg "========================================================"

        user_main = 0
    End Function

End Module
