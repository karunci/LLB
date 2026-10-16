## Low-Level Basic (LLB) Architectural & Language Specification

---

### Executive Summary

**Low-Level Basic (LLB)** is an ahead-of-time (AOT) compiled systems programming language. It combines the familiar readable syntax and object model of Microsoft Visual Basic 6 (Modules, Classes, `ByVal`/`ByRef`, `Sub`/`Function`) with bare-metal execution semantics needed to develop operating system kernels, bootloaders, device drivers, and freestanding applications.

LLB eliminates the runtime overhead of classic BASIC engines (such as dynamic `Variant` types, COM/OLE dynamic resolution, or mandatory heap garbage collection). It introduces explicit fixed-width data types, low-level pointer semantics (`Pointer To T`), volatile memory-mapped I/O controls, explicit struct alignment directives, and inline assembly integration.

The reference compiler toolchain (`llbc`) is designed to be **fully self-hosting**, parsing `.llbproj` project descriptors and emitting native machine code or ELF/PE binaries via an embedded LLVM IR generator and embedded LLD linker.

---

### Language Semantics & Execution Model

#### Compilation Pipeline & Toolchain Architecture

The LLB driver (`llbc`) executes an end-to-end compilation pass:

1. **Manifest Processing:** Parses `.llbproj` project descriptors for targets, entry points, linker scripts, assembly stubs (`.S`), modules (`.bas`), and classes (`.cls`).
2. **Frontend Analysis:** Lexes and parses source files into an Abstract Syntax Tree (AST), resolving symbol tables and enforcing memory safety rules.
3. **IR Generation:** Translates AST structures into LLVM Intermediate Representation (IR). Classes are lowered to flat C-style structures with implicit `Me` (`this`) context pointers.
4. **Code Emission:** Emits target-specific object files (`.o`) via LLVM TargetMachine.
5. **In-Process Linking:** Directly invokes the embedded LLD C++ driver to link object files into freestanding ELF64, PE32+, Mach-O, or raw binary formats.

```
+-----------------------------------------------------------------------------------+
|                                 LLBC Compiler Driver                              |
|                                                                                   |
|  +--------------------+    +---------------------+    +------------------------+  |
|  |   .llbproj / Source|    | AST & Symbol Table  |    |     LLVM IR Generator  |  |
|  |   Parser Engine    | -> |   (Type Inference)  | -> | (Freestanding Lowering)|  |
|  +--------------------+    +---------------------+    +------------------------+  |
|                                                                    |              |
|  +--------------------+    +---------------------+                 v              |
|  | Target Executable  |    |      LLD Linker     |    +------------------------+  |
|  |  (ELF / PE / Bin)  | <- |  (Embedded Driver)  | <- |   Target Machine Code  |  |
|  +--------------------+    +---------------------+    |    (.o Direct In-Mem)   |  |
|                                                       +------------------------+  |
+-----------------------------------------------------------------------------------+

```

#### Memory & Safety Model

LLB uses a dual-mode memory safety architecture:

* **Safe Mode (Default):** Enforces static type bounds, array boundary checks, and null reference checks. Suitable for hosted desktop applications.
* **Unsafe Mode (`Unsafe` Keyword):** Required for direct physical memory casting (`CPtr`), pointer dereferencing (`Pointer To T`), inline assembly blocks (`Asm`), and raw physical hardware manipulation.

---

### Lexical Conventions & Syntax Grammar

#### Case Sensitivity

LLB keywords, identifiers, module names, and function names are **case-insensitive**, maintaining full compatibility with classic Visual Basic conventions (`Sub`, `sub`, and `SUB` are identical).

#### Keywords & Reserved Words

```text
Module       Class        Structure    End          Sub          Function
Public       Private      Dim          As           ByVal        ByRef
Pointer      To           Volatile     Unsafe       Optional     CPtr
CType        Import       Asm          Do           Loop         While
For          To           Step         Next         If           Then
ElseIf       Else         Exit         Select       Case         Me

```

---

### Data Types & Type System

LLB replaces dynamic typing with explicit fixed-width static primitive types and zero-cost pointer abstractions.

#### Primitive Types

| Type | Width | Description |
| --- | --- | --- |
| `Byte` / `UByte` | 8-bit | Unsigned 8-bit byte (`0` to `255`) |
| `Int16` / `UInt16` | 16-bit | Signed/Unsigned 16-bit integer |
| `Int32` / `UInt32` / `Long` | 32-bit | Signed/Unsigned 32-bit integer |
| `Int64` / `UInt64` | 64-bit | Signed/Unsigned 64-bit integer |
| `Boolean` | 1-bit / 8-bit | Logical truth value (`True` / `False`) |
| `Pointer To T` | 32/64-bit | Direct memory address referencing type `T` |
| `Volatile Pointer To T` | 32/64-bit | MMIO address pointer exempt from compiler optimization |

#### Type Conversions & Casting

High-risk type conversions require explicit cast operators within `Unsafe` contexts:

* `CPtr(Type, Address)`: Casts an integer memory address or literal directly into a typed pointer.
* `CType(Type, Value)`: Performs bitwise or zero-extending type conversions between scalar types.

```vb
' Physical VGA Buffer Pointer Casting
Dim vga As Pointer To UInt16
vga = CPtr(Pointer To UInt16, &HB8000)

' Bitwise Packing Cast
Dim entry As UInt16
entry = CType(UInt16, 65) Or CType(UInt16, &H0A00)

```

---

### Structural Language Constructs

#### 1. Modules (`.bas`)

Modules are static, singleton compilation units containing global procedures, global variables, and module-level initialization stubs. Functions in modules map directly to C-style external linkage symbols.

```vb
Module System.PortIO

    Public Unsafe Sub OutB(ByVal port As UInt16, ByVal value As Byte)
        Asm
            "outb %al, %dx"
            : : "d"(port), "a"(value)
        End Asm
    End Sub

End Module

```

#### 2. Classes (`.cls`)

Classes define object-oriented state and behavior. Methods take an implicit `Me` context pointer. Classes can be stack-allocated, statically placed at physical addresses, or heap-allocated via optional runtime hooks (`__llbc_allocate_instance`).

```vb
Class Devices.SerialPort

    Private basePort As UInt16

    Public Sub Initialize(ByVal port As UInt16)
        Me.basePort = port
    End Sub

    Public Unsafe Sub WriteByte(ByVal data As Byte)
        System.PortIO.OutB Me.basePort, data
    End Sub

End Class

```

#### 3. Packed Structures (`Structure`)

Hardware descriptors (GDT, IDT, Page Tables, ACPI tables) require strict memory alignment without compiler field padding. Use the `<Packed>` or `<Align(N)>` attributes:

```vb
<Packed>
Public Structure IdtEntry
    Public BaseLow As UInt16
    Public Selector As UInt16
    Public Ist As Byte
    Public TypeAttributes As Byte
    Public BaseMid As UInt16
    Public BaseHigh As UInt32
    Public Reserved As UInt32
End Structure

```

---

### Low-Level & Bare-Metal Extensions

#### Inline Assembly (`Asm`)

LLB supports inline GCC/Clang assembly blocks with input, output, and clobber registers:

```vb
' Enable Hardware Interrupts
Asm "sti"

' Read Control Register CR0
Dim cr0Val As UInt64
Asm
    "mov %%cr0, %0"
    : "=r"(cr0Val)
End Asm

```

#### Volatile Memory Access

Prevent compiler optimization passes from stripping or reordering memory-mapped register writes (e.g., LAPIC, VGA Text Buffer):

```vb
Private buffer As Volatile Pointer To UInt16
buffer = CPtr(Volatile Pointer To UInt16, &HB8000)

' Guaranteed physical MMIO write
buffer(0) = &H0F41 

```

---

### Project Descriptor Specification (`.llbproj`)

LLB projects are configured via `.llbproj` manifest files, removing the need for external Makefiles or shell build scripts.

```ini
' Project Name: Low-Level Basic Kernel
' Manifest Descriptor: Kernel.llbproj

[Project]
Name = "kernel"
Type = "BareMetalExecutable" ' BareMetalExecutable, HostedExecutable, StaticLibrary
Version = "0.1.0"

[Target]
Arch = "x86_64-unknown-none-elf"

[Entry]
EntryPoint = "_start"

[Linker]
LinkerScript = "linker.ld"

[Sources]
Assembly = "src/arch/x86_64/boot.S"
Assembly = "src/arch/x86_64/IsrStubs.S"
Module = "src/arch/x86_64/Idt.bas"
Class = "src/drivers/Terminal.cls"
Module = "src/KernelMain.bas"

[CompilerOptions]
Optimize = "O2"
EmitDebugSymbols = True
AllowUnsafePointers = True

```

---

### Complete Kernel Implementation Reference

Below is a complete, multi-file bare-metal kernel written in Low-Level Basic, including boot assembly, IDT dispatcher, VGA driver, and main entry point.

#### File 1: `src/arch/x86_64/boot.S` (Multiboot2 Stub)

```assembly
.code32
.section .multiboot_header
.align 8
header_start:
    .long 0xe85250d6 /* Magic */
    .long 0          /* Architecture i386 */
    .long header_end - header_start
    .long -(0xe85250d6 + 0 + (header_end - header_start))
    .word 0, 0
    .long 8
header_end:

.section .bss
.align 4096
page_table_l4: .skip 4096
page_table_l3: .skip 4096
page_table_l2: .skip 4096
stack_bottom:  .skip 16384
stack_top:

.section .text
.global _start
_start:
    cli
    mov $stack_top, %esp
    mov %eax, %edi
    mov %ebx, %esi

    /* Identity Map First 2MB using 4-Level Paging */
    mov $page_table_l3, %eax
    or $0x3, %eax
    mov %eax, (page_table_l4)

    mov $page_table_l2, %eax
    or $0x3, %eax
    mov %eax, (page_table_l3)

    mov $0x000000, %eax
    or $0x83, %eax /* 2MB Huge Page */
    mov %eax, (page_table_l2)

    mov $page_table_l4, %eax
    mov %eax, %cr3

    /* Enable PAE & Long Mode */
    mov %cr4, %eax
    or $(1 << 5), %eax
    mov %eax, %cr4

    mov $0xC0000080, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr

    mov %cr0, %eax
    or $(1 << 31), %eax
    mov %eax, %cr0

    lgdt (gdt64_pointer)
    ljmp $0x08, $long_mode_entry

.code64
long_mode_entry:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov $stack_top, %rsp

    .extern KernelMain_KernelEntry
    call KernelMain_KernelEntry

1:  cli
    hlt
    jmp 1b

.section .rodata
gdt64:
    .quad 0
    .quad (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53)
    .quad (1 << 41) | (1 << 44) | (1 << 47)
gdt64_end:
gdt64_pointer:
    .word gdt64_end - gdt64 - 1
    .quad gdt64

```

#### File 2: `src/drivers/Terminal.cls` (VGA Terminal Class)

```vb
' Project Name: PRK-OS
' Filename: src/drivers/Terminal.cls
' Summary: Low-Level Basic Object-Oriented VGA Driver.

Class Drivers.Terminal

    Private Const VGA_WIDTH As UInt32 = 80
    Private Const VGA_HEIGHT As UInt32 = 25
    Private Const VGA_ADDRESS As UInt64 = &HB8000

    Private buffer As Volatile Pointer To UInt16
    Private cursorX As UInt32
    Private cursorY As UInt32
    Private attribute As Byte

    Public Unsafe Sub Initialize(ByVal fg As Byte, ByVal bg As Byte)
        Me.buffer = CPtr(Volatile Pointer To UInt16, VGA_ADDRESS)
        Me.attribute = fg Or (bg LShift 4)
        Me.cursorX = 0
        Me.cursorY = 0
        Me.Clear
    End Sub

    Public Unsafe Sub Clear()
        Dim blank As UInt16
        blank = CType(UInt16, 32) Or (CType(UInt16, Me.attribute) LShift 8)

        Dim i As UInt32
        For i = 0 To (VGA_WIDTH * VGA_HEIGHT) - 1
            Me.buffer(i) = blank
        Next i
    End Sub

    Public Unsafe Sub WriteChar(ByVal ch As Byte)
        If ch = 10 Then
            Me.cursorX = 0
            Me.cursorY = Me.cursorY + 1
        Else
            Dim offset As UInt32
            offset = (Me.cursorY * VGA_WIDTH) + Me.cursorX
            Me.buffer(offset) = CType(UInt16, ch) Or (CType(UInt16, Me.attribute) LShift 8)
            Me.cursorX = Me.cursorX + 1
        End If

        If Me.cursorX >= VGA_WIDTH Then
            Me.cursorX = 0
            Me.cursorY = Me.cursorY + 1
        End If
    End Sub

    Public Unsafe Sub WriteString(ByVal strPtr As Pointer To Byte)
        Dim i As UInt64
        i = 0
        Do While strPtr(i) <> 0
            Me.WriteChar strPtr(i)
            i = i + 1
        Loop
    End Sub

End Class

```

#### File 3: `src/KernelMain.bas` (Kernel Entry Point)

```vb
' Project Name: PRK-OS
' Filename: src/KernelMain.bas
' Summary: Low-Level Basic Kernel Entrypoint.

Module KernelMain

    Import Drivers.Terminal

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        Dim term As Terminal
        term.Initialize 10, 0 ' Light Green on Black

        term.WriteString CPtr(Pointer To Byte, "PRK-OS Kernel Initialized via Low-Level Basic (LLB)!")
        term.WriteChar 10

        Do
            Asm "hlt"
        Loop
    End Sub

End Module

```

---

### Toolchain Build Summary

To execute the self-hosting compiler pipeline on your project:

1. **Build `llbc-stage0` (C++ Driver):**
```bash
mkdir build && cd build
cmake ..
make -j4

```


2. **Compile LLB Kernel Project:**
```bash
./llbc-stage0 Kernel.llbproj

```


3. **Test Executable in QEMU:**
```bash
qemu-system-x86_64 -kernel kernel.elf -serial stdio

```
