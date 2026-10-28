# Low-Level Basic Compiler & Language Roadmap (`LLBC_ROADMAP`)

> **Compiler Toolchain:** `llbc-stage0` (LLVM 21 Backend, embedded LLD linker)  
> **Source Directory:** `src/`  
> **Full Feature Matrix:** See [`archive/LLB_FEATURES_ROADMAPS.md`](archive/LLB_FEATURES_ROADMAPS.md)  
> **Language Reference:** See [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md)  

---

## 1. Executive Summary

Low-Level Basic (LLB) combines the safety and performance of modern systems languages (Rust memory guarantees, C/C++ hardware control and pointer arithmetic) with the clean, human-readable syntax of Visual Basic 6.

The self-hosting compiler driver (`llbc`) executes frontend lexical analysis, AST parsing, LLVM IR emission, and direct in-process LLD linking into freestanding ELF64, PE32+, or raw binary images.

---

## 2. Compiler Subsystem Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                          LLBC Compiler Driver                          │
├────────────────────┬────────────────────┬──────────────────────────────┤
│ Frontend Engine    │ IR Codegen         │ In-Process Linker            │
│ (src/frontend/)    │ (src/codegen/)     │ (embedded LLD)               │
│ • Manifest Parser  │ • LLVM 21 Emitter  │ • ELF64, PE32+ linker        │
│ • Lexer & Parser   │ • Type Inference   │ • Freestanding linker script │
│ • AST Symbol Table │ • NoRedZone attrs  │ • Zero external dependencies │
└────────────────────┴────────────────────┴──────────────────────────────┘
```

---

## 3. High-Priority Compiler Milestones

### 3.1 String Type Coercion & Interoperability
- [x] Native `String` primitive mapped to LLVM `ptr`.
- [x] String concatenation (`&`, `+`) and equality comparison (`=`, `<>`).
- [ ] Seamless parameter coercion: Allow passing `String` literals directly to functions expecting `Pointer To Byte` or `Pointer To CChar` without requiring explicit `CPtr(...)`.
- [ ] String interpolation syntax (e.g. `$"PID: {pid}"`).

### 3.2 Dynamic Library Generation (`.bdl` Target)
- [ ] Add `-shared` / `-bdl` output target mode in `llbc`.
- [ ] Generate position-independent code (`-fPIC`) for shared libraries.
- [ ] Emit `.bdl` export tables and dynamic relocation sections.

### 3.3 Enhanced Type System & Diagnostics
- [ ] User-defined `Enum` underlying type specifications (`Enum Foo As UInt16`).
- [ ] Enhanced struct field initialization defaults.
- [ ] Improved compile-time error reporting with source line highlights.

