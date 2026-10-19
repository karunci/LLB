# Low-Level Basic (LLB)

[![License: MPL-2.0](https://img.shields.io/badge/License-MPL_2.0-blue.svg)](LICENSE.md)
[![Build Status](https://img.shields.io/badge/tests-59%2F59%20passed-brightgreen.svg)](#)
[![LLVM Version](https://img.shields.io/badge/backend-LLVM%2019-red.svg)](#)

> **Low-Level Basic (LLB)** is an Ahead-Of-Time (AOT) compiled systems programming language combining the safety guarantees and bare-metal performance of Rust and C/C++ with the clean, expressive, approachable syntax of Visual Basic 6.

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
        printf(CPtr(Pointer To Byte, "Formatted output: %d" & Chr(10)), answer)
    End Sub
End Module
```

### 2. Bare-Metal Kernel Hardware Driver (VGA Buffer)
```vb
Class Drivers.Terminal
    Private Const VGA_ADDRESS As UInt64 = &HB8000
    Private buffer As Volatile Pointer To UInt16

    Public Unsafe Sub Initialize()
        ' Explicit cast to MMIO volatile pointer
        Me.buffer = CPtr(Volatile Pointer To UInt16, VGA_ADDRESS)
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

---

## 🛠️ Toolchain Usage

The compiler driver `llbc-stage0` compiles single files or `.llbproj` project manifests directly into native ELF/PE binaries:

```bash
# 1. Compile and link a standalone application
./build/llbc-stage0 app.bas -o app

# 2. Build a full bare-metal OS kernel via project manifest
./build/llbc-stage0 tests/kernel/Kernel.llbproj

# 3. Cross-compile for bare-metal x86_64 or AArch64
./build/llbc-stage0 kernel.bas --target=x86_64-unknown-none-elf --nostdlib -o kernel.elf
```

---

## 📖 Complete Documentation

Comprehensive documentation, full language grammar, type specifications, FFI rules, and bare-metal kernel references are available in the [`docs/`](docs/) directory:

- 📘 **[Full Language & Architecture Documentation](docs/README.md)** — In-depth guide covering all keywords, syntax, generics, memory models, attributes, runtime libraries, and project manifests.
- 🗺️ **[Feature Parity & Implementation Roadmap](docs/LLB_FEATURES_ROADMAPS.md)** — Complete audit of VB6 compatibility, modern extensions, and current compiler status.
- 📜 **[Licensing & AI Ingestion Restrictions](LICENSE.md)** — Dual-license terms (MPL-2.0 and AI training prohibitions).

---

## ⚖️ License

Low-Level Basic Compiler (`llbc`) is dual-licensed under:
1. **Mozilla Public License, Version 2.0 (MPL-2.0)** — See [`docs/LICENSE.md`](docs/LICENSE.md).
2. **Artificial Intelligence (AI) and Machine Learning (ML) Data Mining Restriction** — Explicitly prohibiting unauthorized automated scraping, training, or fine-tuning of machine learning models. See [`LICENSE.md`](LICENSE.md).
