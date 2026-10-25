' Project Name: LibPROS / Low-Level Basic
' Filename: lib/pros/src/Display.bas
' Summary: Hardware display driver support and framebuffer aperture mapping.

Import Pros.Sys
Import Pros.Sys.RawSyscall

Namespace Pros.Driver

    <Packed>
    Public Structure DisplayInfo
        Public Width    As UInt32
        Public Height   As UInt32
        Public Pitch    As UInt32
        Public Bpp      As UInt32
        Public PhysAddr As UInt64
    End Structure

    Public Module Display

        ''
        ' @brief Query active display resolution and framebuffer geometry.
        ' @param info Reference to DisplayInfo structure to fill.
        ' @return True if display information was successfully retrieved.
        ''
        Public Unsafe Function GetInfo(ByRef info As DisplayInfo) As Boolean
            Dim infoPtr As UInt64 = CType(UInt64, AddressOf info)
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call1(SYS_FB_GET_INFO, infoPtr)
            GetInfo = (res = 1)
        End Function

        ''
        ' @brief Map linear framebuffer memory aperture into calling process space.
        ' @param targetVaddr Desired virtual address in userspace (e.g. 0x78000000).
        ' @return Pointer to mapped 32-bit pixel buffer, or 0 on failure.
        ''
        Public Unsafe Function Map(ByVal targetVaddr As UInt64) As Pointer To UInt32
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call1(SYS_FB_MAP, targetVaddr)
            If res = 1 Then
                Map = CPtr(Pointer To UInt32, targetVaddr)
            Else
                Map = CPtr(Pointer To UInt32, 0)
            End If
        End Function

    End Module

End Namespace
