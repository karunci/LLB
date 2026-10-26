' Project Name: PROS (Personal Research Operating System)
' Filename: include/pros.bas
' Summary: Standard C-like header declarations for PROS System Library (libpros).
'          Adheres strictly to LLB coding style:
'          - Import for modules
'          - Use for classes
'          - Declare for libraries
'          - Alias for long/mangled names

Module ProsApi

    ' =========================================================================
    ' 1. System Constants & Hardware Values
    ' =========================================================================
    Public Const NODE_KIND_CLIENT       As UInt32 = 1
    Public Const NODE_KIND_SYSTEM       As UInt32 = 1
    Public Const NODE_KIND_DEVICE       As UInt32 = 2
    Public Const NODE_KIND_STORAGE      As UInt32 = 3
    Public Const NODE_KIND_ROUTER       As UInt32 = 4

    Public Const CAP_SYNAPSE_READ       As UInt32 = 1
    Public Const CAP_SYNAPSE_WRITE      As UInt32 = 2
    Public Const CAP_SYNAPSE_NOTIFY     As UInt32 = 4

    Public Const EVENT_KEY_DOWN         As UInt32 = 1
    Public Const EVENT_KEY_UP           As UInt32 = 2
    Public Const EVENT_MOUSE_MOVE       As UInt32 = 3
    Public Const EVENT_MOUSE_BUTTON     As UInt32 = 4

    Public Const INPUT_QUEUE_MAGIC      As UInt64 = &H494E5055545F5155

    ' Nord / Dark System Theme Palette
    Public Const COLOR_BG               As UInt32 = &HFF191D24
    Public Const COLOR_SURFACE          As UInt32 = &HFF232731
    Public Const COLOR_TITLEBAR         As UInt32 = &HFF2E3440
    Public Const COLOR_ACCENT           As UInt32 = &HFF56B6C2
    Public Const COLOR_BORDER_TOP       As UInt32 = &HFF4C566A
    Public Const COLOR_BORDER_BOTTOM    As UInt32 = &HFF1B2028
    Public Const COLOR_TEXT             As UInt32 = &HFFD8DEE9
    Public Const COLOR_BTN_CLOSE        As UInt32 = &HFFBF616A
    Public Const COLOR_BTN_MAX          As UInt32 = &HFF00C853
    Public Const COLOR_BTN_MIN          As UInt32 = &HFF5E81AC

    ' =========================================================================
    ' 2. System Structures
    ' =========================================================================
    <Packed>
    Public Structure AxonPacket
        Public Sequence      As UInt64
        Public PacketType    As UInt32
        Public PayloadLength As UInt32
        Public SourceNode    As UInt64
        Public TargetNode    As UInt64
        Public Payload(255)  As Byte
    End Structure

    <Packed>
    Public Structure InputEvent
        Public Timestamp  As UInt64
        Public EventType  As UInt32
        Public DeviceId   As UInt32
        Public Code       As UInt32
        Public Modifiers  As UInt32
        Public PosX       As Int32
        Public PosY       As Int32
        Public DeltaX     As Int32
        Public DeltaY     As Int32
    End Structure

    <Packed>
    Public Structure SharedInputQueue
        Public Magic      As UInt64
        Public Head       As UInt32
        Public Tail       As UInt32
        Public Capacity   As UInt32
        Public Reserved   As UInt32
        Public Events(63) As InputEvent
    End Structure

    <Packed>
    Public Structure Surface
        Public Width     As UInt32
        Public Height    As UInt32
        Public Pitch     As UInt32
        Public Bpp       As UInt32
        Public Pixels    As Pointer To UInt32
    End Structure

    <Packed>
    Public Structure DisplayInfo
        Public Width    As UInt32
        Public Height   As UInt32
        Public Pitch    As UInt32
        Public Bpp      As UInt32
        Public PhysAddr As UInt64
    End Structure

    ' =========================================================================
    ' 3. Library Declarations (Declare with Alias)
    ' =========================================================================

    ' Process & System Management
    Public Declare Sub ProcessYield Lib "libpros" Alias "Pros_Sys_Process_Yield" ()
    Public Declare Sub ProcessSleep Lib "libpros" Alias "Pros_Sys_Process_Sleep" (ByVal ms As UInt64)
    Public Declare Function GetPid Lib "libpros" Alias "Pros_Sys_Process_GetPid" () As UInt64
    Public Declare Sub TerminateProcess Lib "libpros" Alias "Pros_Sys_Process_ExitProcess" (ByVal exitCode As UInt64)
    Public Declare Function GetCoreCount Lib "libpros" Alias "Pros_Sys_Process_GetCoreCount" () As UInt64
    Public Declare Function GetUptime Lib "libpros" Alias "Pros_Sys_Process_GetUptime" () As UInt64

    ' Console I/O
    Public Declare Sub ConsoleWrite Lib "libpros" Alias "Pros_IO_Console_Write" (ByVal strPtr As Pointer To Byte)
    Public Declare Sub ConsoleWriteLine Lib "libpros" Alias "Pros_IO_Console_WriteLine" (ByVal strPtr As Pointer To Byte)
    Public Declare Sub ConsolePrintWithUInt Lib "libpros" Alias "Pros_IO_Console_PrintWithUInt" (ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)

    ' Neural Nodes & Synapses
    Public Declare Function NodeRegister Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Register" (ByVal kind As UInt32, ByVal namePtr As Pointer To Byte, ByVal caps As UInt32) As UInt64
    Public Declare Function NodeLookup Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Lookup" (ByVal namePtr As Pointer To Byte) As UInt64
    Public Declare Function SynapseConnect Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Connect" (ByVal srcNodeId As UInt64, ByVal targetNodeId As UInt64, ByVal caps As UInt32) As UInt64
    Public Declare Function SynapsePush Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Push" (ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean
    Public Declare Function SynapsePop Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Pop" (ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean
    Public Declare Function SynapsePopWait Lib "libpros" Alias "Pros_Nodes_NodeRegistry_PopWait" (ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean

    ' Zero-Copy Shared Memory
    Public Declare Function ShmemCreate Lib "libpros" Alias "Pros_Memory_Shmem_Create" (ByVal sizeBytes As UInt64, ByVal targetVaddr As UInt64) As UInt64
    Public Declare Function ShmemAttach Lib "libpros" Alias "Pros_Memory_Shmem_Attach" (ByVal shmid As UInt64, ByVal targetVaddr As UInt64) As UInt64
    Public Declare Function ShmemDetach Lib "libpros" Alias "Pros_Memory_Shmem_Detach" (ByVal shmid As UInt64) As Boolean

    ' GUI & 2D Surface Blitting
    Public Declare Sub FillRect Lib "libpros" Alias "Pros_Gui_Graphics_FillRect" (ByRef surf As Surface, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32, ByVal color As UInt32)
    Public Declare Sub Blit Lib "libpros" Alias "Pros_Gui_Graphics_Blit" (ByRef dst As Surface, ByVal dx As Int32, ByVal dy As Int32, ByRef src As Surface, ByVal sx As Int32, ByVal sy As Int32, ByVal w As Int32, ByVal h As Int32)

    <Packed>
    Public Structure MouseState
        Public X As Int32
        Public Y As Int32
        Public Buttons As Byte
        Public Reserved1 As Byte
        Public Reserved2 As Byte
        Public Reserved3 As Byte
    End Structure

    ' Hardware Display Driver APIs
    Public Declare Function GetDisplayInfo Lib "libpros" Alias "Pros_Driver_Display_GetInfo" (ByRef info As DisplayInfo) As Boolean
    Public Declare Function MapFramebuffer Lib "libpros" Alias "Pros_Driver_Display_Map" (ByVal targetVaddr As UInt64) As Pointer To UInt32

    ' Hardware Input APIs
    Public Declare Function GetMouseState Lib "libpros" Alias "Pros_Inputs_DeviceInput_GetMouseState" (ByRef state As MouseState) As Boolean

    ' Virtual File System (VFS) APIs
    <Packed>
    Public Structure FileStat
        Public SizeBytes As UInt32
        Public Kind      As UInt32
        Public Perms     As UInt32
        Public Status    As UInt32
    End Structure
    Public Declare Function VfsStat Lib "libpros" Alias "Pros_Storage_VfsClient_Stat" (ByVal pathPtr As Pointer To Byte, ByRef outStat As FileStat) As Boolean

    ' Window Management APIs
    Public Declare Function WmRequestFocus Lib "libpros" Alias "Pros_Gui_WindowManagerClient_RequestFocus" (ByVal winId As UInt32) As Boolean

    ' Device Management APIs
    <Packed>
    Public Structure DeviceInfo
        Public Id        As UInt32
        Public Kind      As UInt32
        Public Status    As UInt32
        Public Reserved  As UInt32
        Public BaseAddr  As UInt64
    End Structure
    Public Declare Function DevQueryDevice Lib "libpros" Alias "Pros_Devices_DeviceClient_QueryDevice" (ByVal namePtr As Pointer To Byte, ByRef outInfo As DeviceInfo) As Boolean

    ' Service Supervision APIs
    Public Declare Function PlexusIsServiceActive Lib "libpros" Alias "Pros_Services_ServiceSupervisorClient_IsServiceActive" (ByVal serviceName As Pointer To Byte) As Boolean

End Module

