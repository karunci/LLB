' Project Name: Low-Level Basic Kernel / llbc
' Filename: src/arch/x86_64/CpuContext.cls
' Workspace Path: tests/kernel/src/arch/x86_64/CpuContext.cls
' Summary: MultiUse Per-CPU execution context and state encapsulation.

Namespace Arch.X86_64

    <Instancing(MultiUse)>
    Public Class CpuContext

        Private cpuId As UInt32
        Private apicId As UInt32
        Private stackBase As UInt64
        Private isOnline As Boolean

        Public Sub Initialize(ByVal id As UInt32, ByVal apic As UInt32, ByVal stack As UInt64)
            cpuId = id
            apicId = apic
            stackBase = stack
            isOnline = True
        End Sub

        Public Function GetCpuId() As UInt32
            GetCpuId = cpuId
        End Function

        Public Function GetApicId() As UInt32
            GetApicId = apicId
        End Function

        Public Function GetStackBase() As UInt64
            GetStackBase = stackBase
        End Function

        Public Function IsCpuOnline() As Boolean
            IsCpuOnline = isOnline
        End Function

    End Class

End Namespace
