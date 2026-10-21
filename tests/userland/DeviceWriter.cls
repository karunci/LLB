' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/DeviceWriter.cls
' Summary: MultiUse class implementing IWriter interface fixture.

<Instancing(MultiUse)>
Class DeviceWriter
    Implements IWriter

    Public m_written As Int32

    Public Sub Initialize(ByVal initialVal As Int32)
        Me.m_written = initialVal
    End Sub

    Public Function WriteData(ByVal val As Int32) As Int32
        Me.m_written = Me.m_written + val
        WriteData = Me.m_written
    End Function

    Public Sub ResetDevice()
        Me.m_written = 0
    End Sub

End Class
