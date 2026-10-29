# Low-Level Basic Self-Hosted Compiler (`llbc-stage1`)

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0-blue.svg)](LICENSE.md)
[![Language: Low-Level Basic](https://img.shields.io/badge/Language-Low--Level%20Basic%20(LLB)-informational.svg)](https://github.com/karunci/LLB)
[![Stage: Self-Hosting](https://img.shields.io/badge/Stage-1%20Self--Hosted-purple.svg)](docs/STAGE1_SELFHOSTING_ROADMAP.md)
[![AI-Assisted](https://img.shields.io/badge/development-AI--assisted-purple.svg)](AI_DISCLOSURE.md)

> **`llbc-stage1`** is the pure Low-Level Basic implementation of the LLB compiler, written 100% in Low-Level Basic. It is designed to be compiled by the C++ bootstrap compiler (`llbc-stage0` on branch `main`), achieve full self-hosting parity, and run natively inside **PROS** at `/bin/llbc`.

---

## 🌐 Multi-Branch Ecosystem Navigation
The Low-Level Basic repository is organized across three dedicated parallel branches:

| Subsystem | Branch | Architecture & Responsibility | Remote Link |
| :--- | :--- | :--- | :--- |
| **Stage-0 Bootstrap Compiler** | `main` | C++ bootstrap compiler emitting LLVM IR for freestanding & hosted targets. | [**View Branch: `main`**](https://github.com/karunci/LLB/tree/main) |
| **Personal Research Operating System (PRK-OS)** | `pros` | Complete 64-bit microkernel, system daemons (`services/`), GUI apps (`apps/gui/`), and SDK (`lib/`). | [**View Branch: `pros`**](https://github.com/karunci/LLB/tree/pros) |
| **Stage-1 Self-Hosted Compiler** | `stage1` | Pure Low-Level Basic self-hosting compiler designed to run natively inside PROS. | *Active Branch* |

---

## 🏛️ Compiler Subsystem Architecture

The Stage-1 compiler pipeline is organized as modular, strongly-typed Low-Level Basic modules and classes:

```
+-----------------------------------------------------------------------------------+
|                         Stage-1 Pure LLB Compiler Pipeline                        |
|                                                                                   |
|  +--------------------+    +---------------------+    +------------------------+  |
|  |   .llbproj / Source|    | Pure LLB Lexer &    |    |  Pure LLB AST &        |  |
|  |   Parser Engine    | -> | Tokenizer           | -> |  Type Checking         |  |
|  | (CompilerMain.bas) |    |   (Lexer.cls)       |    |     (Ast.bas)          |  |
|  +--------------------+    +---------------------+    +------------------------+  |
|                                                                    |              |
|  +--------------------+    +---------------------+                 v              |
|  | Target Binary      |    | LLD Linker Driver   |    +------------------------+  |
|  |  (BAX / ELF / PE)  | <- |   (LlvmC.bas)       | <- |  LLVM IR Emission Engine|  |
|  +--------------------+    +---------------------+    |     (LlvmC.bas)        |  |
|                                                       +------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 📂 Source Code Layout

```text
llbc-stage1/
├── stage1.llbproj          # Root project manifest for the self-hosted compiler
├── src/                    # Pure Low-Level Basic compiler sources
│   ├── Ast.bas             # Abstract Syntax Tree structures, expressions, statements
│   ├── Lexer.cls           # Token scanner and lexical stream analyzer
│   ├── Parser.cls          # Recursive descent syntax parser
│   ├── LlvmC.bas           # LLVM-C API declarations, bindings, and IR generator
│   └── CompilerMain.bas    # Command-line driver and compilation orchestrator
│
├── include/                # Shared language and compiler definitions
├── lib/                    # Standard libraries and freestanding runtime
└── docs/                   # Self-hosting documentation
    ├── STAGE1_SELFHOSTING_ROADMAP.md  # LLVM-C Bindings & Bootstrap Milestone Matrix
    └── LANGUAGE_REFERENCE.md          # Formal Low-Level Basic Grammar & Syntax
```

---

## 🛠️ Building & Bootstrapping Stage-1

### 1. Build Stage-1 with Stage-0 (Bootstrap Pass)
Using the Stage-0 compiler (built from branch `main`):
```bash
# On Termux or Linux:
~/projects/LLB/llbc/build/llbc-stage0 stage1.llbproj -o build/llbc-stage1.elf

# Run stage-1 to print usage or compile a test project:
./build/llbc-stage1.elf --help
```

### 2. Self-Hosting Verification Cycle (Stage-2 Bootstrap)
Once all compiler passes are implemented:
```bash
# Compile Stage-1 using Stage-1 binary:
./build/llbc-stage1.elf stage1.llbproj -o build/llbc-stage2.elf

# Verify bit-for-bit object parity:
diff -s build/llbc-stage1.elf build/llbc-stage2.elf
```

---

## 📖 Documentation
- 🗺️ **[Stage-1 Self-Hosting Roadmap](docs/STAGE1_SELFHOSTING_ROADMAP.md)** — Architectural stages, AST layout, LLVM-C bindings, and verification milestones.
- 📕 **[Formal Language Reference](docs/LANGUAGE_REFERENCE.md)** — Complete Low-Level Basic syntax specification and memory model.
- 📜 **[Licensing](LICENSE.md)** — Mozilla Public License 2.0 (MPL-2.0).
