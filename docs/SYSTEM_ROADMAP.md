# PROS Userland & Application Ecosystem Roadmap (`SYSTEM_ROADMAP`)

> **Subsystem Scope:** Native Applications, System Utilities, GUI Tools, and BAX Packaging  
> **Source Directory:** `services/` (applications) & `tests/user_app/`  
> **Status:** Operational on Bare-Metal, QEMU, and VirtualBox  

---

## 1. Application Ecosystem Overview

Applications in PROS are native Low-Level Basic executables built as freestanding ELF64 or BAX (Basic Application eXecutable) binaries. They interact with the operating system through `libpros` system bindings and Synapse IPC.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PROS Graphical Desktop                          │
├─────────────────────┬─────────────────────┬────────────────────────────┤
│ Terminal Console    │ System Monitor      │ Node Topology Viewer       │
│ (/Apps/Terminal)    │ (/Apps/SysMon)      │ (/Apps/NodeViewer)         │
│ • Command line      │ • CPU & Mem gauges  │ • Service connection graph │
│ • Shell built-ins   │ • Task list & PIDs  │ • Channel bandwidth meters │
├─────────────────────┴─────────────────────┴────────────────────────────┤
│                  Pure LLB Standard Library (libpros)                    │
│            String • Memory • Math • Stdio • Font • Graphics            │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Applications & Status

### 2.1 Terminal Console (`/Apps/Terminal`)
- **Location:** `services/terminal/`
- **Features:** Interactive text console with ANSI-compatible display, scrollback history, and keyboard command parsing.
- **Client Canvas:** Direct client surface rendering into shared memory window backbuffers.
- **Status:** Operational with Dual-Plane VFS integration, dynamic prompt (`pros::<dir>\>`), and canonical path resolution.
- **Next Steps:**
  - Modernize from duplicate font blitters to `Pros.Font.DrawText`.
  - [x] Standard CoreUtils built-in and standalone utilities (`ls`, `cat`, `echo`, `uptime`, `ver`).
  - [ ] Dynamic binary execution from `PATH` using microkernel `Process.Spawn` (`SYS_PROCESS_SPAWN`).

### 2.2 System Monitor (`/Apps/SysMon`)
- **Location:** `services/sys_mon/`
- **Features:** Real-time system telemetry window displaying CPU load graphs, physical page utilization (PMM vs Buddy), active task list, uptime, and frame rate metrics.
- **Status:** Operational with live graph rendering.
- **Next Steps:**
  - Leverage `Pros.Graphics` for unified chart and bar drawing.
  - Display thread CPU times and memory footprints per PID.

### 2.3 Node Topology Viewer (`/Apps/NodeViewer`)
- **Location:** `services/node_viewer/`
- **Features:** Graphical inspector displaying the active neural node network, connected synapse channels, and message throughput.
- **Status:** Operational.
- **Next Steps:**
  - Interactive channel ping and message tracing.

### 2.4 BAX (Basic Application eXecutable) Format & Ramdisk Packaging
- **Specification:** [`BAX_EXECUTABLE_SPECIFICATION.md`](BAX_EXECUTABLE_SPECIFICATION.md)
- **Features:** Self-contained application packages embedding code, data, icon assets, and manifest descriptors.
- **Status:** Format specified and initial ramdisk unpacker functional.
- **Next Steps:**
  - Package standalone apps as `.bax` packages on the USTAR filesystem.

---

## 3. Standard Utilities & Future Applications

- [ ] **Text Editor (`/Apps/Edit`):** Simple multi-line text editor with keyboard navigation and file save/load via `srv.vfs`.
- [ ] **File Explorer (`/Apps/Files`):** Graphical file manager browsing Windows (`C:\...`) and Unix (`/...`) directory trees.
- [ ] **Calculator (`/Apps/Calc`):** Standard mathematical calculator demonstrating LLB GUI event handling and widgets.
- [ ] **Network Stack & Telnet/HTTP Client:** Basic Ethernet packet driver and lightweight socket client.

---

## 4. Application Size Optimization with `.bdl`

Currently, because each user application statically includes `libpros.a` and runtime functions, binary footprints range from 80 KB to 150 KB.

With the introduction of **`libpros.bdl` (Basic Dynamic Library)** in Phase 5:
- Binary sizes will drop to **4 KB – 8 KB**.
- All applications will map a single, shared instance of `libpros.bdl` into their virtual address spaces at `0x60000000`.
- System memory consumption will decrease by over 70% across the desktop environment.

