# LLB Gap Analysis: VB6 Features & Modern Language Standards

> **Status Legend:** ✅ Implemented | 🔧 Partial | ❌ Missing

## Core Design Philosophy & Architecture

LLB fuses the safety and performance of modern systems languages with the approachable simplicity of Visual Basic 6:
- **Rust-grade Safety & Intent:** Static boundary checking, explicit null guarantees, zero-overhead abstractions, and explicit `Unsafe` fences for low-level memory operations.
- **C/C++ Control & Freedom:** Manual memory management (`CPtr`, `Pointer To T`, bump allocators, custom memory pools), inline assembly (`Asm`), and byte-accurate struct alignment (`<Packed>`, `<Align(N)>`).
- **VB6 Clarity & Readability:** Intuitive keyword syntax (`Sub`, `Function`, `ByVal`, `ByRef`, `With`, `Select Case`, `Print`), eliminating syntax clutter while generating fast, native machine code.
- **Systems & Freestanding First:** 100% self-contained microkernel/bootloader compatibility with zero mandatory host C library dependencies, fast compile times, and embedded LLD linking.

---

## A. Core Language Syntax (VB6 Parity)

| Feature | Status | Notes |
|---------|--------|-------|
| `Module` / `End Module` | ✅ | Static singleton compilation units |
| `Class` / `End Class` | ✅ | With implicit `Me` pointer |
| `Sub` / `Function` / `End Sub` / `End Function` | ✅ | With `ByVal` / `ByRef` |
| `If / ElseIf / Else / End If` | ✅ | Multi-branch, nested |
| `For / To / Step / Next` | ✅ | With `Exit For` |
| `Do / Loop While / Until` | ✅ | Pre/post-condition, `Exit Do` |
| `While / Wend` | ✅ | Classic BASIC loop |
| `Select Case / Case / Case Else / End Select` | ✅ | Multi-value dispatch |
| `Exit Sub / Function / For / Do / While` | ✅ | All exit forms |
| `Dim` / `Const` | ✅ | Local declarations |
| `Public` / `Private` visibility | ✅ | External vs internal linkage |
| String concatenation (`&` and `+`) | ✅ | With auto int-to-string conversion |
| `Declare Function ... Lib "name"` | ✅ | FFI binding to external `.so`/`.dll` with `Lib` clause & `Alias` |
| `Enum` / `End Enum` | ✅ | Named integer constant groups |
| `Type` (UDT — User Defined Type) | ✅ | Fully supported `Type...End Type` as VB6 alias for `Structure` |
| `GoTo <Label>` / `<Label>:` | ✅ | Unconditional branch and intra-procedure label jumps |
| `Try ... Catch ... Finally / End Try` | ✅ | Freestanding structured error and exception handling model |
| `ReDim` / `ReDim Preserve` | ✅ | Dynamic array resizing with optional element preservation |
| `Erase` | ✅ | Array deallocation & zeroing (stack arrays zeroed, pointer arrays cleared) |
| `With ... End With` | ✅ | Implicit member access block |
| `Optional` parameters + defaults | ✅ | `Optional [ByVal/ByRef] x As Type = DefaultValue` supported |
| `ParamArray` (variadic args) | ✅ | Variable-length argument list packing into dynamic array pointer |
| `Named arguments` (`func(name := val)`) | ✅ | Call-site parameter naming and out-of-order parameter resolution |
| `Property Get / Let / Set` | ✅ | Property accessors for classes and modules |
| `Set obj = New ClassName` | ✅ | Object instantiation with `New ClassName` and `Delete obj` lifecycle |
| `Is` / `Nothing` object comparison | ✅ | Pointer & object null reference checks (`ptr Is Nothing`, `ptr Is Not Nothing`) |
| `TypeOf ... Is ...` | ✅ | Static/compile-time and UDT/Pointer type checking (`TypeOf x Is TypeName`, `TypeOf x Is Not TypeName`) |
| `Like` string pattern matching | ✅ | Glob-style `*` and `?` pattern matching with zero-heap backtrack |
| `Mid$`, `Left$`, `Right$`, `Len`, `InStr`, `Trim`, `Asc`, `Chr` | ✅ | Built-in zero-dependency freestanding string functions |
| `CStr`, `CInt`, `CLng`, `CDbl`, `Val` conversion | ✅ | Explicit type conversion & numeric parsing functions |
| Line continuation (`_`) | ✅ | Multi-line statement support |
| String comparison (`StrComp`, `Option Compare`) | ✅ | Built-in three-way string comparison function (`StrComp`) returning -1, 0, 1 |
| `DoEvents` | ❌ | Cooperative yield (N/A for systems lang) |
| Collections / `For Each` | ✅ | Iterator-based looping over fixed arrays & dynamic collections (`ArrayList`, etc.) |

---

## B. Type System

| Feature | Status | Notes |
|---------|--------|-------|
| Fixed-width integers (`Byte`, `Int16`, `Int32`, `Int64`) | ✅ | Full set |
| `Boolean` | ✅ | i1 type |
| `String` (pointer-based) | ✅ | Mapped to `ptr` (i8*) |
| `Pointer To T` (typed pointers) | ✅ | With arbitrary depth |
| `Volatile Pointer To T` | ✅ | MMIO-safe pointers |
| Packed structures (`<Packed>`, `<Align(N)>`) | ✅ | Hardware descriptor layout |
| Static arrays (`Dim x(N) As T`) | ✅ | Stack-allocated fixed arrays |
| `Single` / `Double` (floating point) | ✅ | IEEE-754 32-bit & 64-bit float types |
| `Currency` / `Decimal` | ✅ | Fixed-point decimal types (64-bit fixed-point scaled units) |
| `Variant` / `Object` | ❌ | Dynamic/boxed types (low priority for systems lang) |
| `Date` | ❌ | Date/time type |
| Dynamic arrays (heap, resizable) | ❌ | Requires runtime allocator |
| Multidimensional arrays / Matrices (`Dim x(M, N)`) | ✅ | Row-major flat indexing computation |
| `UBound` / `LBound` | ✅ | Dimension-aware array bounds intrinsics (`UBound(arr, dim)`) |
| Union types (`Union ... End Union`) | ✅ | Overlapping memory layout with offset-0 member aliasing for registers & hardware protocols |
| Nullable / Optional types | ❌ | `T?` or `Maybe T` |
| Generics / Templates | ❌ | Parameterized types |
| Type aliases (`TypeAlias X = Y`) | ✅ | Named type synonyms for primitives, pointers, and UDTs |
| Signed vs Unsigned distinction in ops | ✅ | `UDiv`, `URem`, `LShr`, and unsigned comparisons (`ULT`, `ULE`, `UGT`, `UGE`) for unsigned operands |

---

## C. Memory Management & Safety

| Feature | Status | Notes |
|---------|--------|-------|
| Stack allocation (`Dim`) | ✅ | Via LLVM `alloca` |
| Raw pointer casting (`CPtr`) | ✅ | With `Unsafe` annotation |
| Pointer arithmetic (`ptr + offset`) | ✅ | Byte-granular GEP |
| `Unsafe` keyword annotation | ✅ | On functions doing raw memory |
| Heap allocation (`malloc` via runtime) | ✅ | Fully integrated `New ClassName` and `Delete obj` lifecycle with freestanding allocator hooks |
| `New` / `Delete` keywords | ✅ | Object lifecycle management (`New ClassName` and `Delete obj`) |
| Reference counting / `Set` | ❌ | VB6-style COM ref counting |
| `AddressOf` operator | ✅ | Extract typed function and procedure addresses (`AddressOf Func`) |
| Bounds-checked array access | ✅ | Compiler-injected runtime bounds validation on array access (`idxgep`), zero-cost bypassable via `Unsafe` |
| Null-pointer safety checks | ✅ | Zero-address null guard insertion before pointer dereferences, zero-cost bypassable via `Unsafe` |
| Stack buffer overflow protection | ✅ | Stack canary protection via LLVM `StackProtectStrong` attribute |
| Ownership / Borrow checker | ❌ | Rust-style memory safety (aspirational) |
| `Dispose` / RAII cleanup | ❌ | Deterministic resource cleanup |
| `GC` (garbage collection) | ❌ | Not planned for systems language |

---

## D. Runtime & Standard Library

| Feature | Status | Notes |
|---------|--------|-------|
| `__llbc_allocate_instance` | ✅ | Minimal malloc wrapper |
| Auto-declared `puts`, `printf` | ✅ | Implicit C library binding |
| `snprintf`, `strlen`, `memcpy`, `malloc` | ✅ | Used internally for string concat |
| String runtime (`Mid`, `Left`, `Right`, `Len`, `InStr`, `Trim`, `Asc`, `Chr`) | ✅ | Self-contained, freestanding ODR bump allocator |
| Math library (`Abs`, `Sgn`, `Sqrt`, `Int`/`Floor`) | ✅ | Native LLVM intrinsics (`llvm.fabs`, `llvm.sqrt`, `llvm.floor`, selects) |
| I/O library (`Open`, `Print #`, `Line Input #`, `Input #`, `Close`, `EOF`, `LOF`) | ✅ | Full file stream I/O with multiple file numbers (1..255), reading, writing, and file status |
| Console I/O (`Print`, `PrintLine`, `PrintFormat`/`PrintF`, `Input`) | ✅ | Both statement form and built-in call wrappers |
| Date/Time library (`Now`, `DateDiff`, `Format`) | ❌ | Calendar operations |
| Error runtime (`Err.Number`, `Err.Description`) | ❌ | Error info structure |
| Collection runtime (`Dictionary`, `Map`, `HashMap`, `ArrayList`) | ✅ | ODR open-addressing hash table runtime (`map("k") = v`), intrinsics (`MapCreate`, `MapHas`, `MapGet`), and freestanding `HashMap` & `ArrayList` UDTs |
| Memory runtime (`CopyMemory`, `ZeroMemory`, `FillMemory`) | ✅ | Direct lowering to native freestanding LLVM `llvm.memcpy` & `llvm.memset` intrinsics |

---

## E. Toolchain & Build System

| Feature | Status | Notes |
|---------|--------|-------|
| Single-file compilation (`llbc file.bas -o out`) | ✅ | Working |
| Project manifests (`.llbproj`) | ✅ | INI-style build descriptors |
| Assembly file compilation (`.S`) | ✅ | GNU AS via LLVM MC |
| Object file emission (`.o`) | ✅ | ELF via LLVM TargetMachine |
| Executable linking (LLD) | ✅ | Embedded LLD |
| Dynamic library linking (`-shared`) | ✅ | `.so` generation |
| Static library archiving (`.a`) | ✅ | Native LLVM archive writer (`llvm::writeArchive`) via `-static` / `-archive` / `.a` |
| Multi-module compilation | ✅ | Fully supported with automatic transitive dependency discovery |
| `Import` / `#include` system | ✅ | Modular import resolution: `Import ModuleName`, `Import Mod.Sym`, `Import In "path"` |
| Optimization passes (`-O0` to `-O3`) | ✅ | Full LLVM PassBuilder pipeline integration |
| Debug info emission (`-g`, DWARF) | ✅ | Source-level DWARF v4 debugging symbols & subprogram line/col mappings |
| Cross-compilation (`--target=`) | 🔧 | Triple in `.llbproj`, not CLI |
| Incremental / parallel builds | ❌ | Recompile-only-changed |
| Package manager | ❌ | Dependency resolution |
| LSP / IDE integration | ❌ | Language server protocol |

---

## F. FFI & Interoperability

| Feature | Status | Notes |
|---------|--------|-------|
| C ABI function calls | ✅ | CallingConv::C on all functions |
| `Declare Function ... ()` extern stubs | ✅ | Forward declarations |
| `Declare ... Lib "name"` (load from .so/.dll) | ✅ | Fully supported `Declare [Sub/Function] ... Lib "lib" [Alias "name"]` with `-rpath $ORIGIN` |
| `Alias "real_name"` (symbol renaming) | ✅ | Map LLB identifier to external symbol name |
| Dynamic loading (`LoadLibrary` / `dlopen`) | ✅ | Full dynamic runtime symbol resolution via POSIX `dlopen`/`dlsym` & Win32 `LoadLibrary`/`GetProcAddress` |
| Callback / function pointer passing | ✅ | `AddressOf` operator with typed pointer passing |
| C struct layout interop | 🔧 | `<Packed>` works, but no `<LayoutKind.Sequential>` |
| POSIX / Win32 API bindings | 🔧 | Supported via `Declare ... Lib "c"` / `Lib "kernel32.dll"` stubs |
| COM / IUnknown interop | ❌ | VB6's core object model (low priority) |

---

## G. Modern Language Features (Beyond VB6)

| Feature | Status | Notes |
|---------|--------|-------|
| Inline assembly (`Asm`) | ✅ | GCC-style with clobbers |
| Freestanding / bare-metal target | ✅ | `--nostdlib`, custom linker scripts |
| MMIO volatile pointers | ✅ | `Volatile Pointer To T` |
| Hardware descriptor annotations | ✅ | `<Packed>`, `<Align(N)>` |
| First-class closures / lambdas | ❌ | Anonymous functions with captures |
| Pattern matching (`Match ... End Match`) | ❌ | Algebraic pattern decomposition |
| Async / Await | ❌ | Cooperative async I/O |
| Interfaces / Traits / Protocols | ❌ | Abstract method contracts |
| Operator overloading | ❌ | Custom `+`, `-`, `=`, etc. |
| Iterators / Generators (`Yield`) | ❌ | Lazy sequence production |
| Namespaces / Module nesting | ❌ | Hierarchical scope organization |
| Compile-time evaluation (`Const` expressions) | ✅ | Compile-time constant evaluation in preprocessor |
| Conditional compilation (`#If`, `#Else`, `#End If`) | ✅ | Full preprocessor directives (`#Const`, `#If`, `#ElseIf`, `#Else`, `#End If`) with `-D` flags |
| Attributes / Annotations beyond `<Packed>` | ✅ | `<Inline>` (AlwaysInline), `<NoReturn>`, `<Export>`, `<Packed>`, `<Align(N)>` |
| Result / Error return types | ❌ | `Result(T, E)` sum types |

---

## Recommended Priority Roadmap

### Phase 1: Language Completeness (Immediate) — COMPLETE ✅
1. ~~String concatenation~~ — **Done** ✅
2. ~~Dynamic library output (`-shared`)~~ — **Done** ✅
3. ~~`Declare ... Lib "name"` FFI binding & `Alias`~~ — **Done** ✅
4. ~~`Enum` / `End Enum`~~ — **Done** ✅
5. ~~Floating-point (`Single` / `Double`) + arithmetic~~ — **Done** ✅
6. ~~`With ... End With`~~ — **Done** ✅
7. ~~Line continuation (`_`)~~ — **Done** ✅

### Phase 2: Standard Library & Runtime
8. ~~String library (`Len`, `Mid`, `Left`, `Right`, `InStr`, `Trim`, `Asc`, `Chr`)~~ — **Done** ✅
9. ~~Type conversion functions (`CStr`, `CInt`, `CLng`, `CDbl`, `Val`)~~ — **Done** ✅
10. ~~Console I/O (`Print`, `Input`)~~ — **Done** ✅
11. ~~File I/O (`Open`, `Close`, `Print #`, `Line Input #`, `EOF`, `LOF`)~~ — **Done** ✅

### Phase 3: Toolchain Hardening
12. ~~LLVM optimization passes (`-O1`, `-O2`, `-O3` via PassBuilder)~~ — **Done** ✅
13. ❌ Debug info emission (DWARF `-g`) — **In Progress** 🎯
14. ~~`Import` / module dependency resolution~~ — **Done** ✅
15. ~~Static library output (`.a`)~~ — **Done** ✅
16. ~~Conditional compilation (`#If`)~~ — **Done** ✅

### Phase 4: Modern Language Power
17. ~~`New` / `Delete` + heap object lifecycle~~ — **Done** ✅
18. ❌ Interfaces / Traits
19. ❌ Generics / Templates
20. ~~First-class function pointers / `AddressOf`~~ — **Done** ✅
21. ❌ Closures / Lambdas
