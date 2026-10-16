/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/TargetEmitter.cpp
 * Summary: Emits native object code and interfaces with embedded LLD driver.
 */

#include "TargetEmitter.hpp"
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/TargetParser/Triple.h>

#include <lld/Common/Driver.h>
#include <lld/Common/ErrorHandler.h>

#include <iostream>
#include <cstdlib>

namespace lld {
namespace elf {
bool link(llvm::ArrayRef<const char *> args, llvm::raw_ostream &stdoutOS,
          llvm::raw_ostream &stderrOS, bool exitEarly, bool disableOutput);
}
}

namespace llbc {

TargetEmitter::TargetEmitter(TargetConfig config) : m_config(std::move(config)) {
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();
}

bool TargetEmitter::emitObjectFile(llvm::Module* module, const std::string& outputFilename) {
    std::string error;
    llvm::Triple triple(m_config.targetTriple);
    auto target = llvm::TargetRegistry::lookupTarget(triple.str(), error);

    if (!target) {
        std::cerr << "[Target Error] " << error << "\n";
        return false;
    }

    llvm::TargetOptions opt;
    auto rm = std::optional<llvm::Reloc::Model>(llvm::Reloc::PIC_);
    
    auto targetMachine = target->createTargetMachine(triple, m_config.cpu, m_config.features, opt, rm);

    module->setDataLayout(targetMachine->createDataLayout());
    module->setTargetTriple(triple);

    std::error_code ec;
    llvm::raw_fd_ostream dest(outputFilename, ec, llvm::sys::fs::OF_None);

    if (ec) {
        std::cerr << "[IO Error] Could not open output file: " << ec.message() << "\n";
        return false;
    }

    llvm::legacy::PassManager pass;
    if (targetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CodeGenFileType::ObjectFile)) {
        std::cerr << "[Target Error] TargetMachine cannot emit object file format!\n";
        return false;
    }

    pass.run(*module);
    dest.flush();
    return true;
}

static std::vector<std::string> GetHostLibraryPaths() {
    std::vector<std::string> paths;
    const char* standardDirs[] = {
        "/data/data/com.termux/files/usr/lib", // Termux Primary
        "/system/lib64",                       // Android Native 64-bit
        "/system/lib",                         // Android Native 32-bit
        "/usr/lib", "/lib", "/usr/lib64"
    };

    for (const char* dir : standardDirs) {
        if (llvm::sys::fs::exists(dir)) {
            paths.push_back(std::string("-L") + dir);
        }
    }
    return paths;
}

static std::string GetHostDynamicLinker() {
    const char* linkers[] = {
        "/system/bin/linker64",                // Android 64-bit
        "/system/bin/linker",                  // Android 32-bit
        "/lib64/ld-linux-x86-64.so.2",         // Linux
        "/lib/ld-linux-aarch64.so.1"
    };

    for (const char* linker : linkers) {
        if (llvm::sys::fs::exists(linker)) {
            return std::string(linker);
        }
    }
    return "";
}

bool TargetEmitter::linkExecutable(
    const std::vector<std::string>& objectFiles,
    const std::string& outputFile,
    const std::string& linkerScript
) {
    std::vector<std::string> argStorage;
    argStorage.push_back("lld");
    argStorage.push_back("-flavor");
    argStorage.push_back("gnu");
    argStorage.push_back("-o");
    argStorage.push_back(outputFile);

    // Bare-Metal Mode
    if (!linkerScript.empty()) {
        argStorage.push_back("--nostdlib");
        argStorage.push_back("-z");
        argStorage.push_back("max-page-size=0x1000");
        argStorage.push_back("-T");
        argStorage.push_back(linkerScript);
    } 
    // Hosted Userland Mode (Android/Linux)
    else {
        argStorage.push_back("-pie"); // Position Independent Executable (Required by Android)
        argStorage.push_back("--defsym=main=Main"); // Map LLB Main to C main

        std::string interpreter = GetHostDynamicLinker();
        if (!interpreter.empty()) {
            argStorage.push_back("-dynamic-linker");
            argStorage.push_back(interpreter);
        }

        // Add C Runtime Startup objects for Termux/Android to provide '_start'
        std::string termuxLib = "/data/data/com.termux/files/usr/lib";
        if (llvm::sys::fs::exists(termuxLib + "/crtbegin_dynamic.o")) {
            argStorage.push_back(termuxLib + "/crtbegin_dynamic.o");
        }

        for (const auto& path : GetHostLibraryPaths()) {
            argStorage.push_back(path);
        }

        argStorage.push_back("-lc"); // Link Bionic / libc
    }

    for (const auto& obj : objectFiles) {
        argStorage.push_back(obj);
    }

    // Append Termux CRT End object if hosted
    if (linkerScript.empty()) {
        if (llvm::sys::fs::exists("/data/data/com.termux/files/usr/lib/crtend_android.o")) {
            argStorage.push_back("/data/data/com.termux/files/usr/lib/crtend_android.o");
        }
    }

    std::vector<const char*> args;
    for (const auto& arg : argStorage) {
        args.push_back(arg.c_str());
    }

    struct lld::DriverDef gnuDriver = { lld::Gnu, &lld::elf::link };
    llvm::ArrayRef<lld::DriverDef> drivers(&gnuDriver, 1);

    lld::Result result = lld::lldMain(args, llvm::outs(), llvm::errs(), drivers);
    return result.retCode == 0;
}

} // namespace llbc