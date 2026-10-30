# Personal Research Operating System (PRK-OS): Windows + Android Hybrid Directory Hierarchy

## 1. Architectural Philosophy
PROS implements a modern hybrid filesystem layout combining the clean application sandboxing and modular separation of **Android** with the familiar drive-mapping and profile structures of **Windows**:
1. **NOT Another Unix/Linux Clone:** PROS intentionally rejects legacy Unix conventions (`/bin`, `/sbin`, `/usr`, `/etc`, `/var`, `/dev`, `/tmp`).
2. **First-Class Application Bundles (`/Apps`):** User installed applications reside in self-contained folders with their own binaries, local libraries, data, and configurations.
3. **Dedicated System Root (`/System`):** All core system software, system servers/daemons, system drivers, system libraries, and OS configurations are organized cleanly under `/System`.
4. **User Profiles (`/Users`):** User profiles and account workspaces reside under `/Users` (e.g. `/Users/Default/Desktop`).
5. **Windows Path Compatibility (`C:\` / `C:/`):** The VFS resolver transparently normalizes Windows-style drive prefixes and backslashes into standard hierarchical paths, allowing legacy Windows idioms to function seamlessly.

---

## 2. Directory Tree Structure

```
sysroot (/)
├── Apps/                      (User installed apps folders, libraries, data, configs)
│   ├── Terminal/
│   │   ├── terminal.bax       (Terminal Emulator application)
│   │   └── lib/               (App-specific dynamic libraries)
│   ├── SysMon/
│   │   └── sys_mon.bax        (System Resource Monitor GUI application)
│   ├── NodeViewer/
│   │   └── node_viewer.bax    (Synapse & Node Graph Viewer application)
│   └── UserApp/
│       └── user_app.bax       (User test application)
│
├── Libraries/                 (System-wide shared libraries)
│
├── System/                    (System-related files: configs, apps, libraries, drivers, services)
│   ├── Apps/                  (Built-in system applications)
│   │   └── CoreUtils/         (Standard userland CLI utilities)
│   │       ├── ls.bax         (Directory listing utility)
│   │       ├── cat.bax        (File display utility)
│   │       ├── echo.bax       (Standard text printing utility)
│   │       ├── uptime.bax     (System uptime utility)
│   │       └── ver.bax        (System version utility)
│   ├── Libraries/             (System libraries)
│   │   ├── libpros.a          (Personal Research Operating System API & ABI Stubs)
│   │   └── libllb_metal.a     (Low-Level Basic Freestanding Runtime)
│   ├── Configurations/        (Operating system and environment configurations)
│   │   ├── environment.cfg    (OS identity, revision, and kernel environment)
│   │   └── ramdisk0.cfg       (RAM disk partition configuration)
│   ├── Drivers/               (Device drivers & hardware abstraction nodes)
│   │   ├── pci.disp.lfb       (Linear Framebuffer Driver node)
│   │   └── ps2.input          (PS/2 Keyboard & Mouse Driver node)
│   └── Services/              (System daemons / microkernel servers)
│       ├── genesis.bax        (Root Orchestrator - PID 1)
│       ├── disp_srv.bax       (Display Driver Service)
│       ├── input_srv.bax      (Unified Input Driver Service)
│       ├── compositor.bax     (Direct Framebuffer Desktop Compositor)
│       ├── dev_mgr.bax        (Hardware Device Discovery & Arbiter)
│       ├── plexus_mgr.bax     (Service Lifecycle Supervisor)
│       ├── wm.bax             (Desktop Window Manager)
│       ├── ramfs_srv.bax      (Dynamic RAM Disk Filesystem Service)
│       └── vfs_srv.bax        (Virtual File System Arbiter)
│
└── Users/                     (User accounts directory)
    └── Default/               (Default User Profile)
        ├── Desktop/           (Desktop Workspace Shortcut Store)
        └── Documents/         (User Documents)
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
| `C:\System\Servers\genesis.bax` | `/System/Servers/genesis.bax` | Resolved (`VFS_KIND_FILE`) |
| `c:/Users/Default/Desktop` | `/Users/Default/Desktop` | Resolved (`VFS_KIND_DIR`) |
| `\System\Servers\compositor.bax` | `/System/Servers/compositor.bax` | Resolved (`VFS_KIND_FILE`) |
| `/System/Libraries/libpros.a` | `/System/Libraries/libpros.a` | Resolved (`VFS_KIND_FILE`) |
| `C:\Apps\Terminal\terminal.bax` | `/Apps/Terminal/terminal.bax` | Resolved (`VFS_KIND_FILE`) |

---

## 4. Mount Tree Hierarchy & Shell Default Working Directory

1. **Root Ownership by TarFS:**
   - The boot ramdisk (`initrd.tar`) is mounted by `srv.vfs` at the root mount point (`/` / `X:\`).
   - `TarFS` owns root and all default subtrees (`/System`, `/Apps`, `/Libraries`) with zero-copy read performance.
2. **Subtree Claiming via Mount Points:**
   - External filesystem Plexus services (such as `fs.ramfs` for dynamic in-memory writable user files) register specific mount points (e.g. `/Users`), thereby claiming that entire subtree.
   - Longest-prefix matching ensures requests to `/Users/...` route across Synapse IPC to `fs.ramfs`, while all other paths resolve to `TarFS`.
3. **Shell Default Working Directory:**
   - Prior to multi-user account subsystems, the default shell working directory is root (`X:\`), with prompt `pros::\> `.
   - Navigating into subdirectories displays the leaf folder name (e.g. `cd Apps\Terminal` -> `pros::Terminal\> `).

