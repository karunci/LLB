# Low-Level Basic (LLB) Language Reference Manual

> **Low-Level Basic (LLB)** is an Ahead-Of-Time (AOT) compiled systems programming language designed for bare-metal kernels, embedded devices, drivers, and high-performance userland applications. It pairs the straightforward readability of Visual Basic 6 with the bare-metal performance, memory safety, and hardware control of C, C++, and Rust.

---

## Table of Contents
1. [Lexical Structure & Conventions](#1-lexical-structure--conventions)
2. [Compilation Units & Declarations](#2-compilation-units--declarations)
3. [Type System & Data Representation](#3-type-system--data-representation)
4. [Variables, Constants & Scope](#4-variables-constants--scope)
5. [Procedures, Parameters & Modifiers](#5-procedures-parameters--modifiers)
6. [Operators & Expressions](#6-operators--expressions)
7. [Control Flow & Loops](#7-control-flow--loops)
8. [Object-Oriented Programming & Interfaces](#8-object-oriented-programming--interfaces)
9. [Low-Level Memory & Pointers](#9-low-level-memory--pointers)
10. [Hardware Interfacing & Inline Assembly](#10-hardware-interfacing--inline-assembly)
11. [Error Handling & Sum Types](#11-error-handling--sum-types)
12. [Generics & Parameterized Templates](#12-generics--parameterized-templates)
13. [File I/O & Console Subsystem](#13-file-io--console-subsystem)
14. [Foreign Function Interface (FFI)](#14-foreign-function-interface-ffi)
15. [Standard Intrinsics Library](#15-standard-intrinsics-library)
16. [Project Manifest Specification (`.llbproj`)](#16-project-manifest-specification-llbproj)
17. [Core Architectural Design & Comparison with Modern Languages](#17-core-architectural-design--comparison-with-modern-languages)
18. [Freestanding Systems & Microkernel Runtime Model](#18-freestanding-systems--microkernel-runtime-model)

---

## 1. Lexical Structure & Conventions

### Case Insensitivity
All keywords, procedure names, module identifiers, and variable names are **case-insensitive**.
```vb
DIM x AS Int32 = 10
dim y as int32 = 20
Dim Z As Int32 = X + Y
```

### Comments
- **Single-Line Comments:** Indicated by an apostrophe `'`:
  ```vb
  ' This is a standard LLB comment
  Dim count As Int32 = 0 ' Inline comment
  ```

### Line Continuation
Statements can span multiple lines using an underscore `_` preceded by whitespace:
```vb
Dim total As Int32 = 100 + _
                     200 + _
                     300
```

### Statement Separator
Multiple statements on a single line are separated by a colon `:`:
```vb
Dim a As Int32: a = 10: Dim b As Int32: b = 20
```

---

## 2. Compilation Units & Declarations

### Modules (`.bas`)
Modules are static, singleton compilation units. Procedures and variables declared `Public` in a module have global or namespace-level linkage:
```vb
Module System.Math
    Public Function Square(ByVal x As Int32) As Int32
        Square = x * x
    End Function
End Module
```

### Classes (`.cls`)
Classes encapsulate instance state and behavior. Methods receive an implicit `Me` reference:
```vb
Class BufferWriter
    Private cursor As Int32

    Public Sub Initialize()
        Me.cursor = 0
    End Sub

    Public Sub Advance(ByVal count As Int32)
        Me.cursor = Me.cursor + count
    End Sub
End Class
```

### Namespaces (`Namespace ... End Namespace`)
Namespaces group modules, procedures, and classes into hierarchical scope trees:
```vb
Namespace Hardware.Bus
    Public Function ReadRegister(ByVal regId As UInt16) As Byte
        ' ...
    End Function
End Namespace

' Call-site usage:
Dim val As Byte = Hardware.Bus.ReadRegister(&H60)
```

### Imports (`Import`)
Imports resolve dependencies between compilation units:
```vb
Import Hardware.Bus In "drivers/Bus.bas"
Import System.Math
```

---

## 3. Type System & Data Representation

### Primitive Scalar Types
| Type | Bit Width | Description |
|---|---|---|
| `Byte` / `UByte` | 8-bit | Unsigned 8-bit integer (`0` to `255`) |
| `Int16` / `Short` | 16-bit | Signed 16-bit integer (`-32,768` to `32,767`) |
| `UInt16` / `UShort` | 16-bit | Unsigned 16-bit integer (`0` to `65,535`) |
| `Int32` / `Integer` / `Long` | 32-bit | Signed 32-bit integer |
| `UInt32` / `ULong` | 32-bit | Unsigned 32-bit integer |
| `Int64` | 64-bit | Signed 64-bit integer |
| `UInt64` | 64-bit | Unsigned 64-bit integer |
| `Currency` / `Decimal` | 64-bit | Fixed-point decimal unit (scaled by 10,000) |
| `Single` | 32-bit | IEEE-754 single-precision float |
| `Double` | 64-bit | IEEE-754 double-precision float |
| `Boolean` | 1-bit | Logical truth value (`True` / `False`) |
| `String` | Pointer | Pointer to null-terminated UTF-8 byte stream |

### User-Defined Structures (`Structure` / `Type`)
Structures define custom layout data types. Members are accessed via dot notation:
```vb
Public Structure Vector3D
    Public X As Double
    Public Y As Double
    Public Z As Double
End Structure
```

### Union Types (`Union ... End Union`)
Unions provide overlapping memory allocations at offset 0, perfect for hardware registers and type punning:
```vb
Public Union Register32
    Public Dword As UInt32
    Public Word As UInt16
    Public LowByte As Byte
End Union
```

### Enumerations (`Enum ... End Enum`)
Named integer constant groups:
```vb
Public Enum LogLevel
    Debug = 0
    Info = 10
    Warning = 20
    FatalError = 30
End Enum
```

### Type Aliases (`TypeAlias`)
Declare clear aliases for complex pointer types or domain synonyms:
```vb
TypeAlias PageDirectoryPtr = Pointer To UInt64
TypeAlias Handle = Int32
```

---

## 4. Variables, Constants & Scope

### Local & Module Variables
```vb
' Local variable with initial assignment
Dim bufferSize As Int32 = 4096

' Module-level global initialized variable
Public g_kernelTickCounter As UInt64 = 0
```

### Constants (`Const` & `#Const`)
```vb
' Runtime compiled constant
Public Const MAX_RETRIES As Int32 = 5

' Preprocessor compile-time constant
#Const TARGET_BITS = 64
```

### Conditional Compilation (`#If ... #ElseIf ... #Else ... #End If`)
```vb
#If TARGET_BITS = 64 Then
    TypeAlias SysInt = Int64
#Else
    TypeAlias SysInt = Int32
#End If
```

---

## 5. Procedures, Parameters & Modifiers

### Subroutines & Functions
- `Sub`: Does not return a value.
- `Function`: Returns a value by assigning to the function name or returning early.
```vb
Public Function Add(ByVal a As Int32, ByVal b As Int32) As Int32
    Add = a + b
End Function

Public Sub LogMessage(ByVal msg As String)
    PrintLine "[LOG] " & msg
End Sub
```

### Parameter Passing Modes
- `ByVal`: Passes a copy of the value (default for primitives).
- `ByRef`: Passes a pointer to the caller's variable, allowing modifications.
- `Optional`: Specifies a default value if argument is omitted.
- `ParamArray`: Packs variadic arguments into an array.
```vb
Public Sub ModifyValues(ByVal id As Int32, ByRef counter As Int32, Optional ByVal stepVal As Int32 = 1)
    counter = counter + stepVal
End Sub

Public Function SumAll(ParamArray nums() As Int32) As Int32
    Dim total As Int32 = 0
    Dim i As Int32
    For i = 0 To UBound(nums)
        total = total + nums(i)
    Next i
    SumAll = total
End Function
```

### Call-Site Named Arguments
Pass arguments out of order by name using `:=`:
```vb
ModifyValues stepVal := 5, counter := myCounter, id := 1
```

### Procedure Attributes
Decorate functions with compiler optimization directives:
```vb
<Inline>
Public Function FastMul(ByVal a As Int32, ByVal b As Int32) As Int32
    FastMul = a * b
End Function

<NoReturn>
Public Sub KernelPanic(ByVal reason As String)
    PrintLine "PANIC: " & reason
    Asm "cli; hlt"
End Sub

<Export>
Public Sub NativePluginEntry()
    ' Exported symbol in shared libraries
End Sub
```

---

## 6. Operators & Expressions

### Arithmetic & Logic
- **Arithmetic:** `+`, `-`, `*`, `/`, `\ ` (integer divide), `Mod`
- **Bitwise:** `And`, `Or`, `Xor`, `Not`, `LShift`, `RShift`
- **Comparison:** `=`, `<>`, `<`, `<=`, `>`, `>=`
- **String Concatenation:** `&` (unconditional string conversion), `+`

### Unsigned Operations
Explicit unsigned division and remainder:
```vb
Dim quotient As UInt32 = UDiv(uValA, uValB)
Dim remainder As UInt32 = URem(uValA, uValB)
```

### Pattern Matching (`Like`)
Glob matching with `*` (any sequence) and `?` (single character):
```vb
If "kernel.elf" Like "*.elf" Then
    PrintLine "Valid ELF file"
End If
```

---

## 7. Control Flow & Loops

### Conditional Branching (`If ... Then ... ElseIf ... Else`)
```vb
If priority >= 30 Then
    HandleUrgent
ElseIf priority >= 10 Then
    HandleStandard
Else
    HandleIdle
End If
```

### Multi-Branch Selection (`Select Case`)
```vb
Select Case status
    Case 200, 201
        PrintLine "OK"
    Case 400 To 499
        PrintLine "Client error"
    Case Else
        PrintLine "Other code"
End Select
```

### Algebraic Pattern Matching (`Match ... Case ... End Match`)
```vb
Match result
    Case Ok(val)
        PrintLine "Computed: " & val
    Case Err(code)
        PrintLine "Error code: " & code
    Case Else
        PrintLine "Unknown"
End Match
```

### Loops
```vb
' For-Next Loop with Step
For i = 0 To 100 Step 10
    PrintLine "Index: " & i
Next i

' Do While / Until Loop
Do While bufferHasData
    ProcessByte
Loop

' While-Wend Loop
While count > 0
    count = count - 1
Wend

' For Each Collection Iterator
For Each item In collection
    ProcessItem item
Next item
```

---

## 8. Object-Oriented Programming & Interfaces

### Interfaces & Implementation
```vb
Interface IDriver
    Sub Initialize()
    Function ReadStatus() As Int32
End Interface

Class SerialDriver
    Implements IDriver

    Public Sub Initialize()
        ' Initialize hardware
    End Sub

    Public Function ReadStatus() As Int32
        ReadStatus = 1
    End Function
End Class
```

### Deterministic Scoped Cleanup (`Using ... End Using`)
Ensures resources are safely disposed upon leaving the block:
```vb
Using res As ResourceHandle
    res.WriteData 1234
    ' res.Dispose() is automatically invoked here
End Using
```

---

## 9. Low-Level Memory & Pointers

### Pointer Declarations & Dereferencing
```vb
' Pointer to typed data
Dim ptr As Pointer To Int32
ptr = AddressOf myVariable
ptr(0) = 500 ' Dereference offset 0

' Memory-Mapped I/O volatile pointer
Dim vga As Volatile Pointer To UInt16
vga = CPtr(Volatile Pointer To UInt16, &HB8000)
vga(0) = &H0F41 ' Write 'A' White on Black
```

### Dynamic Array Resizing & Memory Zeroing
```vb
Dim dynBuffer As Pointer To Int32
ReDim dynBuffer(256)
dynBuffer(0) = 42

ReDim Preserve dynBuffer(512) ' Preserves existing elements

Erase dynBuffer ' Frees memory and sets pointer to Nothing
```

---

## 10. Hardware Interfacing & Inline Assembly

### Inline Assembly (`Asm`)
Execute raw CPU instructions with GCC-style constraints:
```vb
' Single-line assembly
Asm "sti"

' Multi-line assembly with operands
Dim cr3Value As UInt64
Asm
    "mov %%cr3, %0"
    : "=r"(cr3Value)
End Asm
```

---

## 11. Error Handling & Sum Types

### VB6 `Err` Object & Structured `Try ... Catch ... Finally`
```vb
Try
    If port = 0 Then
        Err.Raise 501, "PortManager", "Null port assignment"
    End If
Catch
    PrintLine "Trapped error #" & Err.Number & " from " & Err.Source & ": " & Err.Description
    Err.Clear
Finally
    PrintLine "Cleanup completed"
End Try
```

### `Result(T, E)` Sum Types
```vb
Public Function Divide(ByVal a As Int32, ByVal b As Int32) As Result
    If b = 0 Then
        Divide = Err(101)
    Else
        Divide = Ok(a / b)
    End If
End Function
```

---

## 12. Generics & Parameterized Templates

Zero-cost monomorphized generic templates:
```vb
Public Structure Box(Of T)
    Public Value As T
End Structure

Public Function Min(Of T)(ByVal a As T, ByVal b As T) As T
    If a < b Then
        Min = a
    Else
        Min = b
    End If
End Function

' Usage:
Dim intBox As Box(Of Int32)
intBox.Value = 100

Dim m As Int32 = Min(Of Int32)(50, 20)
```

---

## 13. File I/O & Console Subsystem

```vb
' Writing to a text file
Open "log.txt" For Output As #1
Print #1, "Log Entry: " & 2026
Close #1

' Reading line-by-line
Dim lineText As String
Open "log.txt" For Binary As #1
Do While Not EOF(1)
    Line Input #1, lineText
    PrintLine lineText
Loop
Close #1

' Reading from Standard Input (stdin channel #0)
Dim userInput As String
Print "Enter your name: "
Line Input #0, userInput
PrintLine "Hello, " & userInput
```

---

## 14. Foreign Function Interface (FFI)

```vb
' Bind to standard libc functions
Public Declare Function printf Lib "c" (ByVal fmt As Pointer To Byte, ByVal arg As Int32) As Int32

' Bind with symbol alias
Public Declare Function sys_puts Lib "c" Alias "puts" (ByVal str As Pointer To Byte) As Int32
```

---

## 15. Standard Intrinsics Library

| Intrinsics | Description |
|---|---|
| `Len(s)` | Returns the string character count. |
| `Mid(s, start, [len])` | Extracts substring starting at 1-based index. |
| `Left(s, n)`, `Right(s, n)` | Extracts leftmost or rightmost `n` characters. |
| `InStr([start], s, find)` | Locates first occurrence of substring. |
| `Trim(s)` | Strips leading and trailing whitespace. |
| `Asc(s)`, `Chr(code)` | Converts character to ASCII code and vice-versa. |
| `StrComp(s1, s2)` | Three-way string comparison (`-1`, `0`, `1`). |
| `Val(s)` | Parses numeric value from string. |
| `CStr(n)`, `CInt(n)`, `CLng(n)` | Explicit type conversions. |
| `CopyMemory(dst, src, bytes)` | Memory block copy (`llvm.memcpy`). |
| `ZeroMemory(dst, bytes)` | Zeroes memory block (`llvm.memset`). |
| `FillMemory(dst, bytes, val)` | Fills memory block with byte value. |
| `UBound(arr, [dim])` | Returns upper dimension bound. |
| `LBound(arr, [dim])` | Returns lower dimension bound (`0`). |

---

## 16. Project Manifest Specification (`.llbproj`)

LLB projects are configured using `.llbproj` descriptors:

```ini
[Project]
Name = "kernel"
Type = "BareMetalExecutable" ' BareMetalExecutable, HostedExecutable, SharedLibrary, StaticLibrary, RawBinary
Version = "0.1.0"

[Target]
Arch = "x86_64-unknown-none-elf"

[Entry]
EntryPoint = "_start"

[Linker]
LinkerScript = "linker.ld"

[Sources]
Assembly = "src/boot.S"
Module = "src/Idt.bas"
Class = "src/Terminal.cls"
Module = "src/KernelMain.bas"

[CompilerOptions]
Optimize = "O2"
EmitDebugSymbols = True
AllowUnsafePointers = True
```

---

## 17. Core Architectural Design & Comparison with Modern Languages

Low-Level Basic occupies a unique position in modern systems programming. While many modern languages have embraced high-complexity syntax, LLB proves that systems software can maintain maximum performance and safety without sacrificing syntactic elegance.

### Architectural Feature Comparison

| Architectural Capability | Low-Level Basic (LLB) | C / C++ | Rust | Zig | Classic Visual Basic 6 |
|---|---|---|---|---|---|
| **Compilation Model** | Native AOT (LLVM IR + LLD) | Native AOT | Native AOT (LLVM) | Native AOT (LLVM/Self) | P-Code / MSVC Bytecode |
| **Syntax Philosophy** | Clean, readable VB6 keywords | Cryptic braces & pointers | Heavy symbols (`<'_>`, `&mut`) | Minimalist C-adjacent | Approachable English keywords |
| **Bare-Metal / Freestanding** | **100% Freestanding** (`--nostdlib`) | Supported (`-nostdlib`) | Supported (`#![no_std]`) | Supported (`freestanding`) | ❌ Dependent on MSVBVM60.DLL |
| **Raw Pointer Arithmetic** | ✅ Byte-level GEP (`ptr + N`) | ✅ Unchecked | ⚠️ Requires `unsafe` block | ✅ Supported | ❌ Forbidden (Only `ByVal` FFI) |
| **Hardware MMIO Protection** | `Volatile Pointer To T` | `volatile T*` | `core::ptr::read_volatile` | `volatile` pointers | ❌ None |
| **Memory Safety Model** | Safe defaults + `Unsafe` fences | ❌ Unchecked by default | Strict Affine Borrow Checker | Manual / Optional safe math | Safe bytecode / COM GC |
| **Bounds & Null Guards** | Compiler-injected runtime checks | ❌ None (Undefined Behavior) | Dynamic Panic / Compile-time | Runtime safety assertions | ❌ Dynamic runtime error |
| **Sum Types & Pattern Matching** | `Result(T, E)` + `Match ... Case` | ⚠️ C++17 `std::variant` | `enum Result` + `match` | Tagged unions + `switch` | ❌ None |
| **Deterministic RAII Cleanup** | `Using ... End Using` (`.Dispose`) | Destructors (`~Class`) | RAII (`Drop` trait) | `defer` statement | COM Reference Counting |
| **Generics / Templates** | On-Demand Monomorphization | Complex Templates / SFINAE | Monomorphized Traits | Comptime code generation | ❌ None |
| **Embedded In-Process Linking** | Embedded LLD (`lldMain`) | External `ld`/`link.exe` | External Linkers | Internal Mach-O/ELF Linker | External MSVC Linker |

### Design Principles: The LLB Triangle

1. **Zero Runtime Taxation:** No garbage collector, no hidden runtime thread pools, no mandatory dynamic heap allocation. LLB code compiles directly to native instructions with zero-overhead abstractions.
2. **Explicit Memory Intent:** Safe operations (array lookups, object method calls, scalar arithmetic) are fully checked. Operations involving raw memory casting (`CPtr`), direct address dereferencing, or inline assembly require explicit `Unsafe` qualification.
3. **Approachable Syntactic Clarity:** By retaining `Module`, `Class`, `Sub`, `Function`, `Select Case`, `With`, and `Print`, code bases remain effortlessly readable without line noise, bracket matching, or convoluted macro definitions.

---

## 18. Freestanding Systems & Microkernel Runtime Model

Unlike hosted application runtimes, LLB is engineered from the ground up for freestanding operating system kernels, bootloaders, and firmware.

### Minimal Runtime Footprint
In freestanding mode (`--nostdlib` or `[Project] Type = "BareMetalExecutable"`):
- All implicit host C library bindings are stripped.
- The standard startup file (`_start`) links directly to the target machine without host CRT objects (`crt1.o`, `crti.o`).
- String operations use an in-tree, zero-dependency Bump Allocator (`__llbc_bump_malloc`) with no dependency on host `malloc`.
- Dynamic structures like `HashMap` and `ArrayList` provide zero-heap stack buffer options suitable for initial paging tables, interrupt handlers, and early boot stages.

