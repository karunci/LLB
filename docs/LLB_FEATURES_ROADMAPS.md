# LLB Gap Analysis: VB6 Features & Modern Language Standards

> **Status Legend:**
> - ✅ **Implemented**: Fully operational in compiler, runtime, and verified in test suites.
> - 🔧 **Partial**: Functional with known boundaries or alternate idiom available.
> - 🚫 **Non-Goal / Won't Implement**: Intentionally excluded to maintain freestanding microkernel portability, zero-cost abstractions, deterministic latency, and cross-compilation integrity.
> - ⏳ **Future Roadmap**: High-value candidate for post-bootstrap development.

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
| `Class` / `End Class` | ✅ | Encapsulated OOP with `<Instancing(Global/SingleUse/MultiUse)>` and compile-time uninitialized verification |
| `Use` / `In` / `As` | ✅ | Fine-grained scope binding, aliasing, and one-liner instantiation (`Use [New] Class In Ns As [New] alias`) |
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
| `DoEvents` | 🚫 Won't Implement | Windows GUI message pump (`PeekMessage`/`DispatchMessage`). Inapplicable for freestanding systems & kernels. |
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
| `Variant` / `Object` | 🚫 Won't Implement | Dynamically-typed boxed COM structures. Contradicts bare-metal zero-cost goals; use `Union`, `Structure(Of T)`, or `Result(T, E)`. |
| `Date` | 🚫 Won't Implement | High-level calendar/locale type requiring OS libc timezone databases. Systems code uses `UInt64` UNIX timestamps. |
| Dynamic arrays (syntax `Dim x()`) | 🔧 Partial | Supported via dynamic pointer resizing (`ReDim`, `ReDim Preserve`, `Erase`) and freestanding `ArrayList`. Fat-pointer syntax is a future candidate. |
| Multidimensional arrays / Matrices (`Dim x(M, N)`) | ✅ | Row-major flat indexing computation |
| `UBound` / `LBound` | ✅ | Dimension-aware array bounds intrinsics (`UBound(arr, dim)`) |
| Union types (`Union ... End Union`) | ✅ | Overlapping memory layout with offset-0 member aliasing for registers & hardware protocols |
| Nullable / Optional types (`T?`) | 🔧 Idiomatic | Represented idiomatically via `Result(T, E)` sum types or `Pointer Is Nothing` null guards. |
| Generics / Templates | ✅ | Parameterized templates (`Structure Box(Of T)`, `Function Min(Of T)`) with on-demand monomorphization |
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
| Reference counting (`IUnknown` / COM) | 🚫 Won't Implement | Windows-specific desktop component model. Scoped deterministic RAII cleanup is handled via `Using ... End Using`. |
| `AddressOf` operator | ✅ | Extract typed function and procedure addresses (`AddressOf Func`) |
| Bounds-checked array access | ✅ | Compiler-injected runtime bounds validation on array access (`idxgep`), zero-cost bypassable via `Unsafe` |
| Null-pointer safety checks | ✅ | Zero-address null guard insertion before pointer dereferences, zero-cost bypassable via `Unsafe` |
| Stack buffer overflow protection | ✅ | Stack canary protection via LLVM `StackProtectStrong` attribute |
| Ownership / Borrow checker | ⏳ Future Roadmap | Rust-style affine borrow checker (aspirational for post-bootstrap phases). |
| `Dispose` / RAII cleanup | ✅ | Deterministic scoped resource management with `Using ... End Using` calling `.Dispose()` |
| `GC` (garbage collection) | 🚫 Won't Implement | Non-goal for systems language; manual lifecycle, bump allocators, and scoped RAII guarantee zero GC latency. |

---

## D. Runtime & Standard Library

| Feature | Status | Notes |
|---------|--------|-------|
| `__llbc_allocate_instance` | ✅ | Minimal malloc wrapper |
| Auto-declared `puts`, `printf` | ✅ | Implicit C library binding |
| `snprintf`, `strlen`, `memcpy`, `malloc` | ✅ | Used internally for string concat |
| String runtime (`Mid`, `Left`, `Right`, `Len`, `InStr`, `Trim`, `Asc`, `Chr`) | ✅ | Self-contained, freestanding ODR bump allocator |
| Math library (`Abs`, `Sgn`, `Sqrt`, `Int`/`Floor`) | ✅ | Native LLVM intrinsics (`llvm.fabs`, `llvm.sqrt`, `llvm.floor`, selects) |
| I/O library (`Open`, `Print #`, `Line Input #`, `Input #`, `Close`, `EOF`, `LOF`) | ✅ | Full file stream I/O with multiple file numbers (1..255) and stdin channel `#0` |
| Console I/O (`Print`, `PrintLine`, `PrintFormat`/`PrintF`, `Input`) | ✅ | Both statement form and built-in call wrappers |
| Date/Time library (`Now`, `DateDiff`, `Format`) | 🚫 Won't Implement | OS-specific calendar formatting; standard 64-bit integer timer ticks used instead. |
| Error runtime (`Err.Number`, `Err.Description`) | ✅ | Full VB6 `Err` runtime singleton with `Err.Number`, `Err.Source`, `Err.Description`, `Err.Raise`, and `Err.Clear` |
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
| Cross-compilation (`--target=`) | ✅ | Full CLI `--target=<triple>`, `--sysroot=<path>`, and `--nostdlib` toolchain cross-compilation with LLD emulation mapping |
| Incremental / parallel builds | ⏳ Future Roadmap | Dependency graph caching for recompiling only modified units. |
| Package manager | ⏳ Future Roadmap | External ecosystem dependency manager. |
| LSP / IDE integration | ⏳ Future Roadmap | Language Server Protocol daemon for syntax highlighting and autocomplete. |

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
| C struct layout interop | 🔧 | `<Packed>` and `<Align(N)>` supported; full MSVC bitfield layout in progress |
| POSIX / Win32 API bindings | 🔧 | Supported via `Declare ... Lib "c"` / `Lib "kernel32.dll"` stubs |
| COM / IUnknown interop | 🚫 Won't Implement | Windows-specific desktop object model; inapplicable to cross-target and freestanding bare-metal targets. |

---

## G. Modern Language Features (Beyond VB6)

| Feature | Status | Notes |
|---------|--------|-------|
| Inline assembly (`Asm`) | ✅ | GCC-style with clobbers |
| Freestanding / bare-metal target | ✅ | `--nostdlib`, custom linker scripts, dual Multiboot headers (verified booting directly in QEMU x86_64) |
| MMIO volatile pointers | ✅ | `Volatile Pointer To T` (verified in VGA driver at `0xB8000`) |
| Hardware descriptor annotations | ✅ | `<Packed>`, `<Align(N)>` (verified in 16-byte IDT descriptors & GDT tables) |
| First-class closures / lambdas | ✅ | Anonymous functions with `Function(...) [As Type] => expr` lowering to internal functions & pointers |
| Pattern matching (`Match ... End Match`) | ✅ | Full algebraic pattern matching with `Ok(v)`, `Err(e)`, ranges `min To max`, values, and wildcards |
| Async / Await | ⏳ Future Roadmap | Coroutine transformation pipelines for cooperative multitasking. |
| Interfaces / Traits / Protocols | ✅ | `Interface ... End Interface`, `Implements` contracts & vtable definitions |
| Delegates / Function Pointer Types | ✅ | `Public Delegate Sub/Function Name(...)` lowering to typed function pointers |
| Class Instancing Models | ✅ | `<Instancing(Global/SingleUse/MultiUse)>` with stack/heap allocation & lifecycle checks |
| Compile-Time Layout Intrinsics | ✅ | `SizeOf(Type)` and `OffsetOf(Struct, Field)` compile-time layout evaluations |
| Operator overloading | ⏳ Future Roadmap | Custom user-defined operators (`+`, `-`, `*`). |
| Iterators / Generators (`Yield`) | ⏳ Future Roadmap | Generator coroutines for lazy sequences. |
| Namespaces / Module nesting | ✅ | `Namespace Name ... End Namespace` hierarchical scope organization with dotted symbol normalization |
| Compile-time evaluation (`Const` expressions) | ✅ | Compile-time constant evaluation in preprocessor |
| Conditional compilation (`#If`, `#Else`, `#End If`) | ✅ | Full preprocessor directives (`#Const`, `#If`, `#ElseIf`, `#Else`, `#End If`) with `-D` flags |
| Attributes / Annotations beyond `<Packed>` | ✅ | `<Inline>` (AlwaysInline), `<NoReturn>`, `<Export>`, `<Packed>`, `<Align(N)>` |
| Result / Error return types | ✅ | Native `Result` sum type `{ is_ok, err_code, value }` with `Ok(val)`, `Err(code)`, and `IsOk(res)` intrinsics |
| Bitfield structure fields (`Field As Type * Bits`) | ⏳ Future Roadmap | Hardware register bitfield packing syntax matching classic VB fixed-length string/field style |
| Compile-time `SizeOf` & `OffsetOf` intrinsics | ⏳ Future Roadmap | Zero-overhead compile-time layout queries (`SizeOf(T)`, `OffsetOf(T, Field)`) |
| Interrupt procedure attribute (`<Interrupt>`) | ⏳ Future Roadmap | Native ISR procedures compiling to LLVM `x86_intr` with automatic register preservation and `iretq` |
| Compile-time static assertions (`#Assert` / `StaticAssert`) | ⏳ Future Roadmap | Validation of structure alignment and constant invariants at compile-time |
| Flat binary output (`-O binary` / `Type = "RawBinary"`) | ⏳ Future Roadmap | Direct generation of raw `.bin` kernel images and bootloader sectors |

---

## H. Modern Compiler Alignment: Compile-Time Safety & Diagnostics Guards

Comprehensive comparison of compile-time verification in LLB against modern systems compilers (Rust `rustc`, Zig, Clang):

### 1. Declaration & Symbol Resolution Guards

| Guard Description | Current `llbc` Status | Behavior in `llbc` | Modern Compiler Equivalent (`rustc` / Clang) |
| :--- | :---: | :--- | :--- |
| **Undeclared Variable Access** | ✅ Implemented | Reports compile error with file, line, column caret | `rustc` `cannot find value in this scope` (E0425) |
| **Undeclared Function / Subroutine Call** | ✅ Implemented | Reports compile-time error with line and column caret; preserves indirect calls and delegate pointers | `rustc` `cannot find function in this scope` (E0425) |
| **Undeclared Method on Instance** (`obj.Foo()`) | ✅ Implemented | Rejects calls to unknown methods on instance with compile-time error | `rustc` `no method named on type` (E0599) |
| **Undeclared Class in `New ClassName`** | ✅ Implemented | Rejects unknown class name with compile error instead of silent `malloc(64)` | `rustc` `cannot find struct or type in this scope` (E0422) |
| **Undeclared Type in `Dim x As T` / Params** | ✅ Implemented | Rejects undeclared types in variables, fields, and parameters with compile error | `rustc` `cannot find type in this scope` (E0412) |
| **Missing Module / Import File** | ✅ Implemented | Driver halts compilation and reports missing imported file path | `rustc` `file not found for module` (E0583) |
| **Undeclared Interface in `Implements`** | ✅ Implemented | Rejects undeclared interface names in `Implements` declarations | `rustc` `cannot find trait in this scope` (E0405) |
| **Duplicate Variable in Same Local Scope** | ✅ Implemented | Rejects duplicate `Dim` declaration in the same local procedure scope | `rustc` `the name is defined multiple times` (E0428) |
| **Duplicate Procedure in Same Module** | ✅ Implemented | Rejects duplicate procedure definitions with clean compile-time error | `rustc` `duplicate definition of item` (E0428) |
| **Duplicate Field in `Structure`** | ✅ Implemented | Rejects duplicate field names in structures and unions | `rustc` `field is already declared` (E0124) |
| **Duplicate Enum Member Constant** | ✅ Implemented | Rejects duplicate member names within enum declarations | `rustc` `discriminant value is already defined` |
| **Undefined Label in `GoTo Label`** | ✅ Implemented | Tracks and validates label references in procedure, rejecting undefined labels with caret diagnostic | `clang` `use of undeclared label` |

### 2. Type Checking, Safety & Mutability Guards

| Guard Description | Current `llbc` Status | Behavior in `llbc` | Modern Compiler Equivalent (`rustc` / Clang) |
| :--- | :---: | :--- | :--- |
| **String Intrinsics Type Mismatch** (`Trim(123)`) | ✅ Implemented | Reports explicit compile error requiring `CStr()`/`Str()` | `rustc` `mismatched types` (E0308) |
| **Non-Existent Member / Field Access** (`pt.Z`) | ✅ Implemented | Reports compile-time error with line and column caret when member does not exist | `rustc` `no field on type` (E0609) |
| **`Const` Re-assignment Guard** | ✅ Implemented | Rejects assignment to constants (`Cannot assign to constant 'X'`) | `rustc` `cannot assign to immutable variable` (E0384) |
| **SingleUse Class Multiple Instantiation** | ✅ Implemented | Rejection test: throws error if instantiated more than once | `rustc` Singleton / OnceCell invariants |
| **Uninitialized Object Method Call** | ✅ Implemented | Rejection test: throws error if method called prior to `.Initialize` | `rustc` `use of uninitialized value` (E0381) |
| **Missing `<Instancing(...)>` on Class** | ✅ Implemented | Rejection test: enforces Global/SingleUse/MultiUse attribute | `rustc` Attribute validation |
| **Duplicate `New` in `Use` Statement** | ✅ Implemented | Rejection test: rejects `Use New ... As New ...` | `rustc` Syntax redundancy rejection |
| **Strict `Unsafe` Enforcement** | ✅ Implemented | Enforces `Unsafe` declaration on procedures containing `CPtr`, `Asm`, and raw pointer dereferences | `rustc` `call to unsafe function requires unsafe block` |
| **Private Member Access from Outside** | ✅ Implemented | Enforces visibility checks, rejecting access to `Private` fields from outside enclosing class or module | `rustc` `field is private` (E0616) |

### 3. Arithmetic & Evaluation Guards

| Guard Description | Current `llbc` Status | Behavior in `llbc` | Modern Compiler Equivalent (`rustc` / Clang) |
| :--- | :---: | :--- | :--- |
| **Constant Integer Overflow on `Dim`/`Const`/Assign** | ✅ Implemented | Rejects literals exceeding range (e.g. `Byte = 300`) | `rustc` `overflowing_literals`, `clang -Woverflow` |
| **Compile-Time Division by Zero** (`10 / 0`) | ✅ Implemented | Rejects constant integer division and modulo by 0 at compile time | `rustc` `attempt to divide by zero` (E0080) |
| **Shift Count Out of Range** (`x LShift 64`) | ✅ Implemented | Rejects shift count `< 0` or `>= bitWidth` at compile time | `rustc` `exceeding_bitshifts` |
| **Constant Out-of-Bounds Array Indexing** | ✅ Implemented | Rejects constant index out of bounds for fixed-size arrays on read and write | `rustc` `index out of bounds` (E0080) |

### 4. Control Flow & Interface Guards

| Guard Description | Current `llbc` Status | Behavior in `llbc` | Modern Compiler Equivalent (`rustc` / Clang) |
| :--- | :---: | :--- | :--- |
| **Call Argument Count Mismatch (Arity)** | ✅ Implemented | Validates exact parameter count before emitting call, reporting clear error diagnostic | `rustc` `takes N arguments but M were supplied` (E0061) |
| **Missing Interface Method Implementation** | ✅ Implemented | Validates that classes declaring `Implements Iface` implement all required methods | `rustc` `not all trait items implemented` (E0046) |
| **Loop Exit Outside of Loop** (`Exit For`/`Do`/`While`) | ✅ Implemented | Rejects `Exit For`, `Exit Do`, or `Exit While` outside their respective loop scopes | `rustc` `cannot break outside of loop` (E0268) |
| **Missing Return Value on Function Exit** | ✅ Implemented | Enforces assignment to function name before exit in non-void Functions | `rustc` `mismatched types / expected return value` |
| **Unreachable / Dead Code Detection** | ⏳ In Progress | Statements after `Return`, `Exit`, or `Raise` emit unchecked IR | `rustc` `unreachable_code`, `clang -Wunreachable-code` |
| **Enum / Result Exhaustiveness in `Match`** | ⏳ In Progress | Unhandled match arms fall through to runtime null | `rustc` `non-exhaustive patterns` (E0004) |

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

### Phase 2: Standard Library & Runtime — COMPLETE ✅
8. ~~String library (`Len`, `Mid`, `Left`, `Right`, `InStr`, `Trim`, `Asc`, `Chr`)~~ — **Done** ✅
9. ~~Type conversion functions (`CStr`, `CInt`, `CLng`, `CDbl`, `Val`)~~ — **Done** ✅
10. ~~Console I/O (`Print`, `Input`)~~ — **Done** ✅
11. ~~File I/O (`Open`, `Close`, `Print #`, `Line Input #`, `EOF`, `LOF`)~~ — **Done** ✅

### Phase 3: Toolchain Hardening — COMPLETE ✅
12. ~~LLVM optimization passes (`-O1`, `-O2`, `-O3` via PassBuilder)~~ — **Done** ✅
13. ~~Debug info emission (DWARF `-g`)~~ — **Done** ✅
14. ~~`Import` / module dependency resolution~~ — **Done** ✅
15. ~~Static library output (`.a`)~~ — **Done** ✅
16. ~~Conditional compilation (`#If`)~~ — **Done** ✅

### Phase 4: Modern Language Power — COMPLETE ✅
17. ~~`New` / `Delete` + heap object lifecycle~~ — **Done** ✅
18. ~~Interfaces / Traits / Protocols~~ — **Done** ✅
19. ~~Generics / Parameterized Templates (`Structure Box(Of T)`, `Function Min(Of T)`)~~ — **Done** ✅
20. ~~First-class function pointers / `AddressOf`~~ — **Done** ✅
21. ~~First-class closures / lambdas~~ — **Done** ✅
22. ~~Result / Error sum types (`Result`, `Ok`, `Err`)~~ — **Done** ✅
23. ~~Namespaces / Module nesting (`Namespace ... End Namespace`)~~ — **Done** ✅
24. ~~VB6 `Err` Object Runtime (`Err.Number`, `Err.Description`, `Err.Source`, `Err.Clear`, `Err.Raise`)~~ — **Done** ✅
25. ~~Toolchain CLI Cross-Compilation (`--target=<triple>`, `--nostdlib`, `--sysroot`)~~ — **Done** ✅
26. ~~Deterministic Scoped Cleanup (`Using ... End Using`)~~ — **Done** ✅
27. ~~Algebraic Pattern Matching (`Match ... Case ... End Match`)~~ — **Done** ✅
28. ~~Self-Hosting Bootstrap: `stage1` Compiler Architecture (`src/stage1/`, `llbc.llbproj`)~~ — **Done** ✅
29. ~~`Use` Statement — Scoped Binding, Aliasing & Compile-Time Class Instancing (`<Instancing(MultiUse/SingleUse/Global)>`, duplicate `New` rejection, uninitialized-access rejection)~~ — **Done** ✅

---

### Phase 5: Bare-Metal Systems & Toolchain Enhancements (VB6-Idiomatic)

1. **Bitfield Structure Declarations (VB6 Fixed-Length Style):**
   - Syntax:
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
         Public Reserved As Byte * 4
         Public FrameAddress As UInt64 * 52
     End Structure
     ```
   - Matches classic VB fixed-length syntax (`Dim s As String * 30`), making bitfields clean and natural to read.

2. **Compile-Time Size & Offset Intrinsics (`SizeOf` / `OffsetOf`):**
   - Syntax:
     ```vb
     Dim structSize As UInt64 = SizeOf(IdtEntry)
     Dim fieldOffset As UInt64 = OffsetOf(IdtEntry, BaseHigh)
     ```

3. **Interrupt Handler Procedures (`<Interrupt>` Attribute):**
   - Syntax:
     ```vb
     <Interrupt>
     Public Unsafe Sub KeyboardInterruptHandler(ByVal frame As Pointer To InterruptStackFrame)
         ' LLVM x86_intr calling convention automatically preserves all registers and emits iretq
         Drivers.Keyboard.HandleScancode
     End Sub
     ```

4. **Compile-Time Static Assertions (`#Assert` Directive):**
   - Syntax:
     ```vb
     #Assert SizeOf(IdtEntry) = 16, "IdtEntry must be exactly 16 bytes on x86_64"
     #Assert SizeOf(GdtDescriptor) = 8, "GDT segment descriptor size mismatch"
     ```

5. ~~Direct Flat Binary Output (`-O binary` / `Type = "RawBinary"`)~~ — **Done** ✅

---

### Phase 6: Temporary Discussion & Review Roadmap (For Next Review)

1. **Standard Library Packaging Model:**
   - Precompiled static standard library (`libllb_std.a`) vs source module tree (`Import Std.Collections`).
2. **Self-Hosting Stage-1 Full Monomorphization & Lowering:**
   - Complete AST lowering from `src/stage1/Parser.cls` to `src/stage1/LlvmC.bas` to allow compiling `llbc` without C++ stage-0.
3. **Cross-Compilation Hardware Presets:**
   - Bundled target architectures (`x86_64-kernel`, `aarch64-rpi4`, `riscv64-virt`) in `.llbproj`.
4. **Standard String & Type Inspection Intrinsics:**
   - Built-in freestanding runtime helpers (`IsNumericString(s)`, `IsAlpha(s)`, `IsWhitespace(s)`).




