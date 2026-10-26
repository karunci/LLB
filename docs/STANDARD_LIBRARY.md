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
Header export: `ProcessYield`, `ProcessSleep`, `GetPid`, `TerminateProcess`, `GetCoreCount`, `GetUptime`.

- `Sub ProcessYield()`: Relinquishes CPU quantum to next runnable task.
- `Sub ProcessSleep(ByVal ms As UInt64)`: Puts task to sleep on kernel timer queue. Halts CPU when all tasks are sleeping.
- `Function GetPid() As UInt64`: Returns calling task's PID.
- `Sub TerminateProcess(ByVal exitCode As UInt64)`: Exits calling process cleanly.
- `Function GetCoreCount() As UInt64`: Returns total online SMP CPU cores.
- `Function GetUptime() As UInt64`: Returns system uptime in milliseconds.

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

- `Function PlexusIsServiceActive(ByVal serviceName As Pointer To Byte) As Boolean`: Queries `srv.plexus_mgr` to determine if a background daemon is healthy and running.

---

## 3. C Language Interoperability
All exported symbols in `libpros.a` provide C-compatible ABI bindings without mangling, allowing C/C++ userland programs to link directly against `libpros.a` using `<pros.h>`.
