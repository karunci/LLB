# PROS (Personal Research Operating System) Architecture Specification
## Microkernel Core, PID 1 Genesis Init, Userspace Driver Pipeline, and Display Compositor

```
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                              PROS SYSTEM OVERVIEW                                      │
 │                                                                                        │
 │   Kernel Identity : PRK-LLB (Personal Research Kernel in Low-Level BASIC)               │
 │   System Identity : PROS (Personal Research Operating System)                         │
 │   Executable Type : .bax (Basic Application eXecutable) / NEO/PE-BAX                   │
 │   IPC Primitives  : Dual-Plane Neural Synapse Channels & Shared Memory Gradients       │
 │   Design Paradigm : Pure Microkernel with Userspace Device Drivers & Compositor        │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. System Philosophy & Conceptual Taxonomy

In alignment with the **Dual-Plane Neural Node Architecture** (*"Everything is a Node connected via Synaptic Channels"*), all operating system components are structured as autonomous, capability-authenticated Nodes exchanging messages across memory-speed channels:

| Traditional Concept | Windows NT Equivalent | Unix / Linux Equivalent | PROS / PRK-LLB Equivalent | Architecture & Lifecycle Role |
|:---|:---|:---|:---|:---|
| **PID 1 (Init)** | `smss.exe` / `wininit` | `/sbin/init`, `systemd` | **`genesis.bax`** (or **`cortex.bax`**) | Root userspace coordinator spawned directly by microkernel. |
| **Process** | Process (`.exe`) | Process (ELF binary) | **Node Process** (`.bax`) | Hardware-isolated address space (User PML4) running one or more Nodes. |
| **System Service** | Windows Service | Daemon (`systemd` unit) | **Plexus Service** (`*.bax`) | Long-running background subsystem node (e.g., storage, networking). |
| **Service Supervisor** | SCM (`services.exe`) | `systemd`, `launchd` | **`plexus_mgr.bax`** | Oversees service lifecycles, health heartbeat synapses, and restarts. |
| **Device Arbiter** | Plug & Play (`pnp_mgr`)| `udev`, `devd` | **`dev_mgr.bax`** | Probes hardware buses (PCI/ACPI) and matches userland driver BAXs. |
| **Display Server** | DWM (`dwm.exe`) | Wayland Compositor | **`compositor.bax`** | Owns LFB video aperture; composites window surfaces and cursor plane. |
| **Window Manager** | Windows Shell / Explorer | Mutter / KWin / Sway | **`wm.bax`** | Window frames, titlebars, layouts, hit-testing, and focus dispatch. |
| **Raw Input Driver** | Kernel Input Subsystem | `evdev` / Kernel HID | **`input_srv.bax`** | Reads raw scancodes/mouse bytes from kernel and emits high-level events. |

---

## 2. Complete End-to-End System Topology

```
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                                   USERSPACE (Ring 3)                                   │
 │                                                                                        │
 │  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
 │  │                         GENESIS ORCHESTRATOR (PID 1)                             │  │
 │  │      - Inspects /system/manifest.json via Memory-Mapped Resource at 0x50000000    │  │
 │  │      - Spawns Core Service Managers & Establishes Initial Control Plane          │  │
 │  └───────────────┬──────────────────────────────────────────────────┬───────────────┘  │
 │                  │                                                  │                  │
 │                  ▼                                                  ▼                  │
 │  ┌───────────────────────────────┐                  ┌───────────────────────────────┐  │
 │  │          dev_mgr.bax          │                  │        plexus_mgr.bax         │  │
 │  │       (Device Arbiter)        │                  │       (Service Manager)       │  │
 │  │ - Scans ACPI & PCI Buses      │                  │ - Background service monitor  │  │
 │  │ - Matches Driver Manifests    │                  │ - Heartbeat telemetry probes  │  │
 │  │ - Hot-reloads crashed drivers │                  │ - Clean service restarting    │  │
 │  └───────────────┬───────────────┘                  └───────────────┬───────────────┘  │
 │                  │                                                  │                  │
 │                  ▼                                                  ▼                  │
 │  ┌───────────────────────────────┐                  ┌───────────────────────────────┐  │
 │  │        input_srv.bax          │                  │         vfs_srv.bax           │  │
 │  │    (Unified Input Driver)     │                  │     (Storage & VFS Node)      │  │
 │  │ - Reads raw scancodes & mouse │                  │ - File systems & disk drivers │  │
 │  │ - Emits high-level InputEvents│                  │ - Mount points & permissions  │  │
 │  └───────────────┬───────────────┘                  └───────────────┬───────────────┘  │
 │                  │                                                  │                  │
 │                  │ Axon Input Events (Key/Mouse)                    │ File I/O Synapse │
 │                  ▼                                                  ▼                  │
 │  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
 │  │                              wm.bax (Window Manager)                             │  │
 │  │  - Manages Window Hierarchies, Focus State, Window Decorations & Titlebars       │  │
 │  │  - Routes Input Events to Active Focused Application Node                        │  │
 │  └───────────────┬──────────────────────────────────────────────────┬───────────────┘  │
 │                  │ Window Surface Grants                            │ Focus / Events   │
 │                  ▼                                                  ▼                  │
 │  ┌───────────────────────────────┐                  ┌───────────────────────────────┐  │
 │  │        compositor.bax         │                  │      Client Applications      │  │
 │  │   (Display Engine & Cursor)   │ <══════════════> │   (user_app.bax, calc.bax)    │  │
 │  │ - Maps Physical Framebuffer   │  Shared Memory   │ - Allocates client backbuffer │  │
 │  │ - Composites Window Surfaces  │  (Zero-Copy)     │ - Draws UI widgets            │  │
 │  │ - Renders Hardware Cursor     │                  │ - Exchanges Synapse packets   │  │
 │  └───────────────┬───────────────┘                  └───────────────────────────────┘  │
 └──────────────────┼─────────────────────────────────────────────────────────────────────┘
════════════════════╪══════════════════════════════════════════════════════════════════════
                    │ System Calls: SYS_SHMEM_* / SYS_SYNAPSE_* / SYS_NODE_*               
                    ▼                                                                      
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                                  PRK-LLB MICROKERNEL (Ring 0)                          │
 │                                                                                        │
 │  ┌──────────────────────────────────────┐    ┌──────────────────────────────────────┐  │
 │  │      Hardware Trap & MMIO Engine     │    │       Memory Management Subsystem    │  │
 │  │ - PS/2 Controller IRQ1 (Scancodes)   │    │ - PMM (Physical Free-List Allocator) │  │
 │  │ - PS/2 Mouse IRQ12 (3-Byte Packets)  │    │ - Binary Buddy Allocator (Order 0-10)│  │
 │  │ - Publishes directly to raw Node #2  │    │ - 4-Level VMM (Isolated User PML4s)  │  │
 │  │   ('hw.input.raw') via Ring Buffers  │    │ - Shared Memory Gradients (SHMEM)    │  │
 │  └──────────────────────────────────────┘    └──────────────────────────────────────┘  │
 │                                                                                        │
 │  ┌──────────────────────────────────────┐    ┌──────────────────────────────────────┐  │
 │  │      SMP Runqueue Scheduler Engine   │    │     Dual-Plane Neural Node Registry  │  │
 │  │ - Per-CPU Circular Runqueues         │    │ - Node Descriptor Lifecycle Storage  │  │
 │  │ - Work-Stealing across SMP Cores     │    │ - Lock-Free Axonal Fast-Path Rings   │  │
 │  │ - Fast LSTAR MSR Syscall Gate        │    │ - Capability Authentication Engine   │  │
 │  └──────────────────────────────────────┘    └──────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Bootstrap & Dispatch Sequence

```
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                            SYSTEM BOOT & LAUNCH STAGES                                 │
 │                                                                                        │
 │   Stage 1: Bootloader Handoff (Multiboot 1 / 2)                                        │
 │   - Loads kernel.elf into memory at 1MB (0x100000).                                    │
 │   - Loads boot ramdisk (initrd.tar) as Multiboot module.                               │
 │                                                                                        │
 │   Stage 2: Microkernel Initialization (PRK-LLB)                                        │
 │   - Enters Long Mode (64-bit), sets up GDT, TSS, IDT, and LAPIC/IO-APIC.              │
 │   - Initializes PMM, Buddy Allocator, VMM, and Kernel Heap (8MB).                      │
 │   - Relocates initrd.tar to safe physical memory (0x6000000 / 96MB).                   │
 │   - Boots all AP cores sequentially with synchronized logging.                         │
 │   - Enables LSTAR Fast Syscalls, Dual-Plane Node Registry, and TarArchive parser.      │
 │                                                                                        │
 │   Stage 3: Genesis (PID 1) Dispatch                                                    │
 │   - Microkernel locates 'genesis.bax' inside initrd.tar.                               │
 │   - BaxLoader validates 'NEO/BAX\0' magic, allocates isolated User PML4, maps segments.│
 │   - Memory-maps embedded resource table directly to 0x50000000.                        │
 │   - Scheduler dispatches PID 1 in Ring 3 (CPL=3).                                      │
 │                                                                                        │
 │   Stage 4: Genesis Userspace Subsystem Initialization                                  │
 │   - genesis.bax parses its embedded manifest to determine system boot profile.         │
 │   - Spawns dev_mgr.bax to probe PCI/ACPI buses and attach hardware driver nodes.       │
 │   - Spawns plexus_mgr.bax to oversee background system services.                       │
 │   - Spawns compositor.bax to claim the video framebuffer aperture via SYS_SHMEM_MAP.   │
 │   - Spawns input_srv.bax to subscribe to kernel Node #2 (hw.input.raw).                │
 │   - Spawns wm.bax and launches the interactive desktop or application shell.           │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Subsystem Details & Responsibilities

### A. PID 1 Orchestrator: `genesis.bax`
- **Minimal Core:** Unlike monolithic Unix `systemd`, `genesis.bax` does not contain loggers, network managers, or DNS resolvers. It is purely an orchestrator.
- **Fault Recovery:** Maintains supervision over the Big Four managers. If `compositor.bax` or `dev_mgr.bax` crashes, the microkernel reaps the terminated PID and notifies `genesis.bax`, which immediately restarts the service.

### B. Device & Driver Arbiter: `dev_mgr.bax`
- **Bus Scanning:** Enumerates PCI configuration space (`0xCF8`/`0xCFC`) and ACPI tables.
- **Manifest Matching:** Inspects `.bax` binaries in the system directory for matching hardware signatures:
  ```json
  {
    "app_id": "sys.driver.bga",
    "kind": "driver",
    "matches": [
      { "bus": "pci", "vendor": "0x1234", "device": "0x1111" }
    ],
    "capabilities": ["CAP_FRAMEBUFFER_MAP", "CAP_PCI_CONFIG"]
  }
  ```
- **Driver Process Isolation:** Drivers run with restricted user privileges. A buggy GPU or network driver cannot corrupt kernel page tables.

### C. Service Supervisor: `plexus_mgr.bax`
- **Heartbeat Synapses:** Services connect a dedicated control-plane synapse channel to `plexus_mgr.bax`.
- **Health Probing:** Services emit periodic heartbeat tokens. If a service becomes unresponsive or deadlocks, `plexus_mgr.bax` terminates and respawns it.

### D. Input Service: `input_srv.bax`
- **Kernel Input Decoupling:** The microkernel's IRQ1 (Keyboard) and IRQ12 (Mouse) handlers only copy raw bytes into the lock-free ring buffer of `Node #2` (`hw.input.raw`).
- **Stateful Decoding in Userspace:**
  - `input_srv.bax` translates raw scancodes into UTF-8 characters and virtual keycodes.
  - Assembles 3-byte PS/2 mouse packets, calculates relative $\Delta X$ and $\Delta Y$, clamps mouse coordinates to screen boundaries (`0..1023`, `0..767`), and tracks button state changes.
  - Emits high-level, capability-authenticated `InputEvent` packets to `wm.bax` and `compositor.bax`.

### E. Display Compositor & Window Manager: `compositor.bax` & `wm.bax`
- **Zero-Copy Surface Composition:**
  - Client applications allocate their window canvas using `SYS_SHMEM_CREATE`.
  - The compositor maps the client's canvas via `SYS_SHMEM_MAP` without data copying.
  - The compositor renders the final scene into the double-buffered Linear Framebuffer (`0xFD000000`).
- **Tear-Free Hardware Cursor Overlay:**
  - The cursor is rendered on an independent overlay plane, redrawing only dirty rectangles when the mouse moves.

---

## 5. Foundational Kernel Primitives Required Next

To support this userspace driver and compositor architecture, the PRK-LLB microkernel requires two core mechanisms:

1. **Shared Memory (`SYS_SHMEM_CREATE` & `SYS_SHMEM_MAP`):**
   - Allocates shared physical memory frames in PMM.
   - Maps the same physical frames into two or more distinct User PML4 address spaces with configurable permissions (`R`, `W`).
   - Allows userspace drivers to map physical MMIO apertures (VGA Framebuffer, PCI BARs).

2. **Peer-to-Peer Userspace Synapse Channels:**
   - Extends `NodeRegistry.cls` to allow arbitrary userspace nodes to authenticate via capability masks and establish direct fast-path ring buffers with each other.
