/*
 * Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/AsmCompiler.hpp
 * Workspace Path: src/codegen/AsmCompiler.hpp
 * Summary: Integrated GNU Assembly (.S) parser and object compiler using LLVM MC.
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