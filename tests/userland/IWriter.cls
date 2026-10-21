' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/userland/IWriter.cls
' Summary: Interface declaration for IWriter.

Interface IWriter
    Function WriteData(ByVal val As Int32) As Int32
    Sub ResetDevice()
End Interface
