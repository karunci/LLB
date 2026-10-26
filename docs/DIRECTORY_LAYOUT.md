# PROS Operating System: Windows + Android Hybrid Directory Hierarchy

## 1. Architectural Philosophy
PROS implements a modern hybrid filesystem layout combining the clean, modular separation of **Android** with the familiar drive-mapping and profile structures of **Windows**:
1. **System Immutability (`/system`):** System daemons, shared libraries, and hardware manifests reside in a read-only partition similar to Android `/system` and Windows `System32`.
2. **Persistent User Data (`/data`):** User installed applications, desktop workspaces, and application data reside under `/data` (equivalent to Android `/data` and Windows `C:\Users`).
3. **Hardware Device Hierarchy (`/dev`):** Hardware virtual devices, MMIO framebuffers, and serial UART streams are exposed as virtual nodes under `/dev`.
4. **Windows Path Compatibility (`C:\` / `C:/`):** The VFS resolver transparently normalizes Windows-style drive prefixes and backslashes into standard hierarchical paths, allowing legacy Windows idioms to function seamlessly alongside native Unix/Android paths.

---

## 2. Directory Tree Structure

```
/ (Root Namespace)
├── system/                  (System Partition: Read-Only Core OS)
│   ├── bin/                 (Core System Daemons & Service Executables)
│   │   ├── genesis.bax      (Root Orchestrator - PID 1)
│   │   ├── disp_srv.bax     (Display Driver Service)
│   │   ├── input_srv.bax    (Unified Input Driver Service)
│   │   ├── compositor.bax   (Direct Framebuffer Desktop Compositor)
│   │   ├── dev_mgr.bax      (Hardware Device Discovery & Arbiter)
│   │   ├── plexus_mgr.bax   (Service Lifecycle Supervisor)
│   │   ├── wm.bax           (Desktop Window Manager)
│   │   └── vfs_srv.bax      (Virtual File System Arbiter)
│   ├── lib/                 (Core Standard & System Libraries)
│   │   ├── libpros.a        (PROS System Library & ABI Stubs)
│   │   ├── libllb.a         (Low-Level Basic Freestanding Runtime)
│   │   └── libgui.a         (2D Graphics & Font Engine)
│   ├── etc/                 (System Configuration & Host Profiles)
│   │   ├── init.cfg         (Genesis Boot Configuration)
│   │   └── hosts            (Local Node Lookup Map)
│   ├── fonts/               (System Typography & Raster Fonts)
│   │   ├── console5x7.fnt   (Microkernel Telemetry Font)
│   │   └── sans8x12.fnt     (Desktop UI Font)
│   └── manifest.json        (OS System Image Manifest)
│
├── data/                    (Data Partition: Writable User & App Storage)
│   ├── app/                 (Installed User Applications - e.g. Windows Program Files)
│   │   ├── user_test.bax    (Ring 3 Test Application)
│   │   └── calc.bax         (Desktop Calculator)
│   └── user/                (User Profiles - e.g. Windows C:\Users and Android /data/user)
│       └── 0/               (Default Administrator / User Profile)
│           ├── Desktop/     (Desktop Workspace Shortcut Store)
│           ├── Documents/   (User Documents)
│           └── Downloads/   (Downloaded Payloads & Archives)
│
├── dev/                     (Device Partition: Virtual Hardware Nodes)
│   ├── disp                 (Display Adapter Control Node)
│   ├── input                (Unified Input Event Stream)
│   ├── fb0                  (Direct Linear Framebuffer Aperture)
│   ├── com1                 (COM1 Serial UART 16550 Port)
│   └── ramdisk0             (USTAR Initial RAMDisk Block Node)
│
└── mnt/                     (Mount Namespace)
    └── c/                   (Windows C: Drive Mount Alias -> Maps to /)
```

---

## 3. Path Normalization Rules in VFS Resolver

The VFS Service (`srv.vfs`) implements an automatic normalization algorithm in `NormalizePath`:
1. **Drive Letter Stripping:** Leading drive designations such as `C:` or `c:` are stripped.
2. **Backslash Conversion:** All Windows backslashes (`\`) are automatically mapped to forward slashes (`/`).
3. **Leading Slash Guarantee:** Guarantees absolute path prefix `/`.
4. **Redundant Slash Collapsing:** Multiple consecutive slashes (`//`) are collapsed into a single `/`.
5. **Trailing Slash Trimming:** Trailing slashes on non-root paths are trimmed.

### Mapping Examples
| Input Path | Normalized Target | Resolution Status |
|:---|:---|:---|
| `C:\system\bin\genesis.bax` | `/system/bin/genesis.bax` | Resolved (`VFS_KIND_FILE`) |
| `c:/data/user/0/Desktop` | `/data/user/0/Desktop` | Resolved (`VFS_KIND_DIR`) |
| `\dev\fb0` | `/dev/fb0` | Resolved (`VFS_KIND_DEV`) |
| `/system/lib/libpros.a` | `/system/lib/libpros.a` | Resolved (`VFS_KIND_FILE`) |
