/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/TargetEmitter.hpp
 * Summary: Target Machine object generator and embedded LLD linker wrapper.
 */

#ifndef LLBC_TARGET_EMITTER_HPP
#define LLBC_TARGET_EMITTER_HPP

#include <llvm/IR/Module.h>
#include <llvm/TargetParser/Triple.h>
#include <llvm/TargetParser/Host.h>
#include <string>
#include <vector>

namespace llbc {

struct TargetConfig {
    // Dynamically detect the host OS and CPU architecture (e.g., aarch64-linux-android)
    std::string targetTriple{llvm::sys::getDefaultTargetTriple()};
    std::string cpu{"generic"};
    std::string features{""};
    bool isBareMetal{false};
};

class TargetEmitter {
public:
    explicit TargetEmitter(TargetConfig config = TargetConfig());

    bool emitObjectFile(llvm::Module* module, const std::string& outputFilename);

    static bool linkExecutable(
        const std::vector<std::string>& objectFiles,
        const std::string& outputFile,
        const std::string& linkerScript = ""
    );

private:
    TargetConfig m_config;
};

} // namespace llbc

#endif // LLBC_TARGET_EMITTER_HPP