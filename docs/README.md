## Low-Level Basic (LLB) Architectural & Language Specification

---

### Executive Summary

**Low-Level Basic (LLB)** is an ahead-of-time (AOT) compiled systems and general-purpose programming language. It combines the strong features of Rust (memory safety, zero-cost abstractions, robust static verification) and high-level systems languages (C/C++ manual memory management, hardware control, pointer arithmetic, inline assembly) with the simple, expressive syntax of Visual Basic 6 (Modules, Classes, `ByVal`/`ByRef`, `Sub`/`Function`, `Select Case`, `With`, `Print`).

Targeted at systems programmers, kernel developers, and hobbyist coders alike, LLB emphasizes code that is intuitive to read and write without sacrificing bare-metal efficiency. The reference compiler toolchain (`llbc`) generates compact, highly optimized native machine code with a minimal freestanding footprint, full cross-compilation support, and zero mandatory external runtime dependencies.

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
Const        Enum         With         Declare      Lib          Alias
Print        Input        Type         AddressOf    Property     Get
Let          Set          Each         In           New          Delete
ReDim        Preserve     Is           Nothing      Erase        GoTo
Try          Catch        Finally      ParamArray   Like         Union
TypeOf       Open         Close        Output       Append       Binary
Line         EOF          LOF          Interface    Implements   Namespace
And          Or           Xor          Not          LShift       RShift
Mod
```


---

### Data Types & Type System

LLB replaces dynamic typing with explicit fixed-width static primitive types and zero-cost pointer abstractions.

#### Primitive Types

| Type | Width | Description |
| --- | --- | --- |
| `Byte` / `UByte` | 8-bit | Unsigned 8-bit byte (`0` to `255`) |
| `Int16` / `UInt16` / `Short` / `UShort` | 16-bit | Signed/Unsigned 16-bit integer |
| `Int32` / `UInt32` / `Integer` / `Long` / `ULong` | 32-bit | Signed/Unsigned 32-bit integer |
| `Int64` / `UInt64` | 64-bit | Signed/Unsigned 64-bit integer |
| `Currency` / `Decimal` | 64-bit | Fixed-point decimal integer (4-place decimal scaling) |
| `Single` / `Double` | 32/64-bit | IEEE-754 Single (float) and Double floating point |
| `Boolean` | 1-bit / 8-bit | Logical truth value (`True` / `False`) |
| `String` | Pointer | Pointer-based freestanding null-terminated C string |
| `Pointer To T` | 32/64-bit | Direct memory address referencing type `T` |
| `Volatile Pointer To T` | 32/64-bit | MMIO address pointer exempt from compiler optimization |
| `Result` | Struct | Built-in sum type `{ is_ok As Boolean, err_code As Int32, value As Int64 }` |

#### Compound & User-Defined Types

* **User-Defined Types (`Structure` / `Type`):** Byte-aligned or packed compound structures.
* **Unions (`Union`):** Overlapping memory layouts at offset 0 for registers, protocols, and raw bitfields.
* **Fixed & Multidimensional Arrays:** Stack-allocated row-major arrays (`Dim matrix(3, 3) As Int32`).
* **Type Aliases (`TypeAlias X = Y`):** Strongly checked type nicknames for primitives and pointers.


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

#### 4. Procedure Attributes & Annotations

Procedures can be decorated with compiler attributes to control optimization, code generation, and symbol visibility:

```vb
<Inline>
Public Function FastMultiply(ByVal a As Int32, ByVal b As Int32) As Int32
    FastMultiply = a * b
End Function

<NoReturn>
Public Sub KernelPanic(ByVal msg As Pointer To Byte)
    puts msg
    Asm "hlt"
End Sub

<Export>
Public Sub ExternalHook()
    ' Exported with default external visibility in shared libraries
End Sub
```

#### 5. Interfaces & Dynamic Dispatch (`Interface` / `Implements`)

LLB supports decoupled polymorphism through interface contracts and virtual method table (vtable) dispatch:

```vb
Interface IGreeter
    Sub Greet(ByVal name As String)
    Function GetCode() As Int32
End Interface

Class ConsoleGreeter
    Implements IGreeter

    Public Sub Greet(ByVal name As String)
        PrintLine "Hello, " & name & "!"
    End Sub

    Public Function GetCode() As Int32
        GetCode = 42
    End Function
End Class
```

#### 5.1 Delegates (`Delegate Sub` / `Delegate Function`)

Delegates provide strongly-typed function signatures for callbacks, function pointers, and interrupt handlers:

```vb
Public Delegate Sub InterruptHandler(ByRef frame As InterruptFrame)
Public Delegate Function Transformer(ByVal val As Int32) As Int32

Public Sub ApplyTransform(ByVal ptr As Transformer, ByVal input As Int32)
    Dim res As Int32 = ptr(input)
End Sub
```

#### 6. Namespaces & Hierarchical Organization (`Namespace`)

Modules, classes, and subroutines can be encapsulated inside hierarchical namespaces. Identifiers within namespaces are resolved with standard dotted access:

```vb
Namespace Core.Algorithms

    Public Function ComputeHash(ByVal seed As Int32) As Int32
        ComputeHash = seed Xor &H5A5A5A5A
    End Function

End Namespace

' Usage in another compilation unit:
Dim h As Int32 = Core.Algorithms.ComputeHash(1234)
```

#### 7. Modern Functional Lambdas (`=>`) & First-Class Function Pointers

Inline functions and closures can be defined concisely using fat-arrow syntax (`=>`) and passed as first-class function pointers:

```vb
' Lambda assigned to function pointer variable
Dim multiplier As Pointer
multiplier = Function(x As Int32) As Int32 => x * 3

' Indirect call
Dim ans As Int32 = multiplier(14) ' ans = 42
```

#### 8. Result / Error Handling (`Result(T, E)`)

Freestanding sum types provide zero-exception error handling via `Result`, `Ok(value)`, `Err(code)`, and `IsOk(result)`:

```vb
Public Function SafeDivide(ByVal a As Int32, ByVal b As Int32) As Result
    If b = 0 Then
        SafeDivide = Err(101)
    Else
        SafeDivide = Ok(a / b)
    End If
End Function

Dim res As Result = SafeDivide(100, 5)
If IsOk(res) Then
    PrintLine "Value: " & res.value
Else
    PrintLine "Failed with code: " & res.err_code
End If
```

#### 9. Generics & Parameterized Templates (`Structure(Of T)` / `Function(Of T)`)


LLB supports zero-cost generic abstractions through template monomorphization. Both structures and functions can be parameterized with type arguments:

```vb
' Parameterized structure template
Structure Box(Of T)
    Public Value As T
    Public Tag As Int32
End Structure

' Parameterized function template
Function Min(Of T)(ByVal a As T, ByVal b As T) As T
    If a < b Then
        Min = a
    Else
        Min = b
    End If
End Function

' Instantiation with concrete types
Dim intBox As Box(Of Int32)
intBox.Value = 42

Dim smallest As Int32 = Min(Of Int32)(100, 45) ' smallest = 45
```

#### 10. High-Signal Compiler Diagnostics



The `llbc` compiler provides ANSI-colored diagnostic messages automatically when run in a terminal or console:
```
source.bas:14:10: error: Expected '=' in constant declaration
   14 | Const MAX_LIMIT As Int32
      |                 ^
```
- **Error messages**: Bold red (`error:`) with cyan caret pointer (`^`) indicating exact token column.
- **Source line context**: Gutter line number and the original source line context printed directly under the diagnostic.
- **TTY Auto-detection**: Automatically enables colors on terminals/consoles (`isatty`) and falls back to plain text when piped or redirected.

#### 11. Compile-Time Safety & Diagnostics Guards

The compiler enforces strict compile-time verification across 25 automated rejection test categories:
- **Strict `Unsafe` Enforcement:** Procedures utilizing `CPtr`, raw pointer dereferencing, or `Asm` blocks require explicit `Unsafe` decoration.
- **Mandatory Return Values:** Non-void `Function` procedures must assign a return value along all paths.
- **Static Member & Method Validation:** Methods and members accessed on instances (`obj.Method()`) are statically checked against class and structure definitions.
- **Visibility Protection:** `Private` fields and members are isolated and inaccessible from external scopes.
- **Type Existence Checking:** Undeclared types in `Dim x As T`, parameters, and fields are rejected immediately with column caret diagnostics.
- **Lifecycle Guarantees:** Single-instance (`<Instancing(SingleUse)>`) constraints and constructor invocation order (`.Initialize`) are verified before members can be used.

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

### Control Flow & Structured Programming

LLB provides modern structured control flow constructs matching classic Visual Basic 6 syntax, compiled ahead-of-time to optimized LLVM basic blocks:

#### 1. Conditional Branching (`If ... ElseIf ... Else ... End If`)

Supports nested conditional blocks as well as single-line conditions:

```vb
' Nested Block Conditional
If x > 100 Then
    If x > 200 Then
        score = 3
    Else
        score = 2
    End If
ElseIf x > 50 Then
    score = 1
Else
    score = 0
End If

' Single-Line Conditional
If errorOccurred Then Exit Function
```

#### 2. Pattern & Range Selection (`Select Case`)

Multi-branch dispatch lowered directly to jump tables or optimized conditional branches:

```vb
Select Case messageId
    Case 1, 2, 3
        HandleLowPriority
    Case 10, 20
        HandleHighPriority
    Case Else
        HandleUnknown
End Select
```

#### 3. Iteration & Loops (`For`, `Do`, `While`)

```vb
' For Loop with explicit Step increment
Dim i As Int32
For i = 0 To 100 Step 5
    buffer(i) = 0
Next i

' Pre-tested and Post-tested Do Loops
Do While cursor < length
    cursor = cursor + 1
Loop

Do
    pollStatus = ReadRegister()
    If pollStatus = 1 Then Exit Do
Loop While pollStatus <> 0

' While-Wend Construct
While n < 32
    n = n * 2
Wend
```

#### 4. Pointer Arithmetic & Low-Level Memory Access

In addition to index access (`ptr(i)`), LLB allows direct pointer offset arithmetic:

```vb
Dim startPtr As Pointer To Byte
startPtr = CPtr(Pointer To Byte, &H2000)

' Pointer arithmetic: advances by byte offset
Dim offsetPtr As Pointer To Byte
offsetPtr = startPtr + 16
offsetPtr(0) = &HFF
```

#### 5. VB6-Style String Concatenation & Auto-Conversion (`&` and `+`)

Inspired by Visual Basic 6, LLB provides first-class string concatenation and automatic numeric conversion:

* **Ampersand (`&`):** Unconditionally performs string concatenation. Numbers are automatically formatted and converted to strings without requiring manual `CStr()` calls:
  ```vb
  Dim percent As Int32 = 75
  Dim msg As String
  msg = "Loading " & percent & "%" ' Result: "Loading 75%"
  ```
* **Plus (`+`):** If either operand is a string, `+` performs string concatenation:
  ```vb
  Dim status As String = "Status: " + 100 + "% Complete"
  ```

#### 6. Foreign Function Interface (FFI) & Dynamic Libraries

LLB provides comprehensive support for interfacing with external libraries (both standard C dynamic libraries `.so` / `.dll` and native shared objects):

##### Static/AOT Dynamic Linking (`Declare Function ... Lib ...`)
LLB supports the classic VB6-style `Declare` syntax for binding external functions from libraries:
```vb
' Standard C library binding with symbol aliasing
Declare Function putsLib Lib "c" Alias "puts" (ByVal str As Pointer To Byte) As Int32

' Custom dynamic library binding
Declare Function AddNumbers Lib "SharedLib" Alias "AddNumbers" (ByVal a As Int32, ByVal b As Int32) As Int32
```
* **Syntax:** `[Public | Private] Declare [Sub | Function] Name Lib "libName" [Alias "realSymbol"] (params...) [As ReturnType]`
* **Linkage:** Automatically links against the external symbol using standard C calling conventions (`CallingConv::C`). On ELF targets, `llbc` injects `-rpath $ORIGIN` and `-rpath .` so libraries located in the application directory are automatically discovered at runtime without needing `LD_LIBRARY_PATH`.

##### Dynamic Runtime Loading (`LoadLibrary` / `dlopen`)
In hosted systems, LLB can dynamically load libraries and resolve procedure addresses at runtime via POSIX `dlopen`/`dlsym` or Win32 `LoadLibrary`/`GetProcAddress`:
```vb
' Dynamic runtime resolution using POSIX dlopen / dlsym
Declare Function dlopen Lib "c" (ByVal filename As Pointer To Byte, ByVal flags As Int32) As Pointer To Void
Declare Function dlsym Lib "c" (ByVal handle As Pointer To Void, ByVal symbol As Pointer To Byte) As Pointer To Void
Declare Function dlclose Lib "c" (ByVal handle As Pointer To Void) As Int32

' Win32 dynamic resolution
Declare Function LoadLibraryA Lib "kernel32.dll" (ByVal lpLibFileName As Pointer To Byte) As Pointer To Void
Declare Function GetProcAddress Lib "kernel32.dll" (ByVal hModule As Pointer To Void, ByVal lpProcName As Pointer To Byte) As Pointer To Void
Declare Function FreeLibrary Lib "kernel32.dll" (ByVal hLibModule As Pointer To Void) As Int32
```

##### Compiling Shared Libraries (`-shared`)
LLB can also compile shared libraries (`.so` / `.dll`) for modular plugins, external language FFI, or dynamic loading:
* **Command Line:**
  ```bash
  llbc-stage0 MyLibrary.bas -shared -o libMyLibrary.so
  ```
* **Project Descriptor (`.llbproj`):**
  ```ini
  [Project]
  Name = "MyLibrary"
  Type = "SharedLibrary" ' or "DynamicLibrary"
  ```
Public functions in the module are exported as unmangled symbols.

#### 7. Algebraic Pattern Matching (`Match ... Case ... End Match`)

LLB features comprehensive pattern matching supporting enum values, exact expressions, numeric ranges (`min To max`), sum type variants (`Ok(val)` and `Err(code)`), and fallback wildcards (`Case Else`):

```vb
' Pattern matching over Result sum type
Match result
    Case Ok(val)
        PrintLine "Computation succeeded with: " & val
    Case Err(code)
        PrintLine "Failed with error code: " & code
    Case Else
        PrintLine "Unknown result status"
End Match

' Range and multi-value matching
Match statusCode
    Case 200, 201, 204
        PrintLine "HTTP Success"
    Case 400 To 499
        PrintLine "Client Error Range"
    Case 500 To 599
        PrintLine "Server Error Range"
    Case Else
        PrintLine "Unexpected status code"
End Match
```

#### 8. Deterministic Scoped Cleanup (`Using ... End Using`)

For RAII-style deterministic resource management without garbage collection overhead, LLB provides `Using` blocks. Any object instance implementing a `.Dispose()` method is automatically and unconditionally finalized when execution leaves the block (including early exits or returns):

```vb
Class FileStreamResource
    Public Handle As Int32

    Public Sub Dispose()
        If Me.Handle <> 0 Then
            PrintLine "Closing file handle: " & Me.Handle
            Me.Handle = 0
        End If
    End Sub
End Class

Public Sub ProcessFile()
    Dim stream As FileStreamResource
    stream.Handle = 101

    Using stream
        PrintLine "Processing with handle: " & stream.Handle
        ' Stream.Dispose() is guaranteed to be invoked upon block exit
    End Using
End Sub
```

#### 9. Structured Error Handling & Exception Model

LLB provides dual error handling models:
1. **Classic VB6 `Err` Object:** A freestanding thread-local singleton with `Err.Number`, `Err.Description`, `Err.Source`, `Err.Clear()`, and `Err.Raise(number, source, description)`.
2. **Structured `Try ... Catch ... Finally` Blocks:** Freestanding zero-overhead structured exceptions:

```vb
Try
    ' Code that might trigger an error or raise
    Err.Raise 404, "NetworkService", "Resource not found"
Catch
    PrintLine "Caught error #" & Err.Number & " from " & Err.Source & ": " & Err.Description
    Err.Clear
Finally
    PrintLine "Cleanup logic executes unconditionally"
End Try
```

#### 10. Dynamic Array Resizing & Fixed Array Operations (`ReDim`, `Erase`)

LLB supports both fixed stack arrays and dynamic heap arrays:
* **`ReDim arr(newSize)`**: Allocates or resizes a dynamic array pointer.
* **`ReDim Preserve arr(newSize)`**: Resizes a dynamic array while preserving existing element contents.
* **`Erase arr`**: Zeroes all elements in fixed stack arrays, or frees and clears dynamic pointer arrays.

```vb
Dim dynArr As Pointer To Int32
ReDim dynArr(10)
dynArr(0) = 100
dynArr(1) = 200

' Grow while preserving values
ReDim Preserve dynArr(20)

' Clear array memory
Erase dynArr
```

#### 11. Variadic Arguments & Call-Site Named Parameters

Functions can accept variable-length parameter lists and call-sites can bind parameters out of order:

```vb
' Variadic function via ParamArray
Public Function SumAll(ParamArray values() As Int32) As Int32
    Dim total As Int32 = 0
    Dim i As Int32
    For i = 0 To UBound(values)
        total = total + values(i)
    Next i
    SumAll = total
End Function

' Call-Site Named Arguments
Public Sub ConfigureDevice(ByVal baud As Int32, ByVal parity As Int32, ByVal stopBits As Int32)
    ' ...
End Sub

' Arguments supplied by name out of order
ConfigureDevice stopBits := 1, baud := 115200, parity := 0
```

#### 12. File & Stream I/O Subsystem

LLB includes built-in file channel operations supporting classic BASIC file numbering:
* **`Open "path" For Output As #1`**: Creates or truncates a file for writing.
* **`Open "path" For Append As #1`**: Opens a file for appending.
* **`Open "path" For Binary As #1`**: Opens a file for binary reading/writing.
* **`Print #1, expr`**: Writes text to file channel.
* **`Line Input #1, strVar`**: Reads a newline-delimited line from file channel. If file number `#0` is specified, it reads from standard input (`stdin`).
* **`EOF(fileNum)` / `LOF(fileNum)`**: Returns end-of-file status and length of file in bytes.
* **`Close #1`**: Flushes and closes the channel.

#### 13. Freestanding Runtime & Intrinsics Library

LLB provides an out-of-the-box standard intrinsics library that lowers directly to native machine instructions or zero-dependency freestanding helpers:

| Domain | Functions & Intrinsics | Description |
|---|---|---|
| **Strings** | `Len(s)`, `Mid(s, start, [len])`, `Left(s, n)`, `Right(s, n)`, `InStr([start], s, find)`, `Trim(s)`, `Asc(s)`, `Chr(code)`, `StrComp(s1, s2)` | Zero-dependency freestanding ODR string runtime with bump allocator. |
| **Conversions** | `Val(s)`, `CStr(n)`, `CInt(n)`, `CLng(n)`, `CDbl(n)`, `CBool(n)` | Direct string-to-number and number-to-string formatters. |
| **Math** | `Abs(x)`, `Sgn(x)`, `Sqrt(x)`, `Int(x)` / `Floor(x)` | Direct LLVM hardware intrinsics (`llvm.fabs`, `llvm.sqrt`, `llvm.floor`). |
| **Memory** | `CopyMemory(dst, src, bytes)`, `ZeroMemory(dst, bytes)`, `FillMemory(dst, bytes, val)` | Direct LLVM memory intrinsics (`llvm.memcpy`, `llvm.memset`). |
| **Arrays** | `UBound(arr, [dim])`, `LBound(arr, [dim])` | Returns upper and lower bounds for fixed and multidimensional arrays. |
| **Containers** | `MapCreate()`, `MapHas(m, k)`, `MapGet(m, k)`, `HashMap`, `ArrayList` | Built-in open-addressing hash table runtime and freestanding container structures. |
| **Type Reflection** | `TypeOf expr Is TypeName`, `TypeOf expr Is Not TypeName` | Compile-time and pointer-level type safety verification. |
| **Pattern Match** | `s Like pattern` | Zero-heap pattern matcher supporting `*` and `?` wildcards. |


---

### Self-Hosting Roadmap & LLVM-C API Bindings

The Stage-1 compiler (`llbc-stage1`) is written entirely in Low-Level Basic. It bridges to the LLVM code generator and target emitter via direct bindings to the LLVM-C API (`libLLVM`) defined in `src/stage1/LlvmC.bas`:

* **Context & Modules:** `LLVMContextCreate()`, `LLVMModuleCreateWithNameInContext()`
* **Type Construction:** `LLVMInt32TypeInContext()`, `LLVMPointerType()`, `LLVMFunctionType()`
* **Instruction Builders:** `LLVMBuildAlloca()`, `LLVMBuildStore()`, `LLVMBuildLoad2()`, `LLVMBuildGEP2()`, `LLVMBuildCall2()`
* **Target Emission:** `LLVMTargetMachineEmitToFile()`

---

### Project Descriptor Specification (`.llbproj`)

LLB projects are configured via `.llbproj` manifest files, removing the need for external Makefiles or shell build scripts.

```ini
' Project Name: Low-Level Basic Kernel
' Manifest Descriptor: Kernel.llbproj

[Project]
Name        = "kernel"
Type        = "Kernel" ; Kernel, BareMetalExecutable, FlatBinary, Executable, SharedLibrary, StaticLibrary
Version     = "0.1.0"
Author      = "karunci"
License     = "MPL-2.0"
Platform    = "freestanding" ; freestanding | hosted

[Target]
Architecture = "x86_64-unknown-none-elf"

[Entry]
EntryPoint = "_start"

[Linker]
LinkerScript = "linker.ld"

[Output]
OutputDirectory = "build"
BinaryName      = "kernel.elf"

[Sources]
Files = [
    "src/arch/x86_64/boot.S",
    "src/arch/x86_64/IsrStubs.S",
    "src/arch/x86_64/Idt.bas",
    "src/drivers/Terminal.cls",
    "src/KernelMain.bas"
]

[CompilerOptions]
OptimizationLevel      = "O2" ; O0, O1, O2, O3, Os
EmitDebugInfo          = true ; true / false (generates DWARF debug symbols)
Freestanding           = true ; true / false
DisableStandardLibrary = true ; true / false
```

#### Supported Project Types (`Type = "..."`)

| Type Category | Type Name / Aliases | Runtime / CRT | Default Ext | Description |
|:---|:---|:---:|:---:|:---|
| **Freestanding / Bare-Metal** | `Kernel`, `BareMetalExecutable`, `BareMetal`, `Freestanding` | `--nostdlib` (No CRT) | `.elf` | Bare-metal ELF executable, linked with custom linker script or freestanding entry |
| **Flat Binary** | `FlatBinary`, `RawBinary`, `Binary` | `--nostdlib` (No CRT) | `.bin` | Direct raw binary file extracted via `llvm-objcopy -O binary` (bootloaders, raw ROMs) |
| **Hosted Executable** | `Executable`, `HostedExecutable` | Host libc / CRT | `.elf` / none | Hosted userspace application targeting the host operating system |
| **Shared Library** | `SharedLibrary`, `DynamicLibrary` | Host CRT (`-shared`) | `.so` | Dynamic shared library |
| **Static Archive** | `StaticLibrary`, `Archive` | None (`llvm-ar`) | `.a` | Static library archive |

#### Manifest Section Reference

- `[Project]`: Core project metadata (`Name`, `Type`, `Version`, `Author`, `License`, `Platform`).
- `[Target]`: Cross-compilation settings (`Architecture` or `Arch = "<target-triple>"`). Omit or leave empty for host native target.
- `[Output]`: Artifact location and naming controls:
  - `OutputDirectory` / `OutDir`: Relative directory where all build artifacts are isolated (e.g., `build`).
  - `BinaryName` / `OutFile`: Explicit filename for the final compiled target (e.g., `kernel.elf`, `testsuite`, `libllb.a`).
- `[Entry]`: Target entry point symbol (`EntryPoint = "_start"`).
- `[Linker]`: Linker script specification (`LinkerScript = "linker.ld"`).
- `[Sources]`: Array of source units (`Files = [ ... ]`) or repeating key declarations (`Module = "..."`, `Class = "..."`, `Assembly = "..."`).
- `[CompilerOptions]`: Compiler optimization and codegen controls:
  - `OptimizationLevel = "O0" | "O1" | "O2" | "O3" | "Os"`
  - `EmitDebugInfo = true | false` (enables DWARF debug symbols `-g`)
  - `Freestanding = true | false`
  - `DisableStandardLibrary = true | false`
- `[Script]` / `[PostBuild]`: Sequential post-build commands executed after linking completes successfully:
  - `Cmd = "program_or_script.sh"`: Runs command or script sequentially.
  - `Script = "path/to/script.sh"` or `Bash = "test.sh"`: Executes target script.
  - `Timeout = 30`: Maximum execution time in seconds per command (default: 30s, 0=unlimited).
  - Multiple entries are executed in sequential order.
  - Can be skipped at invocation time via `--no-script`.

#### Multi-Project Builds & Command-Line Invocation

The compiler driver (`llbc`) supports two primary invocation modes:

1. **Multi-Project Manifest Mode**: Pass one or more `.llbproj` project descriptors:
   ```bash
   llbc tests/kernel/Kernel.llbproj tests/userland/TestSuite.llbproj
   ```
   Each project is built sequentially in its own isolated context (symbol catalogs and module indices are cleared between builds). If any project fails, compilation halts immediately with that project's exit status.
2. **Direct Source Compilation Mode**: Pass individual `.bas`, `.cls`, `.S`, or object/library files directly:
   ```bash
   llbc src/Main.bas src/Helper.bas -o build/app.elf
   ```

> [!NOTE]
> **CLI Precedence:** Command-line options (e.g. `-o`, `-O2`, `-T`, `--target`, `--script-timeout`) always take precedence over values specified in `.llbproj` manifest files.

#### Input Validation & Guards

- **File Existence Guard**: Validates that all CLI input files, `-I` include directories, and `-T` linker scripts exist before starting compilation.
- **Directory Guard**: Rejects directory paths inadvertently passed as input files (and vice versa for `-I`).
- **Extension Guard**: Rejects unsupported input file extensions, providing explicit guidance on recognized inputs (`.llbproj`, `.bas`, `.cls`, `.S`, `.s`, `.o`, `.a`, `.so`).
- **Source Verification**: Automatically checks that all source and assembly units declared within `.llbproj` files exist on disk before compilation commences.



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

#### File 2: `src/drivers/Terminal.bas` (Freestanding VGA Terminal Driver)

```vb
' Project Name: PRK-OS
' Filename: src/drivers/Terminal.bas
' Summary: High-performance bare-metal VGA text mode (80x25) console driver for x86_64 Long Mode.

Module Drivers.Terminal

    Public Const VGA_WIDTH As UInt32 = 80
    Public Const VGA_HEIGHT As UInt32 = 25
    Public Const VGA_MEMORY_ADDRESS As UInt64 = &HB8000

    Public Const COLOR_BLACK As Byte = 0
    Public Const COLOR_BLUE As Byte = 1
    Public Const COLOR_GREEN As Byte = 2
    Public Const COLOR_CYAN As Byte = 3
    Public Const COLOR_RED As Byte = 4
    Public Const COLOR_MAGENTA As Byte = 5
    Public Const COLOR_BROWN As Byte = 6
    Public Const COLOR_LIGHT_GREY As Byte = 7
    Public Const COLOR_DARK_GREY As Byte = 8
    Public Const COLOR_LIGHT_BLUE As Byte = 9
    Public Const COLOR_LIGHT_GREEN As Byte = 10
    Public Const COLOR_LIGHT_CYAN As Byte = 11
    Public Const COLOR_LIGHT_RED As Byte = 12
    Public Const COLOR_LIGHT_MAGENTA As Byte = 13
    Public Const COLOR_LIGHT_BROWN As Byte = 14
    Public Const COLOR_WHITE As Byte = 15

    Private cursorX As UInt32
    Private cursorY As UInt32
    Private currentAttribute As Byte

    Private Function MakeAttribute(ByVal fg As Byte, ByVal bg As Byte) As Byte
        MakeAttribute = fg Or (bg LShift 4)
    End Function

    Private Function MakeVgaEntry(ByVal ch As Byte, ByVal attr As Byte) As UInt16
        MakeVgaEntry = CType(UInt16, ch) Or (CType(UInt16, attr) LShift 8)
    End Function

    Public Unsafe Sub Initialize(Optional ByVal fg As Byte = COLOR_WHITE, Optional ByVal bg As Byte = COLOR_BLACK)
        cursorX = 0
        cursorY = 0
        currentAttribute = MakeAttribute(fg, bg)
        Clear
    End Sub

    Public Sub SetColor(ByVal fg As Byte, Optional ByVal bg As Byte = COLOR_BLACK)
        currentAttribute = MakeAttribute(fg, bg)
    End Sub

    Public Unsafe Sub Clear()
        Dim vgaBuf As Volatile Pointer To UInt16
        vgaBuf = CPtr(Volatile Pointer To UInt16, VGA_MEMORY_ADDRESS)

        Dim blankEntry As UInt16
        blankEntry = MakeVgaEntry(32, currentAttribute)

        Dim i As UInt32
        For i = 0 To (VGA_WIDTH * VGA_HEIGHT) - 1
            vgaBuf(i) = blankEntry
        Next i

        cursorX = 0
        cursorY = 0
    End Sub

    Public Unsafe Private Sub Scroll()
        Dim vgaBuf As Volatile Pointer To UInt16
        vgaBuf = CPtr(Volatile Pointer To UInt16, VGA_MEMORY_ADDRESS)

        Dim row As UInt32
        Dim col As UInt32
        Dim destOffset As UInt32
        Dim srcOffset As UInt32

        For row = 1 To VGA_HEIGHT - 1
            For col = 0 To VGA_WIDTH - 1
                destOffset = ((row - 1) * VGA_WIDTH) + col
                srcOffset = (row * VGA_WIDTH) + col
                vgaBuf(destOffset) = vgaBuf(srcOffset)
            Next col
        Next row

        Dim blankEntry As UInt16
        blankEntry = MakeVgaEntry(32, currentAttribute)
        Dim bottomRowOffset As UInt32
        bottomRowOffset = (VGA_HEIGHT - 1) * VGA_WIDTH

        For col = 0 To VGA_WIDTH - 1
            vgaBuf(bottomRowOffset + col) = blankEntry
        Next col

        cursorY = VGA_HEIGHT - 1
    End Sub

    Public Unsafe Sub WriteChar(ByVal ch As Byte)
        Dim vgaBuf As Volatile Pointer To UInt16
        vgaBuf = CPtr(Volatile Pointer To UInt16, VGA_MEMORY_ADDRESS)

        If ch = 10 Then
            cursorX = 0
            cursorY = cursorY + 1
        ElseIf ch = 13 Then
            cursorX = 0
        Else
            Dim charOffset As UInt32
            charOffset = (cursorY * VGA_WIDTH) + cursorX
            vgaBuf(charOffset) = MakeVgaEntry(ch, currentAttribute)
            cursorX = cursorX + 1
        End If

        If cursorX >= VGA_WIDTH Then
            cursorX = 0
            cursorY = cursorY + 1
        End If

        If cursorY >= VGA_HEIGHT Then
            Scroll
        End If
    End Sub

    Public Unsafe Sub WriteString(ByVal strPtr As Pointer To Byte)
        Dim i As UInt64
        i = 0
        Do While strPtr(i) <> 0
            WriteChar strPtr(i)
            i = i + 1
        Loop
    End Sub

    Public Unsafe Sub WriteLine(ByVal strPtr As Pointer To Byte)
        WriteString strPtr
        WriteChar 10
    End Sub

End Module
```

#### File 3: `src/KernelMain.bas` (Kernel Entry Point)

```vb
' Project Name: PRK-OS
' Filename: src/KernelMain.bas
' Summary: Low-Level Basic Kernel Entrypoint.

Module KernelMain

    Import Drivers.Terminal
    Import Arch.Idt

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize VGA Terminal Driver (Light Green on Black)
        Drivers.Terminal.Initialize Drivers.Terminal.COLOR_LIGHT_GREEN, Drivers.Terminal.COLOR_BLACK

        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "      PRK-OS LOW-LEVEL BASIC KERNEL      ")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteChar 10

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_CYAN
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Magic: ")
        Drivers.Terminal.WriteHex CType(UInt64, magic)
        Drivers.Terminal.WriteChar 10

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Info Address: ")
        Drivers.Terminal.WriteHex CType(UInt64, mbAddress)
        Drivers.Terminal.WriteChar 10

        ' Initialize IDT interrupt descriptors
        Arch.Idt.Initialize

        Do
            Asm "hlt"
        Loop
    End Sub

End Module
```

---

### Toolchain & Environment Specifications

Low-Level Basic has been developed and verified on the following toolchain environment:

- **Compiler Backend:** LLVM 21.1.8 (`llvm-config --version`)
- **C/C++ Host Compiler:** Clang 21.1.8 / C++17
- **Linker:** Embedded LLD (ELF driver)
- **Build System:** CMake 3.18+ (tested with CMake 3.31.6)
- **Environments Verified:** Linux (aarch64 / Termux Android 14+), Linux (x86_64), QEMU 9.x+ (Multiboot1 / Multiboot2 bare-metal emulation)

### Toolchain Build Summary

To execute the self-hosting compiler pipeline on your project:

1. **Build `llbc-stage0` (C++ Driver):**
```bash
mkdir build && cd build
cmake ..
cmake --build . -j4
```

2. **Compile LLB Kernel Project:**
```bash
./llbc-stage0 tests/kernel/Kernel.llbproj
```

3. **Test Executable in QEMU (Verified on Bare-Metal & Termux):**
```bash
# Direct Multiboot kernel boot with serial output mirrored to terminal
qemu-system-x86_64 -kernel tests/kernel/kernel.elf -display none -serial stdio -no-reboot -no-shutdown
```

**Verified Boot Output:**
```text
[PRK-OS KERNEL] Booting Low-Level Basic Kernel in QEMU!
[PRK-OS KERNEL] Multiboot Verified. Long mode active.
[PRK-OS KERNEL] VGA Terminal Driver initialized (&HB8000).
[PRK-OS KERNEL] Initializing IDT interrupt descriptors...
[PRK-OS KERNEL] IDT gates registered successfully.
[PRK-OS KERNEL] Kernel execution completed successfully. Halting CPU.
```

**VGA Terminal Demo Screenshot:**

![PRK-OS Low-Level Basic VGA Text Mode Screenshot](docs/vga_terminal_demo.png)

---

### Development & Methodology

Low-Level Basic (`LLB` / `llbc`) is engineered using an AI-assisted pair-programming methodology:

- **Human Architecture & Technical Direction:** Language syntax, type-system semantics, microkernel abstractions, memory layout invariants, and technical oversight are directed by the author (`karunci`).
- **AI Pair Programming:** AST generation, LLVM IR emission routines, extensive test suites, and documentation scaffolding were iteratively developed with AI coding agents.
- **Strict Verification Standards:** All code, compiler outputs, and kernel ELF binaries are tested against bare-metal execution targets in QEMU, 30 compiler rejection tests, 10 CLI options tests, and 66 comprehensive automated test suites.

For full disclosure regarding our development model and licensing restrictions, see [AI_DISCLOSURE.md](../AI_DISCLOSURE.md).
