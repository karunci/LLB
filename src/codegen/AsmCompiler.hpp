/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#ifndef LLBC_ASM_COMPILER_HPP
#define LLBC_ASM_COMPILER_HPP

#include <string>

namespace llbc {

class AsmCompiler {
public:
    // Compiles a raw GNU assembly (.S) file directly into a native object file (.o)
    static bool compileAssemblyFile(
        const std::string& asmFilePath,
        const std::string& outputObjPath,
        const std::string& targetTriple = "x86_64-unknown-none-elf"
    );
};

} // namespace llbc

#endif // LLBC_ASM_COMPILER_HPP