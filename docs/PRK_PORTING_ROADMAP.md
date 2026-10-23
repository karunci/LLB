# PRK Kernel to Low-Level Basic (LLB) Porting Roadmap

> **Target Architecture:** x86_64 Long Mode Bare-Metal Microkernel  
> **Source Repository:** `~/projects/PRK_TO_PORT_TO_LLB/` (`T:\projects\PRK_TO_PORT_TO_LLB`)  
> **Destination:** `tests/kernel/src/` (compiled via `tests/kernel/Kernel.llbproj`)  
> **Compiler:** `llbc-stage0` (LLVM 21 backend, embedded LLD)

---

## 1. Architectural Design & LLB Language Idioms

Rather than writing simple monolithic C-style procedural modules (`.bas`), the ported kernel leverages the full object-oriented and systems capabilities of **Low-Level Basic**:

### Language Feature Utilization Matrix

| Subsystem Component | LLB Construct | Architectural Role & Justification |
| :--- | :--- | :--- |
| **Port I/O & CPU Primitives** | `Namespace Arch.X86_64` + `Module PortIO` | Zero-overhead inline assembly wrappers (`InB`, `OutB`, `InW`, `OutW`, `IoWait`, `Hlt`, `Cli`, `Sti`) with `Unsafe` fences. |
| **GDT & Segment Descriptors** | `<Packed> Structure GdtEntry`, `Structure GdtDescriptor` | Enforces exact 8-byte and 16-byte TSS descriptor layout with `#Assert SizeOf(GdtTable) = ...`. |
| **Hardware Descriptors (PTE/IDT)** | `<Packed> Structure ... Field As Type * Bits` | Real bitfield layout for Page Table Entries (Present, Writable, User, HugePage, FrameAddress) and IDT Gate flags. |
| **Per-CPU Scratch & State** | `Class PerCpuContext` with `<Instancing(MultiUse)>` | Encapsulates logical CPU state, kernel stack pointer, APIC ID, and current task pointer with explicit `.Initialize(cpuId)`. |
| **Console & Character Devices** | `Interface ICharDevice` + `Implements` | Abstract I/O interface declaring `Sub WriteChar(ByVal ch As Byte)` and `Sub WriteString(...)`. Implemented by both `VgaTerminal` and `SerialUart`. |
| **Drivers (UART, PS/2 Keyboard)** | `Class Drivers.SerialUart`, `Class Drivers.Keyboard` | Encapsulates controller state, I/O ports, FIFO ring buffers, and modifier key tracking with `<Instancing(SingleUse)>`. |
| **Synchronization Primitives** | `Structure Spinlock` with atomic intrinsics | High-signal, ticket or test-and-set SMP spinlocks guarding driver and scheduler state. |
| **Physical Memory Allocator (PMM)** | `Class Mem.PhysicalManager` (`<Instancing(SingleUse)>`) | Manages bitmap memory frames, total frame counts, and allocation state. |
| **Virtual Memory Manager (VMM)** | `Class Mem.VirtualSpace` + `Structure PageTable` | Scoped page directory manipulation, 4-level PML4 translation, and kernel higher-half mappings. |

---

## 2. Phased Implementation Roadmap

```mermaid
graph TD
    P1[Phase 1: Foundation & CPU Core] --> P2[Phase 2: Drivers & Abstractions]
    P2 --> P3[Phase 3: Interrupts & SMP Platform]
    P3 --> P4[Phase 4: Memory Management Subsystem]
    P4 --> P5[Phase 5: Scheduling, IPC & Syscalls]
```

---

### Phase 1: CPU Architecture & Port Primitives
**Goal:** Establish fundamental x86_64 register operations, Port I/O, 64-bit GDT, and TSS.

1. **`src/arch/x86_64/PortIO.bas` (Namespace `Arch.X86_64`):**
   - Source: `include/prk/port_io.h`
   - Routines: `InB`, `OutB`, `InW`, `OutW`, `IoWait` via GCC-style `Asm` with `"a"` and `"Nd"` constraints.
2. **`src/arch/x86_64/Gdt.bas` / `src/arch/x86_64/GdtTypes.bas`:**
   - Source: `include/prk/gdt.h`, `include/prk/tss.h`, `kernel/gdt.c`, `kernel/tss.c`
   - Structs: `<Packed> Structure GdtEntry`, `<Packed> Structure TssDescriptor`, `<Packed> Structure TssEntry`.
   - Invariants: `#Assert SizeOf(GdtEntry) = 8`, `#Assert SizeOf(TssDescriptor) = 16`.
   - Procedure: `Unsafe Sub Initialize(ByVal cpuId As UInt32)` loading GDT via inline `lgdt` and TSS via `ltr`.
3. **`src/sync/Spinlock.bas` (Namespace `Sync`):**
   - Source: `include/prk/spinlock.h`, `kernel/spinlock.c`
   - Struct: `Structure Spinlock` (`Public locked As UInt32`).
   - Procedures: `Acquire`, `Release`, `TryAcquire` with compiler atomic built-ins or pause loops.

---

### Phase 2: Device Abstractions & Early Logging Drivers
**Goal:** Decouple character output using LLB Interfaces, enabling early COM1 serial output and PS/2 keyboard input.

1. **`src/drivers/ICharDevice.cls` (Namespace `Drivers`):**
   - Interface definition:
     ```vb
     Interface ICharDevice
         Sub WriteChar(ByVal ch As Byte)
         Sub WriteString(ByVal str As Pointer To Byte)
     End Interface
     ```
2. **`src/drivers/SerialUart.cls` (Namespace `Drivers`):**
   - Source: PRK COM1 early logging logic.
   - Class: `<Instancing(SingleUse)> Class SerialUart`
   - Implements: `Implements ICharDevice`
   - Encapsulates: COM1 port base `&H3F8`, baud rate divisor setting, line control register, and status checks.
3. **`src/drivers/Keyboard.cls` (Namespace `Drivers`):**
   - Source: `include/prk/keyboard.h`, `kernel/keyboard.c`
   - Class: `<Instancing(SingleUse)> Class Keyboard`
   - Encapsulates: Ports `&H60` / `&H64`, 256-byte circular scancode buffer, Shift/Ctrl/Alt modifier states, and US QWERTY scancode lookup table.

---

### Phase 3: Interrupts, Exceptions & APIC Platform
**Goal:** Complete IDT gate registration with `<Interrupt>` handlers and setup local APIC / IO-APIC.

1. **`src/arch/x86_64/Idt.bas` Refactoring:**
   - Source: `include/prk/idt.h`, `kernel/idt.c`, `kernel/isr.S`
   - Structs: `<Packed> Structure IdtEntry` with bitfield attributes:
     ```vb
     <Packed>
     Structure IdtEntry
         Public OffsetLow As UInt16
         Public Selector As UInt16
         Public Ist As Byte * 3
         Public Reserved0 As Byte * 5
         Public GateType As Byte * 4
         Public ZeroBit As Byte * 1
         Public Dpl As Byte * 2
         Public Present As Byte * 1
         Public OffsetMid As UInt16
         Public OffsetHigh As UInt32
         Public Reserved1 As UInt32
     End Structure
     #Assert SizeOf(IdtEntry) = 16
     ```
   - Handlers: Exception ISRs decorated with `<Interrupt>` attribute.
2. **`src/arch/x86_64/Apic.bas` & `IoApic.bas`:**
   - Source: `include/prk/apic.h`, `include/prk/ioapic.h`, `kernel/apic.c`, `kernel/ioapic.c`
   - Module: Memory-mapped I/O using `Volatile Pointer To UInt32` for LAPIC registers (Spurious Vector, EOI, ICR, Timer).

---

### Phase 4: Memory Management (PMM & VMM)
**Goal:** Self-contained physical page frame allocator and 4-level x86_64 page directory management.

1. **`src/mem/PhysicalManager.cls` (Namespace `Mem`):**
   - Source: `include/prk/pmm.h`, `kernel/pmm.c`
   - Class: `<Instancing(SingleUse)> Class PhysicalManager`
   - Encapsulates: Physical memory bitmap, total memory bytes, used frames, and frame allocation / deallocation routines (`AllocFrame`, `FreeFrame`).
2. **`src/mem/PageTableTypes.bas` & `src/mem/VirtualManager.cls`:**
   - Source: `include/prk/vmm.h`, `kernel/vmm.c`
   - Bitfield Page Table Entries:
     ```vb
     <Packed>
     Structure PageTableEntry
         Public Present As Byte * 1
         Public Writable As Byte * 1
         Public UserAccessible As Byte * 1
         Public WriteThrough As Byte * 1
         Public CacheDisabled As Byte * 1
         Public Accessed As Byte * 1
         Public Dirty As Byte * 1
         Public HugePage As Byte * 1
         Public Global As Byte * 1
         Public Available As Byte * 3
         Public FrameAddress As UInt64 * 40
         Public AvailableHigh As UInt16 * 11
         Public NoExecute As Byte * 1
     End Structure
     #Assert SizeOf(PageTableEntry) = 8
     ```
   - Class: `Class VirtualManager` providing `MapPage`, `UnmapPage`, and page table walker routines.
3. **`src/mem/KernelHeap.cls`:**
   - Source: `include/prk/heap.h`, `kernel/heap.c`
   - Bump and slab/freelist allocator for kernel dynamic allocations.

---

### Phase 5: Multitasking, IPC & System Calls
**Goal:** Cooperative/preemptive thread scheduling, Inter-Process Communication, and x86_64 `syscall`/`sysret` mechanism.

1. **`src/sched/Task.cls` (Namespace `Sched`):**
   - Source: `include/prk/sched.h`, `kernel/sched.c`, `kernel/switch.S`
   - Encapsulates: Task ID, execution state (Ready, Running, Blocked), CPU register context, kernel stack pointer, and page directory (CR3).
2. **`src/sched/Scheduler.cls`:**
   - Round-robin task queue and context-switching routines.
3. **`src/ipc/MessageQueue.cls` (Namespace `Ipc`):**
   - Source: `include/prk/ipc.h`, `kernel/ipc.c`
   - Porting synchronous and asynchronous IPC messaging.
4. **`src/sys/Syscall.bas` (Namespace `Sys`):**
   - Source: `include/prk/syscall.h`, `kernel/syscall.c`, `kernel/syscall_entry.S`
   - MSR configuration (`MSR_EFER`, `MSR_STAR`, `MSR_LSTAR`, `MSR_FMASK`) and system call dispatcher.

---

## 3. Directory Layout in `tests/kernel/`

The ported files will be organized into a modern modular structure:

```text
tests/kernel/
├── Kernel.llbproj                  <-- Updated project manifest
├── linker.ld
└── src/
    ├── KernelMain.bas              <-- Kernel entrypoint & subsystem orchestrator
    ├── arch/
    │   └── x86_64/
    │       ├── boot.S              <-- Multiboot1/2 assembly entry
    │       ├── PortIO.bas          <-- Namespace Arch.X86_64, Module PortIO
    │       ├── GdtTypes.bas        <-- Packed GDT/TSS structures & static asserts
    │       ├── Gdt.bas             <-- GDT initialization & reload routines
    │       ├── IdtTypes.bas        <-- Packed IDT structures & bitfields
    │       ├── Idt.bas             <-- IDT registration & handlers
    │       ├── Apic.bas            <-- Local APIC MMIO controller
    │       └── IoApic.bas          <-- I/O APIC routing
    ├── sync/
    │   └── Spinlock.bas            <-- Atomic SMP spinlocks
    ├── drivers/
    │   ├── ICharDevice.cls         <-- Abstract character device interface
    │   ├── Terminal.bas            <-- VGA Text Mode terminal driver
    │   ├── SerialUart.cls          <-- 16550 UART serial driver (Implements ICharDevice)
    │   └── Keyboard.cls            <-- PS/2 Keyboard controller class
    └── mem/
        ├── PmmTypes.bas            <-- Frame structures & constants
        ├── PhysicalManager.cls     <-- PMM bitmap frame allocator
        ├── PageTableTypes.bas      <-- 64-bit PTE bitfield structures
        └── VirtualManager.cls      <-- 4-level paging manager
```

---

## 4. Current Progress & Verification Status

### Phase 1 & Phase 2: COMPLETE and Verified in QEMU (64-bit Long Mode)
- [x] **Compiler Core Extensions (`llbc-stage0`):**
  - Inline `Asm` statement operand parsing (`[output : input : clobbers]`) with GCC-to-LLVM register constraint mapping (`=a` -> `={ax}`, `Nd` -> `N{dx}`, `memory` -> `~{memory}`).
  - Multi-line `Asm` instruction string literal concatenation with `\n\t`.
  - Multi-part dotted type spec parsing (`while match(Dot) ...`) and suffix type resolution across namespaces (`Sync.Spinlock` -> `SpinlockOps.Spinlock`).
  - Recursive nested `Namespace` block parsing supporting multiple `Class`, `Module`, and `Interface` definitions within the same container block.
  - Container-level `<Instancing(...)>` attribute recognition directly preceding nested classes with default fallback to `MultiUse`.
  - Intra-class member procedure resolution and automatic `Me` pointer argument injection with optional parameter default value substitution.
  - `<Instancing(SingleUse)>` singleton symbol generation (`__singleton_<NormClass>`) and automated `Me` pointer argument injection on method calls (`Drivers.Terminal.Initialize`, `Drivers.SerialUart.Initialize`).
  - Implicit `Me` pointer access for class field reads, array index writes, and member subroutine calls.
- [x] **Bare-Metal Bootloader & Runtime (`boot.S`):**
  - Activated SSE vector instructions in 64-bit CR4/CR0 (`CR4.OSFXSR`, `CR4.OSXMMEXCPT`, `CR0.MP`, clear `CR0.EM`) to guarantee LLVM struct zeroing does not trigger #GP.
  - Added freestanding runtime symbols (`abort`, `dprintf`).
- [x] **Subsystem Drivers & Modules:**
  - `src/arch/x86_64/PortIO.bas`: Port I/O primitives (`InB`, `OutB`, `InW`, `OutW`, `IoWait`).
  - `src/arch/x86_64/GdtTypes.bas` & `Gdt.bas`: Packed GDT and TSS segment descriptors.
  - `src/sync/Spinlock.bas`: Atomic ticket/flag spinlocks with pause loops.
  - `src/drivers/ICharDevice.cls`: Abstract character device interface (`Namespace Drivers`).
  - `src/drivers/SerialUart.cls`: 16550 UART COM1 driver (`&H3F8`) implementing `ICharDevice` (`<Instancing(SingleUse)>`).
  - `src/drivers/Keyboard.cls`: PS/2 Keyboard controller class (`&H60`/`&H64`) (`<Instancing(SingleUse)>`).
  - `src/drivers/Terminal.cls`: Bare-metal VGA Text Mode 80x25 console driver class implementing `ICharDevice` (`<Instancing(SingleUse)>`).
  - `src/KernelMain.bas`: Orchestrated kernel entry verifying long mode, UART COM1, GDT/TSS, Keyboard, VGA Terminal, and IDT gates.
- [x] **Verification:**
  - 100% test pass on userland suite (all 65 tests + 26 compiler rejection guards).
  - Clean QEMU execution to halt with verified serial output:
    ```
    [PRK-OS KERNEL] Booting Low-Level Basic Kernel in QEMU!
    [PRK-OS KERNEL] Multiboot Verified. Long mode active.
    [UART] COM1 Driver Online!
    [PRK-OS KERNEL] Initializing 64-bit GDT & TSS...
    [PRK-OS KERNEL] GDT & TSS initialized successfully.
    [PRK-OS KERNEL] PS/2 Keyboard controller initialized.
    [PRK-OS KERNEL] VGA Terminal Driver initialized (&HB8000).
    [PRK-OS KERNEL] Initializing IDT interrupt descriptors...
    [PRK-OS KERNEL] IDT gates registered successfully.
    [PRK-OS KERNEL] Kernel execution completed successfully. Halting CPU.
    ```

### Phase 4: Memory Management Subsystem (PMM, Buddy Allocator, VMM)
- [x] **`src/mem/PhysicalManager.cls` (Namespace `Mem`):**
  - Bitmap physical frame allocator managing page allocation, reservation, and Multiboot1 memory map traversal.
- [x] **`src/mem/BuddyAllocator.cls` (Namespace `Mem` / `<Instancing(SingleUse)> Class BuddyAllocator`):**
  - Binary Buddy Page Allocator with 11 orders (Order 0: 4KB to Order 10: 4MB blocks) across 64MB managed memory pool.
  - Verified in QEMU: dynamic page splitting down to Order 0, recursive buddy coalescing back to Order 10.
- [x] **`src/mem/VirtualMemoryManager.cls` (Namespace `Mem` / `<Instancing(SingleUse)> Class VirtualMemoryManager`):**
  - 4-level x86_64 Virtual Memory Manager (`Pml4Index`, `PdptIndex`, `PdIndex`, `PtIndex`).
  - Implements `MapPage`, `UnmapPage`, `VirtToPhys`, `MapRange`, and TLB invalidation (`invlpg`).
  - Verified in QEMU: mapped `0xDEADBEEF000` to physical frame `0x4C00000`, verified 64-bit volatile read/write (`0x123456789ABCDEF0`), verified address resolution, and cleanly unmapped.

---

## 5. Next Steps: Phase 5 (ACPI Table Discovery, MADT & FADT Parsers)
1. **`src/arch/x86_64/Acpi.bas` (Namespace `Arch` / `Module Acpi`):**
   - Scan BIOS EBDA (`0x80000-0x9FFFF`) and read-only BIOS ROM space (`0xE0000-0xFFFFF`) for `"RSD PTR "` signature.
   - Verify checksums for RSDP v1.0 and extended RSDP v2.0 (XSDT).
   - Parse MADT (Multiple APIC Description Table) to enumerate LAPIC cores and IO-APIC controllers.
   - Parse FADT (Fixed ACPI Description Table) to locate ACPI Power Management registers (`PM1a_CNT_BLK`, `S5` sleep object).
2. **`src/sys/HardwareInfo.cls` (Namespace `Sys` / `Class HardwareInfo`):**
   - CPUID instruction queries for CPU vendor, model, feature flags, APIC ID, and core topology.
3. **`src/arch/x86_64/Smp.bas`:**
   - Multi-core AP initialization via INIT-SIPI-SIPI sequence.
4. **`src/arch/power/PowerManager.cls`:**
   - ACPI SCI event handling, soft reboot, and S5 clean power-off.
