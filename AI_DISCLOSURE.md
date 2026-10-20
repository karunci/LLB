# AI Disclosure & Development Methodology

Low-Level Basic (`LLB` / `llbc`) is engineered using an AI-assisted pair-programming methodology. This document transparently outlines the development model, division of responsibilities, and quality verification standards governing the codebase.

---

## 1. Division of Responsibilities

### Human Architect & Lead Developer
- **Language Design & Semantics:** Defined the grammar, keywords, microkernel architecture, type-system rules, memory safety invariants, and standard library primitives.
- **Architectural Decision-Making:** Dictated technical direction, toolchain integration strategies (LLVM / LLD), and bare-metal target boundaries (Multiboot2, VGA buffers, IDT descriptors).
- **Quality Assurance & Verification:** Reviewed every generated diff, validated compiler logic, orchestrated integration testing in QEMU and Termux, and directed regression benchmarks.

### AI Pair Programmer
- **Code Scaffolding & AST Generation:** Implemented AST nodes, frontend parser grammar rules, and lexer token dispatchers based on specifications provided by the architect.
- **LLVM IR Code Generation:** Assisted in translating AST expressions into LLVM IR builders, instruction emission routines, and linking driver pipelines.
- **Test Suite Construction:** Authored repetitive regression fixtures, parser rejection unit tests, and comprehensive edge-case suites under the direction of the human lead.
- **Documentation & Refactoring:** Generated structured documentation tables, architectural summaries, and targeted code refactorings across the codebase.

---

## 2. Verification & Zero-Hallucination Standard

Every line of code and feature in LLB is subjected to rigorous, deterministic verification:

1. **Bare-Metal Kernel Execution:** The generated freestanding kernel is booted directly in QEMU (`x86_64`) under both Multiboot1 and Multiboot2, validating real hardware initialization, VGA memory-mapped I/O (`0xB8000`), IDT interrupt tables, and CPU halt sequences.
2. **Automated Userland Test Suite:** The userland test suite compiles and runs 63 comprehensive test suites covering arithmetic, strings, memory buffers, dynamic arrays, pattern matching, lambdas, OOP lifecycle, and static library archiving.
3. **Compiler Rejection Tests:** Negative test fixtures verify that syntax violations, uninitialized object usage, and illegal instantiations are cleanly rejected at compile time.
4. **Independent Reproducibility:** The entire toolchain can be built and verified independently using standard CMake and LLVM/Clang toolchains without reliance on AI services.

---

## 3. Intellectual Property & Licensing Clarification

- **License:** Low-Level Basic is dual-licensed under the **Mozilla Public License 2.0 (MPL-2.0)** and custom AI Ingestion Restrictions. See [LICENSE.md](LICENSE.md) for full terms.
- **Original Authorship:** The copyright and architectural ownership reside with the project creator (`karunci`).
- **AI Ingestion Prohibition:** Consistent with the project's header notices, automated scraping, ingestion, and training of this repository's codebase for third-party artificial intelligence or machine learning model training without explicit written consent is strictly prohibited.
