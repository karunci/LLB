/*
 * Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
 * Filename: src/driver/main.cpp
 * Summary: Driver entry point handling project manifests and single-file targets.
 */

#include "ProjectParser.hpp"
#include "../frontend/Lexer.hpp"
#include "../frontend/Parser.hpp"
#include "../codegen/LlvmEmitter.hpp"
#include "../codegen/TargetEmitter.hpp"
#include "../codegen/AsmCompiler.hpp"

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <filesystem>

namespace fs = std::filesystem;

static bool hasExtension(const std::string& path, const std::string& ext) {
    if (path.length() >= ext.length()) {
        return (0 == path.compare(path.length() - ext.length(), ext.length(), ext));
    }
    return false;
}

static std::string compileSourceFile(const std::string& sourcePath) {
    std::ifstream file(sourcePath);
    if (!file.is_open()) {
        std::cerr << "Error: Could not open source file: " << sourcePath << "\n";
        return "";
    }

    std::stringstream buffer;
    buffer << file.rdbuf();

    llbc::Lexer lexer(buffer.str());
    llbc::Parser parser(lexer);
    auto moduleAST = parser.parseModule();

    llbc::LlvmEmitter irEmitter(moduleAST->name);
    if (!irEmitter.emitModule(*moduleAST)) {
        std::cerr << "Error: IR Verification failed for module " << moduleAST->name << "\n";
        return "";
    }

    std::string objFilename = moduleAST->name + ".o";
    llbc::TargetEmitter targetEmitter;
    if (!targetEmitter.emitObjectFile(irEmitter.getModule(), objFilename)) {
        std::cerr << "Error: Failed to generate object file: " << objFilename << "\n";
        return "";
    }

    std::cout << "  [+] Compiled LLB Source: " << sourcePath << " -> " << objFilename << "\n";
    return objFilename;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "Usage:\n";
        std::cout << "  Project Mode: llbc-stage0 <project.llbproj>\n";
        std::cout << "  Single File:  llbc-stage0 <source.bas|boot.S> [-o output.elf] [-T linker.ld]\n";
        return 1;
    }

    std::string inputPath = argv[1];
    std::vector<std::string> objectFiles;
    std::string outputFile = "output.elf";
    std::string linkerScript = "";

    // 1. Parse CLI options (-o and -T) first
    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-o" && i + 1 < argc) outputFile = argv[++i];
        if (arg == "-T" && i + 1 < argc) linkerScript = argv[++i];
    }

    // 2. Process project manifest or single source file
    if (hasExtension(inputPath, ".llbproj")) {
        std::cout << "[llbc] Loading project manifest: " << inputPath << "\n";
        
        llbc::ProjectConfig config = llbc::ProjectParser::parse(inputPath);
        if (config.sourceFiles.empty() && config.assemblyFiles.empty()) {
            std::cerr << "Error: No source or assembly files specified in project manifest.\n";
            return 1;
        }

        outputFile = config.outputFile;
        if (!config.linkerScript.empty()) linkerScript = config.linkerScript;
        // 1. Compile LLB Modules (.bas / .cls)
        for (const auto& srcFile : config.sourceFiles) {
            std::string objFile = compileSourceFile(srcFile);
            if (objFile.empty()) return 1;
            objectFiles.push_back(objFile);
        }
        // 2. Assemble Raw Assembly Files (.S)
        for (const auto& asmFile : config.assemblyFiles) {
            std::string objFile = fs::path(asmFile).stem().string() + "_asm.o";
            std::cout << "  [+] Assembling GNU Assembly: " << asmFile << " -> " << objFile << "\n";

            if (!llbc::AsmCompiler::compileAssemblyFile(asmFile, objFile, config.targetArch)) {
                std::cerr << "Error: Assembly compilation failed for " << asmFile << "\n";
                return 1;
            }
            objectFiles.push_back(objFile);
        }
    // Single Assembly File Mode
    } else if (hasExtension(inputPath, ".S") || hasExtension(inputPath, ".s")) {
        std::string objFile = fs::path(inputPath).stem().string() + "_asm.o";
        if (llbc::AsmCompiler::compileAssemblyFile(inputPath, objFile)) {
            std::cout << "  [+] Assembled " << inputPath << " -> " << objFile << "\n";
            objectFiles.push_back(objFile);
        } else {
            return 1;
        }
    } else {
        // Single LLB File Mode
        std::string objFile = compileSourceFile(inputPath);
        if (objFile.empty()) return 1;
        objectFiles.push_back(objFile);
    }

    // 3. Link All Generated Object Files
    std::cout << "[llbc] Linking " << objectFiles.size() << " object file(s) into " << outputFile << "...\n";
    if (llbc::TargetEmitter::linkExecutable(objectFiles, outputFile, linkerScript)) {
        std::cout << "[llbc] SUCCESS: Executable created -> " << outputFile << "\n";
    } else {
        std::cerr << "Error: LLD Linking stage failed!\n";
        return 1;
    }

    return 0;
}