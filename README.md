# Low-Level Basic (LLB)

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0-blue.svg)](LICENSE.md)
[![Build Status](https://img.shields.io/badge/tests-69%2F69%20passed-brightgreen.svg)](tests/userland/TestSuite.bas)
[![LLVM Version](https://img.shields.io/badge/backend-LLVM%2021-red.svg)](CMakeLists.txt)
[![AI-Assisted](https://img.shields.io/badge/development-AI--assisted-purple.svg)](AI_DISCLOSURE.md)

> **Low-Level Basic (LLB)** is an Ahead-Of-Time (AOT) compiled systems programming language combining the safety guarantees and bare-metal performance of Rust and C/C++ with the clean, expressive, approachable syntax of Visual Basic 6.

---

## 🌐 Multi-Branch Ecosystem Navigation
The Low-Level Basic ecosystem is organized across three dedicated parallel branches:

| Subsystem | Branch | Architecture & Responsibility | Remote Link |
| :--- | :--- | :--- | :--- |
| **Stage-0 Bootstrap Compiler** | `main` | C++ bootstrap compiler emitting LLVM IR for freestanding & hosted targets. | *Active Branch* |
| **PROS Operating System** | `pros` | Complete 64-bit microkernel, system daemons (`services/`), GUI apps (`apps/gui/`), and SDK (`lib/`). | [**View Branch: `pros`**](https://github.com/karunci/LLB/tree/pros) |
| **Stage-1 Self-Hosted Compiler** | `stage1` | Pure Low-Level Basic self-hosting compiler designed to run natively inside PROS. | [**View Branch: `stage1`**](https://github.com/karunci/LLB/tree/stage1) |

---

## 💡 Why Low-Level Basic?

Modern systems programming languages often impose high cognitive burdens, steep learning curves, or complex syntax rules. Meanwhile, classic languages like Visual Basic 6 proved that software can be clear, readable, and rapid to construct — but were held back by runtime interpreters, OLE/COM overhead, and an inability to write bare-metal code.

**Low-Level Basic solves this dilemma:**
1. **Readable & Approachable:** Clear `Sub`, `Function`, `Module`, `Class`, `Select Case`, `With`, and `Print` statements without bracket clutter.
2. **True Bare-Metal Control:** Explicit pointer types (`Pointer To T`), MMIO-safe registers (`Volatile Pointer To T`), inline assembly (`Asm`), and byte-accurate struct alignment (`<Packed>`, `<Align(N)>`).
3. **Rust-Grade Safety Intent:** Bounds-checked arrays and null-pointer safety guards by default; explicit `Unsafe` context blocks required for raw memory addresses and physical pointer manipulation.
4. **Freestanding & Self-Contained:** Zero mandatory host C library runtime dependencies. Perfect for microkernels, OS kernels, bootloaders, firmware, and high-performance standalone utilities.
5. **Modern Language Power:** First-class generic templates (`Structure Box(Of T)`, `Function Min(Of T)`), pattern matching (`Match ... Case`), lambda expressions (`=>`), deterministic scoped cleanup (`Using ... End Using`), interfaces & vtables, and algebraic `Result(T, E)` error types.

---

## ⚡ Quick Sample Code

### 1. Interactive Application (FFI & Console)
```vb
Module Main
    Declare Function printf Lib "c" (ByVal format As Pointer To Byte, ByVal arg As Int32) As Int32

    Public Sub MainEntry()
        Dim answer As Int32 = 42
        Dim status As String = "Ready"

        ' First-class VB6-style string concatenation with auto-conversion
        PrintLine "System status: " & status & ", Code: " & answer

        ' Direct FFI call with C calling convention
        printf("Formatted output: %d" & Chr(10), answer)
    End Sub
End Module
```

### 2. Bare-Metal Kernel Hardware Driver (VGA Buffer)
```vb
Class Drivers.Terminal
    Private Const VGA_ADDRESS As UInt64 = &HB8000
    Private buffer As Volatile Pointer To UInt16

    Public Unsafe Sub Initialize()
        ' Explicit cast to MMIO volatile pointer using pure LLB constructor syntax
        Me.buffer = Pointer To UInt16(VGA_ADDRESS)
        ' Write colored ASCII character ('A', Green on Black)
        Me.buffer(0) = &H0A41
    End Sub
End Class
```

### 3. Generic Templates & Pattern Matching
```vb
Public Structure Box(Of T)
    Public Value As T
End Structure

Public Function CheckResult(ByVal res As Result) As String
    Match res
        Case Ok(val)
            CheckResult = "Success: " & val
        Case Err(code)
            CheckResult = "Error code: " & code
        Case Else
            CheckResult = "Unknown"
    End Match
End Function
```

### 4. Structured Error Handling & Freestanding Exceptions (`Try ... Catch ... Finally`)
```vb
Public Sub ExecuteTask(ByVal taskId As Int32)
    Try
        If taskId < 0 Then
            ' Raise standard VB6-compatible error without CRT dependency
            Err.Raise 1001, "TaskScheduler", "Invalid negative task ID"
        End If
        PrintLine "Executing task #" & taskId
    Catch
        ' Freestanding Err object provides rich diagnostic info
        PrintLine "Error #" & Err.Number & " in " & Err.Source & ": " & Err.Description
        Err.Clear
    Finally
        ' Cleanup logic executes unconditionally
        PrintLine "Task execution block completed."
    End Try
End Sub
```

### 5. Deterministic Scoped Cleanup (`Using ... End Using`)
```vb
Class MutexGuard
    Public Locked As Boolean

    Public Sub Dispose()
        If Me.Locked Then
            PrintLine "Releasing spinlock..."
            Me.Locked = False
        End If
    End Sub
End Class

Public Sub CriticalSection()
    Dim guard As MutexGuard
    guard.Locked = True

    Using guard
        PrintLine "Inside atomic critical section"
        ' guard.Dispose() is guaranteed to execute upon leaving block
    End Using
End Sub
```

### 6. Modern First-Class Lambdas (`=>`) & Functional Pointers
```vb
Public Sub RunFilter()
    ' Concisely define inline lambdas lowering to LLVM functions
    Dim isEven As Pointer
    isEven = Function(x As Int32) As Boolean => (x Mod 2) = 0

    ' Dynamic array with bounds safety
    Dim nums(4) As Int32
    nums(0) = 10 : nums(1) = 15 : nums(2) = 20 : nums(3) = 25 : nums(4) = 30

    Dim i As Int32
    For i = 0 To UBound(nums)
        If isEven(nums(i)) Then
            PrintLine "Even number: " & nums(i)
        End If
    Next i
End Sub
```

### 7. `Use` Statement — Scoped Binding, Aliasing & Class Instancing
```vb
' Import a MultiUse class and create independent, scoped instances
Module Demo
    Use ClassHelper In "ClassHelper.cls" As Helper

    Public Sub Run()
        ' Instantiate two independent value instances within scope
        Use New Helper As h1
        Use New Helper As h2

        h1.Initialize 10     ' h1.m_val = 10
        h2.Initialize 5      ' h2.m_val = 5  (fully independent)

        PrintLine "h1 sum: " & h1.ComputeSum(3)   ' => 13
        PrintLine "h2 sum: " & h2.ComputeSum(7)   ' => 12
    End Sub
End Module

' SingleUse class — compiler enforces exactly one instance per scope
<Instancing(SingleUse)>
Class Logger
    Public Sub Initialize(ByVal level As Int32)
        ' ...
    End Sub
End Class
```

---



## 🛠️ Toolchain Usage

The compiler driver `llbc-stage0` compiles single files or `.llbproj` project manifests directly into native ELF/PE binaries. All build artifacts are emitted into the `build/` directory.

```bash
# 1. Compile and link a standalone application
./build/llbc-stage0 app.bas -o build/app

# 2. Build the comprehensive test suite via project manifest
./build/llbc-stage0 tests/userland/TestSuite.llbproj

# 3. For OS microkernel and system daemons, switch to the 'pros' branch:
# git checkout pros (or cd ../pros in worktree setup)

# 4. Cross-compile for freestanding x86_64
./build/llbc-stage0 kernel.bas --target=x86_64-unknown-none-elf --nostdlib -o build/kernel.elf
```

---

## 🔧 Building from Source

### Primary Build Environment

This project is primarily developed and compiled on **Termux (Android)** using the following toolchain:

| Component | Version |
|-----------|---------|
| Platform  | Termux on Android (AArch64) |
| Compiler  | Clang / Clang++ |
| Build system | CMake + Make |
| Backend  | LLVM 21 + LLD |

```bash
# Termux packages
pkg install clang llvm lld cmake make
```

### Building on Other Host Systems

> [!IMPORTANT]
> CMake requires **both C and C++** languages to be enabled (for LLVM's internal `FindLibEdit` probe). This is already set correctly in `CMakeLists.txt` — if you hit the `"Unknown extension .c"` error, make sure you are using the latest `CMakeLists.txt` from this repo.

#### Debian / Ubuntu
```bash
sudo apt install build-essential cmake clang llvm-dev liblld-dev libedit-dev
```

#### Arch Linux
```bash
sudo pacman -S base-devel cmake clang llvm lld libedit
```

#### Fedora / RHEL
```bash
sudo dnf install gcc gcc-c++ cmake clang llvm-devel lld libedit-devel
```

#### macOS (Homebrew)
```bash
brew install cmake llvm lld libedit
# Homebrew LLVM is keg-only; point CMake to it:
export PATH="$(brew --prefix llvm)/bin:$PATH"
export LDFLAGS="-L$(brew --prefix llvm)/lib"
export CPPFLAGS="-I$(brew --prefix llvm)/include"
```

#### NixOS / nix-shell
```bash
nix-shell -p cmake clang llvm lld libedit
```

### Build Steps (all platforms)
```bash
git clone https://github.com/karunci/LLB.git
cd LLB

mkdir build && cd build
cmake ..
cmake --build . -j$(nproc)

# Run the 69-suite test verification:
ctest --test-dir . --output-on-failure
```

---

## 📖 Complete Documentation

Comprehensive compiler documentation, full language grammar, type specifications, and compiler roadmap:

- 📕 **[Formal Language Reference Manual](docs/LANGUAGE_REFERENCE.md)** — Exhaustive 28-section language specification including grammar, layout intrinsics, interrupt handlers, and static assertions.
- 🗺️ **[Compiler Feature & Codegen Roadmap](docs/LLBC_ROADMAP.md)** — Stage-0 compiler features, LLVM IR emitter optimizations, and test standards.
- 🤝 **[Contributing Guidelines](docs/CONTRIBUTING.md)** — Compiler contribution protocols, test suite requirements, and patch author standards.
- 📜 **[Licensing & AI Ingestion Restrictions](LICENSE.md)** — Dual-license terms (MPL-2.0 and AI training prohibitions).

---

## ⚖️ License

Low-Level Basic Compiler (`llbc`) is dual-licensed under:
1. **Mozilla Public License, Version 2.0 (MPL-2.0)** — See [`docs/LICENSE.md`](docs/LICENSE.md).
2. **Artificial Intelligence (AI) and Machine Learning (ML) Data Mining Restriction** — Explicitly prohibiting unauthorized automated scraping, training, or fine-tuning of machine learning models. See [`LICENSE.md`](LICENSE.md).
