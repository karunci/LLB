# BAX Executable Specification (`NEO/PE-BAX`)

**Operating System:** PROS (Personal Research Operating System)  
**Kernel:** PRK-LLB (Personal Research Kernel in Low-Level Basic)  
**File Extension:** `.bax` (Basic Application eXecutable)  
**Magic Signature:** `NEO/BAX\0` (`0x005841422F4F454E` in little-endian 64-bit integer)

---

## 1. Overview & Architecture

The **BAX** binary format is the native application executable format for **PROS / PRK-LLB**. Inspired by modern microkernel principles and the structured sectioning of Windows PE, BAX is tailored specifically for **Low-Level Basic (LLB)**.

Unlike legacy ELF binaries that separate code from application assets or Windows PE binaries that require complex RVA (Relative Virtual Address) trees, BAX provides:
1. **Streamlined 64-Byte Header:** Minimalist, zero-cruft execution descriptor.
2. **Direct Memory-Mapped Resource Table:** Applications can embed icons, metadata manifests, and assets that are mapped directly into user virtual space (`0x50000000`), allowing **zero-syscall direct pointer access**.
3. **Subsystem Differentiation:** Clear distinction between CLI (Console), GUI (Framebuffer Compositor), and Neural Compute Node services.
4. **Lightweight CLI Support:** Pure console applications specify `ResourceCount = 0`, entirely omitting the resource table and asset payload for minimal binary footprint.

---

## 2. File Layout

```text
+---------------------------------------------------------------+
|                      BaxHeader (64 Bytes)                     |
|  Magic ("NEO/BAX\0"), Arch, Subsystem, EntryPoint, ImageBase  |
+---------------------------------------------------------------+
|                 Segment Table (48 Bytes per Entry)            |
|  Loadable sections: .text, .rodata, .data, .bss descriptors   |
+---------------------------------------------------------------+
|             Resource Directory (48 Bytes per Entry)           |
|  (Omitted if ResourceCount = 0 for pure CLI applications)     |
+---------------------------------------------------------------+
|                   Segment Data Payloads                       |
|  Raw compiled machine code and initialized global data        |
+---------------------------------------------------------------+
|                    Asset Data Payloads                        |
|  Raw asset blobs: icons (PNG/BMP), JSON manifests, fonts      |
+---------------------------------------------------------------+
```

---

## 3. Data Structures

### A. Main Executable Header (`BaxHeader` - 64 Bytes)

```vb
<Packed>
Public Structure BaxHeader
    Public Magic            As UInt64    ' ASCII "NEO/BAX\0" (0x005841422F4F454E)
    Public FormatVersion    As UInt16    ' Format revision (1)
    Public TargetArch       As UInt16    ' 1 = x86_64, 2 = AArch64, 3 = RISC-V 64
    Public Subsystem        As UInt16    ' 1 = Console, 2 = GUI, 3 = Neural Node
    Public Flags            As UInt16    ' Bit 0: ASLR Compatible
    Public EntryPoint       As UInt64    ' Virtual address of application entry point
    Public ImageBase        As UInt64    ' Preferred base virtual address (e.g. 0x40000000)
    Public ImageSize        As UInt64    ' Total virtual address span in memory
    Public SegmentsOffset   As UInt32    ' File offset to Segment Table
    Public SegmentCount     As UInt16    ' Number of loadable segments
    Public ResourceCount    As UInt16    ' Number of embedded assets (0 for pure CLI)
    Public ResourceOffset   As UInt32    ' File offset to Resource Directory (0 if none)
    Public ResourceVirtAddr As UInt64    ' Virtual address where resource table is mapped (e.g. 0x50000000)
    Public Reserved         As UInt32    ' Reserved for alignment (must be 0)
End Structure
#Assert SizeOf(BaxHeader) = 64
```

#### Subsystem Identifiers:
- **`SUBSYSTEM_CONSOLE` (`1`):** Pure command-line application. Operates via standard serial/terminal console.
- **`SUBSYSTEM_GUI` (`2`):** Windowed application. Interfaces with the 1024x768 Linear Framebuffer compositor. Requires `ASSET_ICON` and `ASSET_MANIFEST`.
- **`SUBSYSTEM_NEURAL_NODE` (`3`):** Background microkernel compute service communicating over Axon Synapse channels.

---

### B. Segment Descriptor (`BaxSegment` - 48 Bytes)

Each loadable memory section (`.text`, `.data`, `.rodata`, `.bss`) is described by a `BaxSegment`:

```vb
<Packed>
Public Structure BaxSegment
    Public Name         As Byte * 8  ' Null-padded section name (e.g., ".text\0\0\0")
    Public FileOffset   As UInt64    ' File offset where initialized data begins
    Public FileSize     As UInt64    ' Initialized data size in file
    Public VirtAddr     As UInt64    ' Target virtual address in User PML4
    Public MemSize      As UInt64    ' Span in virtual memory (MemSize >= FileSize)
    Public Flags        As UInt32    ' Bit 0: Read (1), Bit 1: Write (2), Bit 2: Execute (4)
    Public Reserved     As UInt32    ' Must be 0
End Structure
#Assert SizeOf(BaxSegment) = 48
```

> **BSS Handling:** When `MemSize > FileSize`, the kernel loader automatically zero-initializes the trailing `MemSize - FileSize` bytes during page allocation.

---

### C. Resource Directory Entry (`BaxResourceEntry` - 48 Bytes)

```vb
<Packed>
Public Structure BaxResourceEntry
    Public AssetType    As UInt32    ' Asset category (1..5)
    Public AssetId      As UInt32    ' Numeric asset identifier (e.g., 100)
    Public Name         As Byte * 16 ' Null-terminated ASCII name (e.g., "manifest.json")
    Public FileOffset   As UInt64    ' Offset from start of .bax file to raw asset bytes
    Public ByteLength   As UInt64    ' Length of asset in bytes
    Public VirtAddr     As UInt64    ' Virtual address where asset is mapped in user space
    Public Flags        As UInt32    ' 0 = Raw, 1 = Compressed
    Public Reserved     As UInt32    ' Must be 0
End Structure
#Assert SizeOf(BaxResourceEntry) = 48
```

#### Asset Type Identifiers:
- **`ASSET_MANIFEST` (`1`):** Application metadata manifest (JSON/TOML) detailing App Name, Version, Author, and required capabilities.
- **`ASSET_ICON` (`2`):** Application icon bitmap or PNG for desktop shell and taskbar rendering.
- **`ASSET_IMAGE` (`3`):** Graphical textures, background art, or splash screens.
- **`ASSET_FONT` (`4`):** Custom typography glyph tables.
- **`ASSET_CUSTOM` (`5`):** Raw application-defined configuration or data blobs.

---

## 4. Memory-Mapped Resource Access in Userspace

When `ResourceCount > 0`:
1. The kernel loader maps the Resource Table and all asset payloads starting at `ResourceVirtAddr` (`0x50000000`).
2. The user runtime (`BRT`) and application code can inspect embedded resources directly:

```vb
' Basic Runtime Userspace Resource Access:
Dim resTable As Pointer To BaxResourceEntry = CPtr(Pointer To BaxResourceEntry, &H50000000)
Dim manifestStr As Pointer To Byte = CPtr(Pointer To Byte, resTable(0).VirtAddr)
' Access manifest data directly with zero syscall overhead!
```

---

## 5. Tooling & Packaging Pipeline

The compilation pipeline converts Low-Level Basic source code into `.bax` executables:

```text
Low-Level Basic Sources (*.bas, *.cls)
            │
            ▼ (llbc-stage0)
Standard Object Files (*.o)
            │
            ▼ (ld.lld)
Intermediate ELF64 Binary
            │
            ▼ (tools/bax_pack.py) + Optional Assets (icon, manifest)
Target Executable: application.bax
            │
            ▼ (tar cf initrd.tar *.bax)
In-Memory USTAR Ramdisk: initrd.tar
```
