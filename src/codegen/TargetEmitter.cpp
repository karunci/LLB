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
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Passes/OptimizationLevel.h>

#include <lld/Common/Driver.h>
#include <lld/Common/ErrorHandler.h>
#include <llvm/Object/Archive.h>
#include <llvm/Object/ArchiveWriter.h>

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

    // Run LLVM Optimization Passes (O1, O2, O3) if requested
    if (m_config.optLevel > 0) {
        llvm::LoopAnalysisManager lam;
        llvm::FunctionAnalysisManager fam;
        llvm::CGSCCAnalysisManager cgam;
        llvm::ModuleAnalysisManager mam;

        llvm::PassBuilder pb(targetMachine);
        pb.registerModuleAnalyses(mam);
        pb.registerCGSCCAnalyses(cgam);
        pb.registerFunctionAnalyses(fam);
        pb.registerLoopAnalyses(lam);
        pb.crossRegisterProxies(lam, fam, cgam, mam);

        llvm::OptimizationLevel opt;
        switch (m_config.optLevel) {
            case 1: opt = llvm::OptimizationLevel::O1; break;
            case 2: opt = llvm::OptimizationLevel::O2; break;
            case 3: default: opt = llvm::OptimizationLevel::O3; break;
        }

        llvm::ModulePassManager mpm = pb.buildPerModuleDefaultPipeline(opt);
        mpm.run(*module, mam);
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
        "/data/data/com.termux/files/usr/lib", // Termux / Android userland
        "/system/lib64",                       // Android Native 64-bit
        "/system/lib",                         // Android Native 32-bit
        "/usr/local/lib",
        "/usr/lib",
        "/lib",
        "/usr/lib64",
        "/lib64",
        "/usr/lib/x86_64-linux-gnu",           // Debian / Ubuntu multiarch
        "/usr/lib/aarch64-linux-gnu",
        "/usr/lib/arm-linux-gnueabihf"
    };

    for (const char* dir : standardDirs) {
        if (llvm::sys::fs::exists(dir)) {
            paths.push_back(std::string("-L") + dir);
        }
    }
    return paths;
}

static std::string FindHostCrtFile(const std::vector<std::string>& candidateNames) {
    const char* searchDirs[] = {
        "/data/data/com.termux/files/usr/lib",
        "/system/lib64",
        "/system/lib",
        "/usr/lib",
        "/lib",
        "/usr/lib64",
        "/lib64",
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu",
        "/usr/lib/arm-linux-gnueabihf"
    };

    for (const auto& name : candidateNames) {
        for (const char* dir : searchDirs) {
            std::string fullPath = std::string(dir) + "/" + name;
            if (llvm::sys::fs::exists(fullPath)) {
                return fullPath;
            }
        }
    }
    return "";
}

static std::string GetHostDynamicLinker() {
    const char* linkers[] = {
        "/system/bin/linker64",                // Android 64-bit
        "/system/bin/linker",                  // Android 32-bit
        "/lib64/ld-linux-x86-64.so.2",         // Linux x86_64
        "/lib/ld-linux-aarch64.so.1",          // Linux AArch64
        "/lib/ld-linux-armhf.so.3",            // Linux ARM
        "/lib/ld-musl-x86_64.so.1",            // Musl x86_64 (Alpine)
        "/lib/ld-musl-aarch64.so.1"            // Musl AArch64
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
    const std::string& linkerScript,
    bool isShared,
    bool isFreestanding
) {
    std::vector<std::string> argStorage;
    argStorage.push_back("lld");
    argStorage.push_back("-flavor");
    argStorage.push_back("gnu");
    argStorage.push_back("-o");
    argStorage.push_back(outputFile);

    // Bare-Metal / Freestanding Mode
    if (!linkerScript.empty() || isFreestanding) {
        argStorage.push_back("--nostdlib");
        argStorage.push_back("-z");
        argStorage.push_back("max-page-size=0x1000");
        if (!linkerScript.empty()) {
            argStorage.push_back("-T");
            argStorage.push_back(linkerScript);
        }
    } 
    // Hosted Userland Mode (Android/Linux)
    else {
        if (isShared) {
            argStorage.push_back("-shared");
            argStorage.push_back("-soname");
            argStorage.push_back(outputFile);
        } else {
            argStorage.push_back("-pie"); // Position Independent Executable (Required by Android)
            // Allow looking for shared libraries in the same directory as the executable ($ORIGIN)
            argStorage.push_back("-rpath");
            argStorage.push_back("$ORIGIN");
            argStorage.push_back("-rpath");
            argStorage.push_back(".");
        }

        std::string interpreter = GetHostDynamicLinker();
        if (!interpreter.empty() && !isShared) {
            argStorage.push_back("-dynamic-linker");
            argStorage.push_back(interpreter);
        }

        // Add C Runtime Startup objects dynamically
        if (isShared) {
            std::string crtBegin = FindHostCrtFile({"crtbegin_so.o", "crti.o"});
            if (!crtBegin.empty()) {
                argStorage.push_back(crtBegin);
            }
        } else {
            std::string crtBegin = FindHostCrtFile({"crtbegin_dynamic.o", "Scrt1.o", "crt1.o"});
            if (!crtBegin.empty()) {
                argStorage.push_back(crtBegin);
            }
            std::string crtI = FindHostCrtFile({"crti.o"});
            if (!crtI.empty()) {
                argStorage.push_back(crtI);
            }
        }

        for (const auto& path : GetHostLibraryPaths()) {
            argStorage.push_back(path);
        }

        argStorage.push_back("-lc"); // Link Bionic / libc
    }

    for (const auto& obj : objectFiles) {
        argStorage.push_back(obj);
    }

    // Append CRT End object dynamically if hosted
    if (linkerScript.empty() && !isFreestanding) {
        if (isShared) {
            std::string crtEnd = FindHostCrtFile({"crtend_so.o", "crtn.o"});
            if (!crtEnd.empty()) {
                argStorage.push_back(crtEnd);
            }
        } else {
            std::string crtEnd = FindHostCrtFile({"crtend_android.o", "crtend.o", "crtn.o"});
            if (!crtEnd.empty()) {
                argStorage.push_back(crtEnd);
            }
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

bool TargetEmitter::createStaticArchive(
    const std::vector<std::string>& objectFiles,
    const std::string& outputFile
) {
    std::vector<llvm::NewArchiveMember> members;
    for (const auto& objFile : objectFiles) {
        llvm::Expected<llvm::NewArchiveMember> memberOrErr =
            llvm::NewArchiveMember::getFile(objFile, /*Deterministic=*/true);
        if (!memberOrErr) {
            std::cerr << "[llbc] Archive error: Unable to read object member " << objFile << "\n";
            return false;
        }
        members.push_back(std::move(*memberOrErr));
    }

    auto err = llvm::writeArchive(
        outputFile,
        members,
        llvm::SymtabWritingMode::NormalSymtab,
        llvm::object::Archive::K_GNU,
        /*Deterministic=*/true,
        /*Thin=*/false
    );

    if (err) {
        std::cerr << "[llbc] Archive error writing to " << outputFile << ": "
                  << llvm::toString(std::move(err)) << "\n";
        return false;
    }

    return true;
}

} // namespace llbc