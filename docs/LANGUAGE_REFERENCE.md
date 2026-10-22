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
19. [Compile-Time Safety & Diagnostics Guards](#19-compile-time-safety--diagnostics-guards)
20. [Delegates & Function Pointer Types](#20-delegates--function-pointer-types)
21. [Bitfield Declarations in Structures & Unions](#21-bitfield-declarations-in-structures--unions)
22. [Compile-Time Layout Intrinsics (`SizeOf` & `OffsetOf`)](#22-compile-time-layout-intrinsics-sizeof--offsetof)
23. [Bare-Metal Interrupt Handlers (`<Interrupt>`)](#23-bare-metal-interrupt-handlers-interrupt)
24. [Compile-Time Static Assertions (`#Assert`)](#24-compile-time-static-assertions-assert)

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
Namespaces group modules, procedures, classes, and interfaces into hierarchical scope trees. A namespace container can host multiple `Class`, `Module`, and `Interface` definitions within the same compilation unit:

```vb
' X.cls
Namespace X
    <Instancing(SingleUse)>
    Public Class Y
        Public Function GetValue() As Int32
            GetValue = 101
        End Function
    End Class

    <Instancing(SingleUse)>
    Public Class Z
        Public Function GetValue() As Int32
            GetValue = 202
        End Function
    End Class
End Namespace

' Y.cls
Namespace Y
    <Instancing(SingleUse)>
    Public Class Z
        Public Function GetValue() As Int32
            GetValue = 303
        End Function
    End Class
End Namespace
```

#### Nested Import Disambiguation
Targeted imports automatically isolate to their respective inner definitions without symbol bleeding:
```vb
Import X.Y  ' Imports only Class Y from Namespace X (X.Y)
Import X.Z  ' Imports only Class Z from Namespace X (X.Z)
Import Y.Z  ' Imports only Class Z from Namespace Y (Y.Z)

Dim a As Int32 = X.Y.GetValue() ' Evaluates to 101
Dim b As Int32 = X.Z.GetValue() ' Evaluates to 202
Dim c As Int32 = Y.Z.GetValue() ' Evaluates to 303
```

Top-level namespace declarations can also be imported in bulk:
```vb
Import X    ' Imports all inner classes and modules within Namespace X
```

### Imports (`Import`)
Imports resolve dependencies between compilation units and bring module routines and constants into scope:
```vb
Import Hardware.Bus In "drivers/Bus.bas"
Import Arch.Idt
Import System.Math
```

### Explicit Scope Binding (`Use`)
While `Import` is designed for static modules, `Use` provides fine-grained, explicit scope binding and aliasing for classes, procedures, and member functions across namespaces:

| Syntax Pattern | Semantics / What it does | Example Call |
| :--- | :--- | :--- |
| `Use Drivers.Terminal` | Brings class `Terminal` into current scope without typing `Drivers.` prefix | `Terminal.WriteChar "A"` |
| `Use Drivers.Terminal As term` | Imports class with a convenient short alias | `term.WriteChar "A"` |
| `Use Terminal In Drivers` | Equivalent to `from Drivers import Terminal` | `Terminal.WriteChar "A"` |
| `Use Terminal In Drivers As term` | Class import from parent namespace with alias | `term.WriteChar "A"` |
| `Use WriteChar In Drivers.Terminal` | Directly imports a specific procedure/method | `WriteChar "A"` |
| `Use WriteChar In Drivers.Terminal As TWrite` | Directly imports a method with a unique alias | `TWrite "A"` |

#### One-Liner Instantiation via `Use`
For instance-able classes (`<Instancing(MultiUse)>` or `<Instancing(SingleUse)>`), `Use` supports concise, one-line instantiation on the stack or heap:
```vb
' Instantiation with alias in a single statement
Use New Terminal In Drivers As term1
' Or:
Use Terminal In Drivers As New term1

term1.Initialize 10, 0
term1.WriteChar "A"
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

### The `Unsafe` Modifier
Procedures that execute raw pointer casting (`CPtr`), dereference raw pointers (`Pointer To T`), or execute inline assembly (`Asm`) must be decorated with `Unsafe`. Attempting low-level operations in a safe procedure triggers a compile-time rejection:
```vb
Public Unsafe Sub WritePort(ByVal port As UInt16, ByVal val As Byte)
    Asm
        "outb %al, %dx"
        : : "d"(port), "a"(val)
    End Asm
End Sub
```

### Mandatory Return Value Assignment
Functions returning a non-void value must assign a return value to the function name (e.g. `FunctionName = ...`) along all execution paths. Omitting the return assignment triggers a compile-time error:
```vb
Public Function CalculateArea(ByVal width As Int32, ByVal height As Int32) As Int32
    CalculateArea = width * height ' Mandatory assignment
End Function
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

### Mandatory `<Instancing(...)>` Class Attributes
Every `.cls` file must declare its instancing category at the top. If missing, the compiler will emit a **hard compile-time error**:
```vb
<Instancing(Category)>
Class ClassName
    ' ...
End Class
```

| Attribute | Category | Description | Freestanding / Zero-Heap? |
| :--- | :--- | :--- | :--- |
| `<Instancing(Global)>` | **Global Static Class** | Singleton state living in `.bss`. Methods can be called directly without `New` or local `Dim`. | ✅ 100% Zero-Heap |
| `<Instancing(SingleUse)>` | **Single-Instance Class** | Can only be instantiated **once** per scope/binary. Attempting multiple instances or `New` throws a compile-time error. | ✅ 100% Zero-Heap (Stack or Global BSS) |
| `<Instancing(MultiUse)>` | **Multi-Instance Class** | Can be instantiated multiple times via `Dim ... As New ...` or `Use ... As New ...`. | ✅ Stack (Value) or Heap (Dynamic) |

---

### Class Categories & Memory Models

#### 1. Global Static Class (`<Instancing(Global)>`)
- **Concept:** Acts as a structured singleton service with internal state stored in `.bss`.
- **Codegen:** The compiler allocates a zeroed static buffer `@__singleton_ClassName = internal global %struct.ClassName zeroinitializer` and automatically passes its address as `Me`.
- **Usage:**
  ```vb
  Use Drivers.Terminal As term

  term.Initialize 10, 0
  term.WriteChar 65
  ```

#### 2. Single-Instance Class (`<Instancing(SingleUse)>`)
- **Concept:** Represents unique hardware devices or core kernel drivers (e.g., primary VGA console, keyboard controller) that must never be duplicated.
- **Rules:** The compiler strictly enforces at compile-time that only one instance exists. Attempting a second instantiation or using `New` produces:
  `Error: Class 'Drivers.Terminal' is marked <Instancing(SingleUse)> and cannot be instantiated multiple times.`
- **Instantiation:**
  ```vb
  Dim term As Drivers.Terminal ' Single instance on stack or in .bss
  term.Initialize 10, 0
  ```

#### 3. Multi-Instance Class (`<Instancing(MultiUse)>`)
- **Concept:** Represents reusable objects, buffers, virtual terminals, or processes.
- **Stack / Value Instantiation (Zero Heap):**
  ```vb
  Dim com1 As Drivers.SerialPort ' Stack-allocated via alloca
  com1.Initialize &H3F8
  ```
- **Dynamic Heap Instantiation:**
  ```vb
  Dim comPort As Pointer To Drivers.SerialPort
  Set comPort = New Drivers.SerialPort
  ```

---

### Strict Compile-Time Uninitialized Error Enforcement
For both `<Instancing(SingleUse)>` and `<Instancing(MultiUse)>` classes that define a `Public Sub Initialize(...)` constructor:
1. The compiler tracks the lifecycle state of each instance variable (`UNINITIALIZED` -> `INITIALIZED`).
2. If code attempts to access a member variable or invoke any method before calling `.Initialize(...)`, the compiler immediately emits a **compile-time error**:
   ```text
   [llbc error] File 'KernelMain.bas', Line 42:
     Object 'term' of class 'Drivers.Terminal' is used before being initialized.
     Call 'term.Initialize(...)' first.
   ```
3. Calling `.Initialize(...)` transitions the state to `INITIALIZED`, permitting all subsequent operations.

---

### Destruction & Teardown Lifecycle (`Exit` / `Destroy`)
Classes may provide symmetric teardown via `Public Sub Destroy()` or `Public Sub Exit()`:
```vb
term.Destroy ' or term.Exit
```
- **Value / Stack instances:** Resets hardware state and clears buffers.
- **Dynamic Heap instances (`New`):** `Delete term` automatically invokes `Destroy()` before freeing memory through the registered allocator hook.

---

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

### Private Member Isolation & Visibility
Fields and members declared `Private` inside a `Class` or `Module` are strictly inaccessible from outside code. Accessing a `Private` field from an external scope produces a compile-time rejection:
```vb
Class Account
    Private m_balance As Int32
End Class

' In external procedure:
' acc.m_balance = 500  --> [Compile Error] Member 'm_balance' is Private to Class 'Account'.
```

### Static Method & Member Validation
Attempting to invoke an undeclared method or access an undeclared field on a class or structure instance (e.g. `obj.UnknownMethod()`) is verified at compile-time and rejected with a caret diagnostic.

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
Name    = "kernel"
Type    = "Kernel" ; Kernel, BareMetalExecutable, FlatBinary, Executable, SharedLibrary, StaticLibrary
Version = "0.1.0"

[Target]
Arch = "x86_64-unknown-none-elf"

[Entry]
EntryPoint = "_start"

[Linker]
LinkerScript = "linker.ld"

[Output]
OutDir  = "build"
OutFile = "kernel.elf"

[Sources]
Assembly = "src/boot.S"
Module   = "src/Idt.bas"
Module   = "src/Terminal.bas"
Module   = "src/KernelMain.bas"

[CompilerOptions]
Optimize           = "O2"
EmitDebugSymbols   = True
AllowUnsafePointers = True

[Script]
; Sequential post-build commands/scripts
Cmd = "post_build.sh"
```

### Supported Target Types

| Category | Value / Aliases | Runtime CRT | Default Ext | Description |
|:---|:---|:---:|:---:|:---|
| **Freestanding** | `Kernel`, `BareMetalExecutable`, `BareMetal`, `Freestanding` | Freestanding (`--nostdlib`) | `.elf` | Bare-metal kernel or firmware binary |
| **Flat Binary** | `FlatBinary`, `RawBinary`, `Binary` | Freestanding (`--nostdlib`) | `.bin` | Flat raw binary image generated via `llvm-objcopy -O binary` |
| **Hosted Executable** | `Executable`, `HostedExecutable` | Hosted standard CRT | `.elf` / none | Userspace hosted application |
| **Shared Library** | `SharedLibrary`, `DynamicLibrary` | Hosted (`-shared`) | `.so` | Dynamic shared library |
| **Static Library** | `StaticLibrary`, `Archive` | Static archive (`llvm-ar`) | `.a` | Static code archive |

### Multiple Manifest Builds & Invocation Modes

The `llbc` compiler driver supports compiling multiple project manifests sequentially:
```bash
llbc 1.llbproj 2.llbproj 3.llbproj
```
Each project is compiled with isolated module indices and symbol catalogs. Input files, directories, and extensions are strictly validated before code generation begins.



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

---

## 19. Compile-Time Safety & Diagnostics Guards

Low-Level Basic pairs ahead-of-time LLVM code generation with comprehensive static verification:

1. **Undeclared Symbol & Type Verification:**
   - Any reference to an undeclared type in `Dim x As T`, field declarations, or procedure parameters produces an immediate compile error.
   - Any call to an undeclared function or subroutine is halted at compile time.
2. **Undeclared Method Rejection:**
   - Invoking methods or members not present on a target class or structure instance (`obj.NoSuchMethod()`) is statically rejected.
3. **Private Member Access Fencing:**
   - Members declared `Private` inside a `Class` or `Module` cannot be accessed from outside code.
4. **Mandatory Function Return Value:**
   - Non-void `Function` definitions must assign to their function name (`Func = value`) along all execution paths before exiting.
5. **Strict `Unsafe` Enforcement:**
   - Any procedure using `CPtr`, raw pointer dereferencing (`ptr(i)`), or inline assembly (`Asm`) must be declared with `Unsafe`. Safe procedures attempting unsafe operations are rejected at compile time.
6. **Class Instancing Invariants:**
   - `<Instancing(SingleUse)>` classes can only be instantiated once per scope.
   - Objects must be initialized via `.Initialize(...)` before members or methods can be accessed.
7. **Arithmetic & Boundary Safety:**
   - Compile-time division by zero (`x / 0`) and out-of-range bit shifts (`x LShift 64`) are caught during frontend evaluation.
   - Fixed-size array indexing with constant indices is statically bounds-checked.

---

## 20. Delegates & Function Pointer Types

Delegates declare strongly-typed signatures for function pointers, callbacks, and interrupt handlers:

```vb
' Declare a delegate signature for interrupt handlers
Public Delegate Sub InterruptHandler(ByRef frame As InterruptFrame)

' Declare a callback delegate
Public Delegate Function Comparator(ByVal a As Int32, ByVal b As Int32) As Int32

' Use delegate type in signatures
Public Sub RegisterHandler(ByVal intNum As Byte, ByVal handler As InterruptHandler)
    ' handler is passed as a typed function pointer
End Sub
```

Delegates compile directly to LLVM function pointer types (`ptr`) with zero runtime abstraction overhead.

---

## 21. Bitfield Declarations in Structures & Unions

Structures and Unions can specify explicit bitfield widths using classic BASIC fixed-length notation (`* Bits`):

```vb
<Packed>
Structure PageTableEntry
    Public Present         As Byte * 1
    Public Writable        As Byte * 1
    Public UserAccessible  As Byte * 1
    Public WriteThrough    As Byte * 1
    Public CacheDisabled   As Byte * 1
    Public Accessed        As Byte * 1
    Public Dirty           As Byte * 1
    Public HugePage        As Byte * 1
    Public Reserved        As Byte * 4
    Public FrameAddress    As UInt64 * 52
End Structure
```

Bitfield width specifications allow zero-overhead, direct hardware register mapping for MMIO peripherals, descriptor tables, and hardware page tables without manual bit-shifting or mask boilerplate.

---

## 22. Compile-Time Layout Intrinsics (`SizeOf` & `OffsetOf`)

LLB provides zero-overhead compile-time layout intrinsics evaluated directly against the target architecture's DataLayout:

- **`SizeOf(T)`**: Evaluates to the exact size of type or structure `T` in bytes as a compile-time constant `UInt64`.
- **`OffsetOf(T, Field)`**: Evaluates to the byte offset of `Field` within structure `T` as a compile-time constant `UInt64`.

```vb
' Compile-time static constants
Dim idtSize As UInt64 = SizeOf(IdtEntry)
Dim baseHighOffset As UInt64 = OffsetOf(IdtEntry, BaseHigh)

' Inlined directly without runtime function calls or overhead
```

---

## 23. Bare-Metal Interrupt Handlers (`<Interrupt>`)

For bare-metal microkernels and freestanding OS development, procedures handling CPU exceptions and hardware IRQs can be decorated with the `<Interrupt>` attribute:

```vb
<Interrupt>
Public Unsafe Sub KeyboardInterruptHandler(ByVal frame As Pointer To InterruptStackFrame)
    ' Handler code
    Drivers.Keyboard.HandleScancode
End Sub
```

### Compiler Invariants:
1. **Calling Convention:** Compiles to the target architecture's native interrupt calling convention (`x86_intr` on x86_64).
2. **Register Preservation:** Automatically pushes and restores all general-purpose registers (including scratch registers) across the call.
3. **Hardware Return:** Automatically terminates with the native interrupt return instruction (`iretq` on x86_64) instead of standard procedure return (`ret`).

---

## 24. Compile-Time Static Assertions (`#Assert`)

Compile-time static assertions allow developers to enforce architectural invariants, data structure layouts, and preprocessor configurations directly during compilation:

```vb
' Enforce hardware data structure bounds
#Assert SizeOf(IdtEntry) = 16, "IdtEntry must be exactly 16 bytes on x86_64"
#Assert SizeOf(GdtDescriptor) = 8, "GDT segment descriptor size mismatch"
#Assert OffsetOf(IdtEntry, BaseHigh) = 8, "BaseHigh must be at offset 8"

' Enforce preprocessor and build environment constraints
#Assert TARGET_ENV = 1, "TARGET_ENV constant validation"
#Assert ARCH_BITS = 64, "Only 64-bit builds supported"
```

### Compiler Invariants:
1. **Zero Runtime Overhead:** Evaluated purely at compile time by the AST emitter against constant folded expressions and the LLVM `DataLayout`. Generates zero instructions or runtime metadata.
2. **Deterministic Diagnostic Error:** If the condition evaluates to `0` (false), compilation halts immediately with a source-location error diagnostic and the provided error message.
3. **Scope Availability:** Valid at both the module/namespace level and within procedure statement blocks.



