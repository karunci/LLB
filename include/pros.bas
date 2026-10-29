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
    ' 0. Semantic Type Aliases for Kernel & ABI Types
    ' =========================================================================
    TypeAlias ProcessId       = UInt64
    TypeAlias ThreadId        = UInt64
    TypeAlias Handle          = UInt64
    TypeAlias NodeId          = UInt64
    TypeAlias SynapseId       = UInt64
    TypeAlias ShmId           = UInt64
    TypeAlias VirtualAddress  = UInt64
    TypeAlias PhysicalAddress = UInt64

    ' =========================================================================
    ' 1. System Constants, Hardware Values & Strongly-Typed Enums
    ' =========================================================================

    ' Node Hierarchy Kinds
    Public Enum NodeKind
        Client  = 1
        System  = 1
        Device  = 2
        Storage = 3
        Router  = 4
    End Enum

    Public Const NODE_KIND_CLIENT       As UInt32 = 1
    Public Const NODE_KIND_SYSTEM       As UInt32 = 1
    Public Const NODE_KIND_DEVICE       As UInt32 = 2
    Public Const NODE_KIND_STORAGE      As UInt32 = 3
    Public Const NODE_KIND_ROUTER       As UInt32 = 4

    ' Synapse Channel Capability Bitmasks
    Public Enum SynapseCapability
        Read   = 1
        Write  = 2
        Notify = 4
        All    = 7
    End Enum

    Public Const CAP_SYNAPSE_READ       As UInt32 = 1
    Public Const CAP_SYNAPSE_WRITE      As UInt32 = 2
    Public Const CAP_SYNAPSE_NOTIFY     As UInt32 = 4

    ' Hardware & GUI Input Event Types
    Public Enum InputEventType
        KeyDown     = 1
        KeyUp       = 2
        MouseMove   = 3
        MouseButton = 4
    End Enum

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

    ' Window Manager Protocol Commands & Responses
    Public Enum WmCommand
        SetFocus       = 22
        MoveWindow     = 23
        ResizeWindow   = 24
        MinimizeWindow = 25
        MaximizeWindow = 26
        RestoreWindow  = 27
        RegisterTable  = 30
        CreateWindow   = 31
        DestroyWindow  = 32
        MouseEvent     = 33
        SetCursor      = 34
        WindowDirty    = 35
    End Enum

    Public Enum WmResponse
        Ok    = 200
        Error = 201
    End Enum

    Public Const WM_CMD_REGISTER_TABLE  As UInt32 = 30
    Public Const WM_CMD_CREATE_WINDOW   As UInt32 = 31
    Public Const WM_CMD_DESTROY_WINDOW  As UInt32 = 32
    Public Const WM_CMD_SET_FOCUS       As UInt32 = 22
    Public Const WM_CMD_MOVE_WINDOW     As UInt32 = 23
    Public Const WM_CMD_RESIZE_WINDOW   As UInt32 = 24
    Public Const WM_CMD_MINIMIZE_WINDOW As UInt32 = 25
    Public Const WM_CMD_MAXIMIZE_WINDOW As UInt32 = 26
    Public Const WM_CMD_RESTORE_WINDOW  As UInt32 = 27
    Public Const WM_CMD_MOUSE_EVENT     As UInt32 = 33
    Public Const WM_CMD_SET_CURSOR      As UInt32 = 34
    Public Const WM_CMD_WINDOW_DIRTY    As UInt32 = 35

    Public Const WM_RESP_OK             As UInt32 = 200
    Public Const WM_RESP_ERROR          As UInt32 = 201

    Public Const MAX_WINDOWS            As UInt32 = 16

    ' Window Presentation States
    Public Enum WindowState
        Normal    = 0
        Minimized = 1
        Maximized = 2
    End Enum

    Public Const WIN_STATE_NORMAL       As Int32 = 0
    Public Const WIN_STATE_MINIMIZED    As Int32 = 1
    Public Const WIN_STATE_MAXIMIZED    As Int32 = 2

    ' Virtual File System Enums
    Public Enum VfsKind
        File      = 1
        Directory = 2
        Device    = 3
    End Enum

    Public Enum VfsCommand
        Lookup = 10
        Stat   = 11
        List   = 12
    End Enum

    Public Enum VfsResponse
        Ok    = 100
        Error = 101
    End Enum

    ' Device Management Enums
    Public Enum DevCommand
        GetTree = 30
        Query   = 31
    End Enum

    Public Enum DevResponse
        Ok    = 300
        Error = 301
    End Enum

    ' Service Supervisor Enums
    Public Enum PlexusCommand
        Status = 40
        Ping   = 41
    End Enum

    Public Enum PlexusResponse
        Ok    = 400
        Error = 401
    End Enum

    ' System Call Numbers
    Public Enum SyscallNumber
        ConsoleWrite   = 1
        ProcessYield   = 2
        ProcessSleep   = 3
        ProcessGetPid  = 6
        ProcessExit    = 16
        GetMouse       = 19
        MemAllocPages  = 26
        TimeUptime     = 28
        SmpCoreCount   = 34
        NodeRegister   = 50
        SynapseConnect = 51
        SynapsePush    = 52
        SynapsePop     = 53
        NodeLookup     = 55
        ShmemCreate    = 60
        ShmemAttach    = 61
        ShmemDetach    = 62
        FbGetInfo      = 70
        FbMap          = 71
    End Enum

    ' =========================================================================
    ' 2. System Structures
    ' =========================================================================
    <Packed>
    Public Structure WindowDescriptor
        Public WinId         As UInt32
        Public OwnerPid      As ProcessId
        Public X             As Int32
        Public Y             As Int32
        Public Width         As Int32
        Public Height        As Int32
        Public SurfaceWidth  As Int32
        Public SurfaceHeight As Int32
        Public State         As Int32
        Public Focused       As Boolean
        Public ShmId         As Handle
        Public ClientVaddr   As VirtualAddress
        Public Title(32)     As Byte
    End Structure

    <Packed>
    Public Structure WindowTable
        Public Revision    As UInt32
        Public Count       As Int32
        Public Windows(16) As WindowDescriptor
    End Structure

    <Packed>
    Public Structure AxonPacket
        Public Sequence      As UInt64
        Public PacketType    As UInt32
        Public PayloadLength As UInt32
        Public SourceNode    As NodeId
        Public TargetNode    As NodeId
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
        Public Width     As Int32
        Public Height    As Int32
        Public Pitch     As UInt32
        Public Bpp       As UInt32
        Public Pixels    As Pointer To UInt32
    End Structure

    <Packed>
    Public Structure Rect
        Public X      As Int32
        Public Y      As Int32
        Public Width  As Int32
        Public Height As Int32
    End Structure

    <Packed>
    Public Structure DisplayInfo
        Public Width    As Int32
        Public Height   As Int32
        Public Pitch    As UInt32
        Public Bpp      As UInt32
        Public PhysAddr As PhysicalAddress
    End Structure

    ' =========================================================================
    ' 3. Library Declarations (Declare with Alias)
    ' =========================================================================

    ' Process & System Management
    Public Declare Sub ProcessYield Lib "libpros" Alias "Pros_Sys_Process_Yield" ()
    Public Declare Sub ProcessSleep Lib "libpros" Alias "Pros_Sys_Process_Sleep" (ByVal ms As UInt64)
    Public Declare Function GetPid Lib "libpros" Alias "Pros_Sys_Process_GetPid" () As ProcessId
    Public Declare Sub TerminateProcess Lib "libpros" Alias "Pros_Sys_Process_ExitProcess" (ByVal exitCode As UInt64)
    Public Declare Function GetCoreCount Lib "libpros" Alias "Pros_Sys_Process_GetCoreCount" () As UInt64
    Public Declare Function GetUptime Lib "libpros" Alias "Pros_Sys_Process_GetUptime" () As UInt64
    Public Declare Function AllocatePages Lib "libpros" Alias "Pros_Sys_Process_AllocatePages" (ByVal pageCount As UInt64, ByVal targetVaddr As VirtualAddress) As Pointer To UInt32

    ' Console I/O
    Public Declare Sub ConsoleWrite Lib "libpros" Alias "Pros_IO_Console_Write" (ByVal str As String)
    Public Declare Sub ConsoleWriteLine Lib "libpros" Alias "Pros_IO_Console_WriteLine" (ByVal str As String)
    Public Declare Sub ConsolePrintWithUInt Lib "libpros" Alias "Pros_IO_Console_PrintWithUInt" (ByVal prefix As String, ByVal val As UInt64, ByVal suffix As String)

    ' Neural Nodes & Synapses
    Public Declare Function NodeRegister Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Register" (ByVal kind As UInt32, ByVal name As String, ByVal caps As UInt32) As NodeId
    Public Declare Function NodeLookup Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Lookup" (ByVal name As String) As NodeId
    Public Declare Function SynapseConnect Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Connect" (ByVal srcNodeId As NodeId, ByVal targetNodeId As NodeId, ByVal caps As UInt32) As SynapseId
    Public Declare Function SynapsePush Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Push" (ByVal synId As SynapseId, ByRef pkt As AxonPacket) As Boolean
    Public Declare Function SynapsePop Lib "libpros" Alias "Pros_Nodes_NodeRegistry_Pop" (ByVal synId As SynapseId, ByRef pkt As AxonPacket) As Boolean
    Public Declare Function SynapsePopWait Lib "libpros" Alias "Pros_Nodes_NodeRegistry_PopWait" (ByVal synId As SynapseId, ByRef pkt As AxonPacket) As Boolean

    ' Zero-Copy Shared Memory
    Public Declare Function ShmemCreate Lib "libpros" Alias "Pros_Memory_Shmem_Create" (ByVal sizeBytes As UInt64, ByVal targetVaddr As VirtualAddress) As Handle
    Public Declare Function ShmemAttach Lib "libpros" Alias "Pros_Memory_Shmem_Attach" (ByVal shmid As Handle, ByVal targetVaddr As VirtualAddress) As VirtualAddress
    Public Declare Function ShmemDetach Lib "libpros" Alias "Pros_Memory_Shmem_Detach" (ByVal shmid As Handle) As Boolean

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
    Public Declare Function MapFramebuffer Lib "libpros" Alias "Pros_Driver_Display_Map" (ByVal targetVaddr As VirtualAddress) As Pointer To UInt32

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
    Public Declare Function VfsStat Lib "libpros" Alias "Pros_Storage_VfsClient_Stat" (ByVal path As String, ByRef outStat As FileStat) As Boolean

    ' Window Management APIs
    Public Declare Function WmRequestFocus Lib "libpros" Alias "Pros_Gui_WindowManagerClient_RequestFocus" (ByVal winId As UInt32) As Boolean
    Public Declare Function WmCreateWindow Lib "libpros" Alias "Pros_Gui_WindowManagerClient_CreateWindow" (ByVal w As Int32, ByVal h As Int32, ByVal shmId As Handle, ByVal title As String) As UInt32
    Public Declare Function WmDestroyWindow Lib "libpros" Alias "Pros_Gui_WindowManagerClient_DestroyWindow" (ByVal winId As UInt32) As Boolean
    Public Declare Function WmSignalDirty Lib "libpros" Alias "Pros_Gui_WindowManagerClient_SignalDirty" (ByVal winId As UInt32, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32) As Boolean

    ' Device Management APIs
    <Packed>
    Public Structure DeviceInfo
        Public Id        As UInt32
        Public Kind      As UInt32
        Public Status    As UInt32
        Public Reserved  As UInt32
        Public BaseAddr  As UInt64
    End Structure
    Public Declare Function DevQueryDevice Lib "libpros" Alias "Pros_Devices_DeviceClient_QueryDevice" (ByVal name As String, ByRef outInfo As DeviceInfo) As Boolean

    ' Service Supervision APIs
    Public Declare Function PlexusIsServiceActive Lib "libpros" Alias "Pros_Services_ServiceSupervisorClient_IsServiceActive" (ByVal serviceName As String) As Boolean

    ' =========================================================================
    ' 4. Low-Level Basic Standard Library APIs (libpros)
    ' =========================================================================

    ' String Manipulation & Formatting
    Public Declare Function StrLen Lib "libpros" Alias "Pros_String_StringUtil_StrLen" (ByVal s As String) As UInt64
    Public Declare Function StrEquals Lib "libpros" Alias "Pros_String_StringUtil_StrEquals" (ByVal s1 As String, ByVal s2 As String) As Boolean
    Public Declare Sub AppendStr Lib "libpros" Alias "Pros_String_StringUtil_AppendStr" (ByVal s As String, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
    Public Declare Sub AppendUInt Lib "libpros" Alias "Pros_String_StringUtil_AppendUInt" (ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
    Public Declare Sub AppendHex Lib "libpros" Alias "Pros_String_StringUtil_AppendHex" (ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
    Public Declare Function Trim Lib "libpros" Alias "Pros_String_StringUtil_Trim" (ByVal src As String, ByVal outBuf As Pointer To Byte) As UInt64
    Public Declare Function StrTrim Lib "libpros" Alias "Pros_String_StringUtil_Trim" (ByVal src As String, ByVal outBuf As Pointer To Byte) As UInt64

    ' Numeric & String Formatting
    Public Declare Function SprintF Lib "libpros" Alias "Format_SprintF" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
    Public Declare Function ToHex Lib "libpros" Alias "Format_ToHex" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
    Public Declare Function ToUInt Lib "libpros" Alias "Format_ToUInt" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte) As UInt32
    Public Declare Function ToInt Lib "libpros" Alias "Format_ToInt" (ByVal value As Int64, ByVal outBuf As Pointer To Byte) As UInt32
    Public Declare Function ToBinary Lib "libpros" Alias "Format_ToBinary" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean, ByVal minWidth As UInt32) As UInt32

    ' Memory Operations
    Public Declare Sub Copy Lib "libpros" Alias "Pros_Memory_MemUtil_Copy" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
    Public Declare Sub Move Lib "libpros" Alias "Pros_Memory_MemUtil_Move" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)
    Public Declare Sub SetBytes Lib "libpros" Alias "Pros_Memory_MemUtil_SetBytes" (ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
    Public Declare Sub MemSet Lib "libpros" Alias "Pros_Memory_MemUtil_SetBytes" (ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
    Public Declare Function Compare Lib "libpros" Alias "Pros_Memory_MemUtil_Compare" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32

    ' Math Utilities & Geometry
    Public Declare Function Min Lib "libpros" Alias "Pros_Math_MathUtil_Min" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Max Lib "libpros" Alias "Pros_Math_MathUtil_Max" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Clamp Lib "libpros" Alias "Pros_Math_MathUtil_Clamp" (ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64
    Public Declare Function Abs Lib "libpros" Alias "Pros_Math_MathUtil_Abs" (ByVal val As Int64) As Int64
    Public Declare Function RectContains Lib "libpros" Alias "Pros_Math_MathUtil_RectContains" (ByRef r As Rect, ByVal px As Int32, ByVal py As Int32) As Boolean
    Public Declare Sub UnionRect Lib "libpros" Alias "Pros_Math_MathUtil_UnionRect" (ByRef outRect As Rect, ByRef r1 As Rect, ByRef r2 As Rect)

    ' Font Rendering & Text Drawing
    Public Declare Sub DrawGlyph5x7 Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawGlyph5x7" (ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
    Public Declare Sub DrawText5x7 Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawText5x7" (ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal text As String, ByVal color As UInt32)
    Public Declare Sub DrawGlyph8x16 Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawGlyph8x16" (ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
    Public Declare Sub DrawText8x16 Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawText8x16" (ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal text As String, ByVal color As UInt32)
    Public Declare Sub DrawGlyph Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawGlyph" (ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32, ByVal useLargeFont As Boolean = False)
    Public Declare Sub DrawText Lib "libpros" Alias "Pros_Drawing_FontRenderer_DrawText" (ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal text As String, ByVal color As UInt32, ByVal useLargeFont As Boolean = False)

End Module
