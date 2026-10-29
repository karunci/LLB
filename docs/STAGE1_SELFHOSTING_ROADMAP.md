# Stage-1 Self-Hosting Compiler Roadmap (`llbc-stage1`)

This document outlines the architectural roadmap and milestone verification criteria for the pure **Low-Level Basic (LLB)** self-hosted compiler (`llbc-stage1`), designed to run natively inside **PROS** at `/bin/llbc`.

---

## 🎯 Architecture & Objectives

The goal of `stage1` is to provide a completely self-contained, self-hosting Low-Level Basic compiler written 100% in Low-Level Basic itself, eliminating any long-term dependency on C++ or GCC/Clang host toolchains.

```
+-----------------------------------------------------------------------------------+
|                         Stage-1 Pure LLB Compiler Pipeline                        |
|                                                                                   |
|  +--------------------+    +---------------------+    +------------------------+  |
|  |   .llbproj / Source|    | Pure LLB Lexer &    |    |  Pure LLB AST &        |  |
|  |   Parser (Lexer.cls| -> | Parser (Parser.cls) | -> |  Type Checker (Ast.bas)|  |
|  +--------------------+    +---------------------+    +------------------------+  |
|                                                                    |              |
|  +--------------------+    +---------------------+                 v              |
|  | Target Executable  |    | LLD Linker Binding  |    +------------------------+  |
|  |  (BAX / ELF64)     | <- | (LlvmC.bas Linker)  | <- |  LLVM-C API Generator |  |
|  +--------------------+    +---------------------+    |     (LlvmC.bas IR)     |  |
|                                                       +------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 🗺️ Milestone Matrix

| Milestone | Subsystem | Focus & Key Deliverables | Status |
| :--- | :--- | :--- | :---: |
| **M1: Source Isolation** | Worktree & Manifest | Promote `src/stage1/*` to top-level `src/`, configure root `stage1.llbproj`. | **COMPLETED** |
| **M2: Lexer & Tokenizer** | `Lexer.cls` | Full lexical grammar: identifiers, keywords, numeric literals (hex/oct/bin), strings with escape characters, and source locations. | **IN PROGRESS** |
| **M3: AST & Types** | `Ast.bas` | Low-level Basic AST node hierarchy: `AstNode`, `AstExpr`, `AstStmt`, `AstDecl`, `AstTypeInfo`. Pointer peeling and sized struct layouts. | **IN PROGRESS** |
| **M4: Recursive Descent Parser** | `Parser.cls` | Modules, Classes, Functions, Subs, Structures, Enums, TypeAliases, `Select Case`, `If...Else`, `For...Next`, `While...Wend`, `With`, inline assembly (`Asm`). | **IN PROGRESS** |
| **M5: LLVM-C Bindings** | `LlvmC.bas` | Complete FFI bindings to `libLLVM.so` / `libLLVM.a` C API: Context, Module, Builder, Types, Values, BasicBlocks, and PassManager. | **IN PROGRESS** |
| **M6: Self-Compilation Pass** | Stage-0 Bootstrapping | Successfully compile `stage1.llbproj` using `llbc-stage0` into native host binary `stage1-bin`. | **PLANNED** |
| **M7: Self-Hosting Verification** | Stage-1 Self-Compiling | `stage1-bin stage1.llbproj -o stage2-bin`; verify `stage1-bin` and `stage2-bin` generate bit-for-bit identical object code. | **PLANNED** |
| **M8: Native PROS Integration** | `/bin/llbc` in PROS | Port `stage1` into PROS userspace using `lib/pros`, packaging as `/bin/llbc.bax` on the USTAR ramdisk for self-contained OS programming. | **PLANNED** |

---

## 🛠️ Verification & Build Commands

### Compiling Stage-1 with Stage-0 Bootstrap Compiler:
```bash
# From workspace root on Termux or Linux:
~/projects/LLB/llbc/build/llbc-stage0 stage1.llbproj -o build/llbc-stage1.elf
```

### Pure LLB Idioms & Standards:
- All source files must adhere strictly to pure LLB syntax:
  - Use prefix dereference/cast syntax (`*TypeName(addr)`) or constructor syntax (`Pointer To T(expr)`).
  - No legacy `CPtr(...)` usage.
  - Return typed pointers directly from functions (`Function (...) As Pointer To T`).
  - Zero dynamic heap allocation during AST parsing: use pooled ring or bump allocators.
