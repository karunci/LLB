' Project Name: Personal Research Operating System (PROS) / Low-Level Basic
' Filename: include/Version.bas
' Summary: Centralized system-wide build revision, operating system identifiers, and release tags.

Namespace Sys

Module Version
    Public Const SYSTEM_VERSION_TAG As Pointer To Byte = "REV: 2026.10.30-r38-re10"
    Public Const SYSTEM_NAME        As Pointer To Byte = "Personal Research Operating System"
    Public Const SYSTEM_SHORT_NAME  As Pointer To Byte = "PRK-OS"
    Public Const SYSTEM_IDENTIFIER  As Pointer To Byte = "PROS"
    Public Const KERNEL_NAME        As Pointer To Byte = "Personal Research Kernel"
End Module

End Namespace

