# PROS System Architecture: Application Binary Interface (ABI) & System Calls Specification

## 1. System Architecture Overview
PROS (Personal Research Operating System) is a 64-bit microkernel based on Low-Level Basic (LLB) that enforces strict hardware isolation:
- **Ring 0 (CPL=0):** Freestanding microkernel managing physical/virtual memory, CPU SMP scheduling, interrupt gates, and the dual-plane neural node registry.
- **Ring 3 (CPL=3):** Standalone userland processes, device drivers, and system services running under hardware page protection with no raw I/O port (`in`/`out`) or page-table privileges.

Inter-Process Communication (IPC) is strictly decoupled through two complementary planes:
1. **Control Plane (Synapses):** Message-passing control channels for RPC commands, capability queries, and event signaling.
2. **Data Plane (Axons):** Zero-copy shared memory rings and linear framebuffer apertures for bulk data transfer.

---

## 2. Low-Level x86_64 Calling Convention & Register ABI

System calls in PROS use the AMD64 `syscall` / `sysretq` hardware instructions:
- Fast transition via MSR `0xC0000082` (`IA32_LSTAR`).
- Red zone is disabled (`NoRedZone` invariant).
- Stack alignment: 16-byte aligned before function invocation.

### Syscall Register Mapping
| Register | Direction | Purpose | Description |
|:---|:---|:---|:---|
| `%rax` | Input | Syscall ID | Numeric identifier of the requested kernel service |
| `%rdi` | Input | Argument 1 | Primary parameter (e.g. Channel ID, Node ID, or Buffer Pointer) |
| `%rsi` | Input | Argument 2 | Secondary parameter (e.g. Size, Buffer Pointer, or Capability mask) |
| `%rdx` | Input | Argument 3 | Tertiary parameter (e.g. Flags, Blocking flag, or Permissions) |
| `%r10` | Input | Argument 4 | Quaternary parameter (Mapped from `%rcx` in userspace stub) |
| `%r8`  | Input | Argument 5 | Quinary parameter |
| `%r9`  | Input | Argument 6 | Senary parameter |
| `%rax` | Output | Return Value | Status code or handle (`1` = Success, `0` = Failure/Empty, or ID) |
| `%rcx` | Clobbered | Hardware RIP | Automatically saved by `syscall` CPU instruction |
| `%r11` | Clobbered | Hardware RFLAGS| Automatically saved by `syscall` CPU instruction |

---

## 3. Core Microkernel System Call Table

### Process & Threading Management
- `SYS_CONSOLE_WRITE (1)`: Emit raw ASCII buffer to kernel COM1 serial log and linear console.
  - `%rdi`: Virtual memory address of ASCII buffer.
  - `%rsi`: Number of bytes to emit.
  - Returns: Number of bytes written.
- `SYS_PROCESS_YIELD (2)`: Voluntarily yield the current CPU quantum to the next runnable thread.
- `SYS_PROCESS_SLEEP (3)`: Block the calling thread on the timer queue for a specified interval.
  - `%rdi`: Sleep duration in milliseconds.
- `SYS_PROCESS_GETPID (6)`: Query active process ID.
  - Returns: Current PID (`UInt64`).
- `SYS_PROCESS_EXIT (16)`: Terminate the calling process and notify parent / supervisor.
  - `%rdi`: Process exit status code (`UInt64`).
- `SYS_TIME_UPTIME (28)`: Read system uptime counter.
  - Returns: Milliseconds elapsed since microkernel boot (`UInt64`).
- `SYS_SMP_CORE_COUNT (34)`: Query online hardware CPU core count detected by ACPI MADT.
  - Returns: Number of online cores (`UInt64`).

### Dual-Plane Neural Node Registry (Control & Data Plane)
- `SYS_NODE_REGISTER (50)`: Register a new communication node in the kernel topology.
  - `%rdi`: Functional category (`1` = Client, `2` = Device, `3` = Storage, `4` = Router).
  - `%rsi`: Pointer to null-terminated node name string (max 31 characters).
  - `%rdx`: Capability mask (`1` = Read, `2` = Write, `4` = Notify).
  - Returns: Assigned Node ID (`1000..4999`) or `0` on error.
- `SYS_SYNAPSE_CONNECT (51)`: Establish a directed communication channel between two nodes.
  - `%rdi`: Source Node ID.
  - `%rsi`: Target Node ID.
  - `%rdx`: Requested channel capability flags.
  - Returns: Assigned Channel ID (`>= 5000`) or existing channel ID.
- `SYS_SYNAPSE_PUSH (52)`: Push an `AxonPacket` into a channel's fast-path ring buffer.
  - `%rdi`: Channel ID (`>= 5000`).
  - `%rsi`: Pointer to userland `AxonPacket` structure (288 bytes).
  - Returns: `1` on success, `0` if queue is full or unpermitted.
- `SYS_SYNAPSE_POP (53)`: Pop an `AxonPacket` from an individual channel or a node's inbound queue.
  - `%rdi`: Channel ID (`>= 5000`) or Node ID (`< 5000` for multiplexed node-level pop).
  - `%rsi`: Pointer to userland `AxonPacket` structure to populate.
  - `%rdx`: Blocking mode (`1` = Block until packet arrives, `0` = Non-blocking poll).
  - Returns: `1` if packet was retrieved, `0` if empty.
- `SYS_NODE_LOOKUP (55)`: Discover the Node ID associated with a public service name.
  - `%rdi`: Pointer to null-terminated node name string (e.g. `"srv.vfs"`).
  - Returns: Node ID or `0` if not registered.

### Zero-Copy Shared Memory & Dynamic Memory Allocation
- `SYS_MEM_ALLOC_PAGES (26)`: Allocate anonymous physical RAM frames and map contiguously into calling task's address space.
  - `%rdi`: Number of 4 KB pages to allocate (up to 8,192 pages = 32 MB).
  - `%rsi`: Target virtual memory address (must be 4 KB page-aligned, e.g. `0x88000000`).
  - Returns: Mapped base virtual address or `0` on allocation/validation failure.
- `SYS_SHMEM_CREATE (60)`: Allocate zero-copy physical pages and map to calling task.
  - `%rdi`: Size in bytes (rounded up to 4 KB page alignment).
  - `%rsi`: Preferred virtual target address.
  - Returns: SHMID handle (`> 0`) or `0` on failure.
- `SYS_SHMEM_ATTACH (61)`: Attach an existing shared memory pool to calling task's address space.
  - `%rdi`: SHMID handle.
  - `%rsi`: Target virtual address.
  - Returns: Attached virtual address or `0`.
- `SYS_SHMEM_DETACH (62)`: Unmap shared memory pool and release reference count.
  - `%rdi`: SHMID handle.
  - Returns: `0` on success.

### Direct Hardware Driver Apertures
- `SYS_FB_GET_INFO (70)`: Query GOP Linear Framebuffer geometry.
  - `%rdi`: Pointer to `DisplayInfo` structure (Width, Height, Pitch, Bpp, PhysAddr).
  - Returns: `1` on success, `0` on error.
- `SYS_FB_MAP (71)`: Map physical linear framebuffer aperture into Ring 3 address space with uncacheable MMIO attributes (`0x1F`: Present, Writable, User, Write-Through, Cache-Disable) matching PRK reference semantics to prevent PCIe bus write-combining conflicts.
  - `%rdi`: Target virtual address (e.g. `0x78000000`).
  - Returns: Virtual address pointer to pixel buffer.
- `SYS_GET_MOUSE (19)`: Poll live PS/2 hardware mouse coordinates and button flags.
  - `%rdi`: Pointer to `MouseState` structure (X, Y, Buttons).
  - Returns: `1` on success.

---

## 4. Synapse AxonPacket Binary Layout

```
Offset  Size  Field          Description
0x00    8     Sequence       Monotonically increasing sequence number
0x08    8     Timestamp      Kernel uptime timestamp (milliseconds)
0x10    4     PacketType     Subsystem command / response code
0x14    4     Flags          Transfer flags (Urgent, End-of-Stream, Shm)
0x18    8     SourceNode     Originating Node ID
0x20    8     TargetNode     Destination Node ID
0x28    4     PayloadLength  Active bytes in payload buffer (0..256)
0x2C    4     Reserved       Reserved alignment padding
0x30    256   Payload        Data payload buffer
Total Size: 288 bytes (Cache-line aligned)
```

---

## 5. Semantic Type Aliases & Strongly-Typed Enums (`include/pros.bas`)

PROS public ABI uses semantic type aliases and strongly-typed enums to enforce type safety across microkernel syscall boundaries and Ring 3 service messaging.

### Semantic Type Aliases
| Type Alias | Primitive Type | Semantic Scope |
|:---|:---|:---|
| `ProcessId` | `UInt64` | Process identifiers (PID) |
| `ThreadId` | `UInt64` | Thread identifiers (TID) |
| `Handle` | `UInt64` | Resource handles (e.g. ShmId) |
| `NodeId` | `UInt64` | Neural node topology addresses |
| `SynapseId` | `UInt64` | Inter-node synapse channel IDs |
| `ShmId` | `UInt64` | Shared memory block identifiers |
| `VirtualAddress` | `UInt64` | Ring 3 / Ring 0 virtual memory addresses |
| `PhysicalAddress` | `UInt64` | Physical memory frame addresses |

### Strongly-Typed Enums
- `NodeKind`: Node hierarchy classification (`Client = 1`, `System = 1`, `Device = 2`, `Storage = 3`, `Router = 4`).
- `SynapseCapability`: Capability bitmasks (`Read = 1`, `Write = 2`, `Notify = 4`, `All = 7`).
- `InputEventType`: User input events (`KeyDown = 1`, `KeyUp = 2`, `MouseMove = 3`, `MouseButton = 4`).
- `WmCommand`: Window manager protocol requests (`SetFocus = 22`, `MoveWindow = 23`, `ResizeWindow = 24`, `MinimizeWindow = 25`, `MaximizeWindow = 26`, `RestoreWindow = 27`, `RegisterTable = 30`, `CreateWindow = 31`, `DestroyWindow = 32`, `MouseEvent = 33`, `SetCursor = 34`, `WindowDirty = 35`).
- `WmResponse`: Window manager protocol responses (`Ok = 200`, `Error = 201`).
- `WindowState`: Window visibility status (`Normal = 0`, `Minimized = 1`, `Maximized = 2`).
- `VfsKind`: Virtual file system node kinds (`File = 1`, `Directory = 2`, `Device = 3`).
- `VfsCommand`: VFS protocol commands (`Open = 1`, `Read = 2`, `Write = 3`, `Close = 4`, `Stat = 11`, `List = 12`).
- `VfsResponse`: VFS status codes (`Success = 0`, `Error = 1`, `NotFound = 2`, `PermissionDenied = 3`).
- `DevCommand`: Device manager protocol commands (`Register = 1`, `Unregister = 2`, `Query = 31`).
- `DevResponse`: Device manager status codes (`Success = 0`, `Error = 1`, `DeviceNotFound = 2`).

### String Parameter Modernization
All public library functions accept `ByVal ... As String` directly, supporting both variable strings and literal string constants seamlessly with freestanding null-check safety.

