# PROS Standard Library (libpros): API Reference & Architecture

## 1. Overview
The PROS Standard Library (`libpros.a`, headers in `include/pros.bas`) provides native Low-Level Basic (LLB) modules and standard C declarations for userland applications, drivers, and background daemons.

The library strictly follows LLB module and library binding rules:
- `Import` for modules (`.bas`).
- `Use` for classes (`.cls`).
- `Declare` for external precompiled libraries (`.a`, `.bdl`).
- `Alias` for long or namespaced symbol exports.

---

## 2. Subsystem API Reference

### 2.1 Process Management (`Pros.Sys.Process`)
Header export: `ProcessYield`, `ProcessSleep`, `GetPid`, `TerminateProcess`, `GetCoreCount`, `GetUptime`, `AllocatePages`.

- `Sub ProcessYield()`: Relinquishes CPU quantum to next runnable task.
- `Sub ProcessSleep(ByVal ms As UInt64)`: Puts task to sleep on kernel timer queue. Halts CPU when all tasks are sleeping.
- `Function GetPid() As UInt64`: Returns calling task's PID.
- `Sub TerminateProcess(ByVal exitCode As UInt64)`: Exits calling process cleanly.
- `Function GetCoreCount() As UInt64`: Returns total online SMP CPU cores.
- `Function GetUptime() As UInt64`: Returns system uptime in milliseconds.
- `Function AllocatePages(ByVal pageCount As UInt64, ByVal targetVaddr As UInt64) As Pointer To UInt32`: Allocates anonymous physical RAM pages and maps them contiguously into caller's address space.

### 2.2 Console I/O (`Pros.IO.Console`)
Header export: `ConsoleWrite`, `ConsoleWriteLine`, `ConsolePrintWithUInt`.

- `Sub ConsoleWrite(ByVal strPtr As Pointer To Byte)`: Emits null-terminated string to COM1 UART and debug console.
- `Sub ConsoleWriteLine(ByVal strPtr As Pointer To Byte)`: Emits string with trailing `\r\n`.
- `Sub ConsolePrintWithUInt(ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)`: Atomically formats and emits string with embedded 64-bit integer.

### 2.3 Neural Node Registry & Synapses (`Pros.Nodes.NodeRegistry`)
Header export: `NodeRegister`, `NodeLookup`, `SynapseConnect`, `SynapsePush`, `SynapsePop`.

- `Function NodeRegister(ByVal kind As UInt32, ByVal namePtr As Pointer To Byte, ByVal caps As UInt32) As UInt64`: Registers calling process node in control topology.
- `Function NodeLookup(ByVal namePtr As Pointer To Byte) As UInt64`: Resolves public service node name (e.g. `"srv.vfs"`, `"srv.wm"`, `"srv.dev_mgr"`).
- `Function SynapseConnect(ByVal srcNodeId As UInt64, ByVal targetNodeId As UInt64, ByVal caps As UInt32) As UInt64`: Creates or reuses a directed channel between two nodes.
- `Function SynapsePush(ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean`: Pushes packet to channel ring buffer.
- `Function SynapsePop(ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean`: Retrieves incoming packet from a channel or from the node's inbound queue.

### 2.4 Zero-Copy Shared Memory (`Pros.Memory.Shmem`)
Header export: `ShmemCreate`, `ShmemAttach`, `ShmemDetach`.

- `Function ShmemCreate(ByVal sizeBytes As UInt64, ByVal targetVaddr As UInt64) As UInt64`: Allocates physical pages and maps them to virtual address space.
- `Function ShmemAttach(ByVal shmid As UInt64, ByVal targetVaddr As UInt64) As UInt64`: Maps an existing shared memory pool.
- `Function ShmemDetach(ByVal shmid As UInt64) As Boolean`: Unmaps and decrements reference count.

### 2.5 2D Surface Graphics & Blitting (`Pros.Gui.Graphics`)
Header export: `FillRect`, `Blit`.

- `Sub FillRect(ByRef surf As Surface, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32, ByVal color As UInt32)`: Fills clipped rectangle in ARGB8888 color.
- `Sub Blit(ByRef dst As Surface, ByVal dx As Int32, ByVal dy As Int32, ByRef src As Surface, ByVal sx As Int32, ByVal sy As Int32, ByVal w As Int32, ByVal h As Int32)`: Fast zero-copy pixel block transfer.

### 2.6 Virtual File System (`Pros.Storage.VfsClient`)
Header export: `VfsStat`.

- `Function VfsStat(ByVal pathPtr As Pointer To Byte, ByRef outStat As FileStat) As Boolean`: Queries file size, node type, and permissions from `srv.vfs` using Synaptic IPC. Supports both Windows-style paths (`C:\System\Bin\genesis.bax`) and Android/Unix paths (`/system/bin/genesis.bax`).

### 2.7 Window Manager (`Pros.Gui.WindowManagerClient`)
Header export: `WmRequestFocus`.

- `Function WmRequestFocus(ByVal winId As UInt32) As Boolean`: Sends `WM_CMD_SET_FOCUS` to `srv.wm` to update desktop focus state and active window borders.

### 2.8 Device Manager (`Pros.Devices.DeviceClient`)
Header export: `DevQueryDevice`.

- `Function DevQueryDevice(ByVal namePtr As Pointer To Byte, ByRef outInfo As DeviceInfo) As Boolean`: Queries hardware topology, MMIO apertures, and IRQ line numbers from `srv.dev_mgr`.

### 2.9 Service Supervisor (`Pros.Services.ServiceSupervisorClient`)
Header export: `PlexusIsServiceActive`.

### 2.10 Pure Low-Level Basic String Utilities (`Pros.String`)
Header export: `StrLen`, `StrEquals`, `AppendStr`, `AppendUInt`, `AppendHex`, `Trim`, `StrTrim`.

- `Function StrLen(ByVal strPtr As Pointer To Byte) As UInt64`: Calculates the byte length of a null-terminated ASCII string (excluding null terminator). Returns 0 on null pointer.
- `Function StrEquals(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Boolean`: Performs exact byte-for-byte ASCII string equality comparison. Returns `True` if both pointers are identical or null.
- `Sub AppendStr(ByVal s As Pointer To Byte, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)`: Appends an ASCII string to `buf` starting at `outIdx` and updates `outIdx`. Does not append a terminating null.
- `Sub AppendUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)`: Converts an unsigned 64-bit integer to base-10 ASCII digits, appends to `buf` at `outIdx`, and updates `outIdx`.
- `Sub AppendHex(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)`: Converts an unsigned 64-bit integer to uppercase hexadecimal ASCII digits, appends to `buf` at `outIdx`, and updates `outIdx`.
- `Function Trim(ByVal src As Pointer To Byte, ByVal outBuf As Pointer To Byte) As UInt64`: Strips leading and trailing ASCII whitespace (ASCII <= 32), writes the null-terminated result into `outBuf`, and returns the trimmed byte length. Also accessible via alias `StrTrim`.

### 2.11 Pure Low-Level Basic Memory Operations (`Pros.Memory`)
Header export: `Copy`, `Move`, `SetBytes`, `MemSet`, `Compare`.

- `Sub Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)`: Strongly-typed wrapper around `memcpy` with null pointer and zero count guard checks.
- `Sub Move(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)`: Strongly-typed wrapper around `memmove` with overlap safety (`dest > src` backward copy).
- `Sub SetBytes(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)`: Strongly-typed wrapper around `memset` to fill a buffer with a single byte value. Also accessible via alias `MemSet`.
- `Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32`: Strongly-typed wrapper around `memcmp` returning signed difference (`< 0`, `0`, `> 0`).

### 2.12 Pure Low-Level Basic Math & Geometry (`Pros.Math`)
Header export: `Min`, `Max`, `Clamp`, `Abs`, `RectContains`, `UnionRect`, `Structure Rect`.

- `Function Min(ByVal a As Int64, ByVal b As Int64) As Int64`: Returns minimum of two signed 64-bit integers.
- `Function Max(ByVal a As Int64, ByVal b As Int64) As Int64`: Returns maximum of two signed 64-bit integers.
- `Function Clamp(ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64`: Clamps a signed 64-bit integer within inclusive range `[lowVal, highVal]`.
- `Function Abs(ByVal val As Int64) As Int64`: Returns absolute value of a signed 64-bit integer.
- `Function RectContains(ByRef r As Rect, ByVal px As Int32, ByVal py As Int32) As Boolean`: Tests if point `(px, py)` is inside `Rect` (inclusive top-left `[X, Y]`, exclusive bottom-right `[X+W, Y+H)`).
- `Sub UnionRect(ByRef outRect As Rect, ByRef r1 As Rect, ByRef r2 As Rect)`: Computes minimal union bounding box of two rectangles with in-place aliasing protection.

### 2.13 Centralized Font Rendering & Drawing (`Pros.Drawing` / `Pros.Font`)
Header export: `DrawGlyph5x7`, `DrawText5x7`, `DrawGlyph8x16`, `DrawText8x16`, `DrawGlyph`, `DrawText`.

- `Sub DrawGlyph5x7(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)`: Renders single 5x7 bitmap glyph with 4-border clipping.
- `Sub DrawText5x7(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)`: Renders null-terminated ASCII string using 5x7 font (step = 6 pixels).
- `Sub DrawGlyph8x16(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)`: Renders single 8x16 console glyph from `font_8x16_data` with clipping.
- `Sub DrawText8x16(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)`: Renders null-terminated ASCII string using 8x16 font (step = 8 pixels).
- `Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32, ByVal useLargeFont As Boolean)`: Universal glyph renderer selecting 5x7 (`False`) or 8x16 (`True`).
- `Sub DrawText(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32, ByVal useLargeFont As Boolean)`: Universal text renderer selecting 5x7 (`False`) or 8x16 (`True`).

---

## 3. C Language Interoperability
All exported symbols in `libpros.a` provide C-compatible ABI bindings without mangling, allowing C/C++ userland programs to link directly against `libpros.a` using `<pros.h>`.

