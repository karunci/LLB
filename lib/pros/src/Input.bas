' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Input.bas
' Summary: High-level input event definitions and queue reader.

Namespace Pros.Inputs

    Public Const EVENT_KEY_DOWN      As UInt32 = 1
    Public Const EVENT_KEY_UP        As UInt32 = 2
    Public Const EVENT_MOUSE_MOVE    As UInt32 = 3
    Public Const EVENT_MOUSE_BUTTON  As UInt32 = 4

    Public Const INPUT_QUEUE_MAGIC   As UInt64 = &H494E5055545F5155

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

End Namespace
