/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#include "ProjectParser.hpp"
#include "../frontend/Lexer.hpp"
#include "../frontend/Parser.hpp"
#include "../frontend/Diagnostic.hpp"
#include "../codegen/LlvmEmitter.hpp"
#include "../codegen/TargetEmitter.hpp"
#include "../codegen/AsmCompiler.hpp"

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <filesystem>

#include <set>
#include <map>
#include <algorithm>
#include <chrono>
#include <thread>

#if !defined(_WIN32)
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#endif

namespace fs = std::filesystem;

static int runCommandWithTimeout(const std::string& command, int timeoutSeconds) {
#if !defined(_WIN32)
    pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "Error: fork() failed to spawn process for command: " << command << "\n";
        return -1;
    }
    if (pid == 0) {
        // Child: execute via sh -c
        execl("/bin/sh", "sh", "-c", command.c_str(), (char*)nullptr);
        _exit(127);
    }

    // Parent: monitor child with timeout
    auto startTime = std::chrono::steady_clock::now();
    bool timedOut = false;

    while (true) {
        int status = 0;
        pid_t res = waitpid(pid, &status, WNOHANG);
        if (res == pid) {
            if (WIFEXITED(status)) {
                return WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                return 128 + WTERMSIG(status);
            }
            return status;
        } else if (res < 0) {
            return -1;
        }

        if (timeoutSeconds > 0) {
            auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::steady_clock::now() - startTime
            ).count();
            if (elapsed >= timeoutSeconds) {
                timedOut = true;
                break;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    if (timedOut) {
        std::cerr << "\n[llbc] Error: Post-build command timed out after " << timeoutSeconds
                  << "s and was terminated!\n";
        kill(pid, SIGTERM);
        // Grace period
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        int status = 0;
        if (waitpid(pid, &status, WNOHANG) == 0) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
        }
        return 124; // Standard timeout exit code
    }

    return 0;
#else
    // Windows fallback
    int ret = std::system(command.c_str());
    return ret;
#endif
}

static bool hasExtension(const std::string& path, const std::string& ext) {
    if (path.length() >= ext.length()) {
        return (0 == path.compare(path.length() - ext.length(), ext.length(), ext));
    }
    return false;
}

static std::string toLowerStr(const std::string& str) {
    std::string lower = str;
    for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return lower;
}

// Global project module catalog: ModuleName -> FilePath
static std::unordered_map<std::string, std::string> g_moduleFileIndex;
static std::vector<std::string> g_includeDirs;

static std::string resolveImportPath(const llbc::ImportDirective& imp, const std::string& currentFilePath) {
    // 1. Explicit file path: In "path/file.bas" or Import "path/file.bas"
    if (!imp.filePath.empty()) {
        fs::path p(imp.filePath);
        if (p.is_absolute() && fs::exists(p)) return p.string();

        // Relative to current file's directory
        fs::path currentDir = fs::path(currentFilePath).parent_path();
        fs::path relPath = currentDir / p;
        if (fs::exists(relPath)) return relPath.string();

        // Check include directories
        for (const auto& inc : g_includeDirs) {
            fs::path incPath = fs::path(inc) / p;
            if (fs::exists(incPath)) return incPath.string();
        }
    }

    // 2. Named Module: Import ModuleName or Import ModuleName.Symbol
    if (!imp.moduleName.empty()) {
        std::string lowerMod = toLowerStr(imp.moduleName);
        auto it = g_moduleFileIndex.find(lowerMod);
        if (it != g_moduleFileIndex.end()) {
            return it->second;
        }

        // Try candidate filenames in current directory and include directories
        std::vector<std::string> candidates = {
            imp.moduleName + ".bas", imp.moduleName + ".cls",
            lowerMod + ".bas", lowerMod + ".cls"
        };

        fs::path currentDir = fs::path(currentFilePath).parent_path();
        for (const auto& cand : candidates) {
            fs::path candPath = currentDir / cand;
            if (fs::exists(candPath)) return candPath.string();
        }

        for (const auto& inc : g_includeDirs) {
            for (const auto& cand : candidates) {
                fs::path candPath = fs::path(inc) / cand;
                if (fs::exists(candPath)) return candPath.string();
            }
        }
    }

    return "";
}

// Parses and caches parsed ASTs for modules across the compilation unit
static std::unordered_map<std::string, std::shared_ptr<llbc::ModuleNode>> g_parsedModules;
static std::unordered_map<std::string, int64_t> g_defines;

static std::shared_ptr<llbc::ModuleNode> getOrParseModule(const std::string& sourcePath) {
    auto it = g_parsedModules.find(sourcePath);
    if (it != g_parsedModules.end()) return it->second;

    std::ifstream file(sourcePath);
    if (!file.is_open()) {
        return nullptr;
    }
    std::stringstream buffer;
    buffer << file.rdbuf();

    llbc::Lexer lexer(buffer.str());
    llbc::Parser parser(lexer, g_defines, sourcePath);
    auto mod = std::shared_ptr<llbc::ModuleNode>(parser.parseModule().release());
    if (mod) {
        mod->sourceFilePath = sourcePath;
        g_parsedModules[sourcePath] = mod;
        g_moduleFileIndex[toLowerStr(mod->name)] = sourcePath;
    }
    return mod;
}

// Recursively discovers all transitive imports starting from entry files
static bool resolveDependencies(
    const std::vector<std::string>& entryFiles,
    std::vector<std::string>& orderedSources
) {
    std::vector<std::string> worklist = entryFiles;
    std::set<std::string> visited;
    std::vector<std::string> discovered;

    for (const auto& f : entryFiles) {
        auto mod = getOrParseModule(f);
        if (mod) {
            g_moduleFileIndex[toLowerStr(mod->name)] = f;
        }
    }

    while (!worklist.empty()) {
        std::string curFile = worklist.back();
        worklist.pop_back();

        if (visited.count(curFile)) continue;
        visited.insert(curFile);
        discovered.push_back(curFile);

        auto mod = getOrParseModule(curFile);
        if (!mod) continue;

        for (const auto& imp : mod->imports) {
            std::string resolved = resolveImportPath(imp, curFile);
            if (!resolved.empty() && !visited.count(resolved)) {
                getOrParseModule(resolved);
                worklist.push_back(resolved);
            }
        }
    }

    orderedSources = discovered;
    return true;
}

static std::string compileSourceFile(
    const std::string& sourcePath,
    int optLevel = 0,
    bool enableDebugInfo = false,
    const std::string& targetTriple = "",
    const std::string& sysroot = "",
    const std::string& outDir = ""    // directory for .ll / .o artifacts; empty = cwd
) {
    auto moduleAST = getOrParseModule(sourcePath);
    if (!moduleAST) {
        llbc::Diagnostic::report(sourcePath, 1, 1, true, "Could not parse source file");
        return "";
    }

    llbc::LlvmEmitter irEmitter(moduleAST->name, enableDebugInfo, targetTriple);

    // Pre-register all interfaces and delegates discovered across the compilation unit
    for (const auto& pair : g_parsedModules) {
        if (!pair.second) continue;
        for (const auto& member : pair.second->members) {
            if (auto iface = dynamic_cast<const llbc::InterfaceNode*>(member.get())) {
                irEmitter.emitInterface(*iface);
            } else if (auto del = dynamic_cast<const llbc::DelegateNode*>(member.get())) {
                irEmitter.emitDelegate(*del);
            }
        }
    }

    // Inject exported symbols from all imported modules into this emitter
    for (const auto& imp : moduleAST->imports) {
        std::string impPath = resolveImportPath(imp, sourcePath);
        if (impPath.empty()) {
            std::string impTarget = !imp.moduleName.empty() ? imp.moduleName : imp.filePath;
            llbc::Diagnostic::report(sourcePath, 1, 1, true, "Could not find imported module or file '" + impTarget + "'.");
            return "";
        }

        auto targetMod = getOrParseModule(impPath);
        if (!targetMod) {
            llbc::Diagnostic::report(sourcePath, 1, 1, true, "Failed to parse imported module '" + impPath + "'.");
            return "";
        }

        for (const auto& member : targetMod->members) {
            // Import Enums
            if (auto en = dynamic_cast<const llbc::EnumNode*>(member.get())) {
                if (en->isPublic && (imp.symbolName.empty() || imp.symbolName == en->name)) {
                    irEmitter.emitEnum(*en);
                }
            }
            // Import Structures & Unions
            else if (auto st = dynamic_cast<const llbc::StructureNode*>(member.get())) {
                if (imp.symbolName.empty() || imp.symbolName == st->name) {
                    irEmitter.emitStructure(*st);
                }
            }
            // Import Constants
            else if (auto c = dynamic_cast<const llbc::ConstStmtNode*>(member.get())) {
                if (c->isPublic && (imp.symbolName.empty() || imp.symbolName == c->name)) {
                    std::string pref = !imp.moduleName.empty() ? imp.moduleName : targetMod->name;
                    irEmitter.declareConstant(*c, pref);
                }
            }
            // Import Procedures (Public Functions & Subs)
            else if (auto proc = dynamic_cast<const llbc::ProcedureNode*>(member.get())) {
                if (proc->isPublic) {
                    bool matchSymbol = imp.symbolName.empty() || imp.symbolName == proc->name;
                    if (matchSymbol) {
                        std::vector<llbc::TypeSpec> pTypes;
                        for (const auto& p : proc->parameters) {
                            llbc::TypeSpec pt = p.type;
                            if (p.isByRef) pt.pointerDepth++;
                            pTypes.push_back(pt);
                        }
                        llbc::TypeSpec retType = proc->isFunction ? proc->returnType : llbc::TypeSpec{"void"};

                        std::vector<llbc::ExprASTNode*> defExprs;
                        for (const auto& p : proc->parameters) {
                            defExprs.push_back(p.defaultValue.get());
                        }

                        // If the procedure comes from a dotted module (e.g., Drivers.Terminal),
                        // its mangled symbol in the object file is ModulePrefix_ProcName (e.g. Drivers_Terminal_Initialize).
                        std::string targetPrefix = "";
                        if (targetMod->name.find('.') != std::string::npos) {
                            targetPrefix = targetMod->name;
                            for (auto& ch : targetPrefix) {
                                if (ch == '.') ch = '_';
                            }
                        }

                        std::string symbolMangled = !targetPrefix.empty() ? (targetPrefix + "_" + proc->name) : proc->name;
                        std::string alias = (!imp.aliasName.empty() && !imp.symbolName.empty()) ? imp.aliasName : symbolMangled;
                        irEmitter.registerExternalProcedure(proc->name, retType, pTypes, alias, defExprs);

                        // If imported as ModuleName.ProcName, also register qualified name
                        if (!imp.moduleName.empty()) {
                            std::string qual = imp.moduleName + "." + proc->name;
                            irEmitter.registerExternalProcedure(qual, retType, pTypes, symbolMangled, defExprs);
                        }
                        if (targetMod->name != imp.moduleName) {
                            std::string qualTarget = targetMod->name + "." + proc->name;
                            irEmitter.registerExternalProcedure(qualTarget, retType, pTypes, symbolMangled, defExprs);
                        }
                    }
                }
            }
        }
    }

    // Inject exported symbols and classes from all Use directives
    for (const auto& useDir : moduleAST->uses) {
        std::string targetModName = !useDir.containerPath.empty()
            ? (useDir.containerPath + "." + useDir.targetPath)
            : useDir.targetPath;

        // Try exact match, base match in moduleFileIndex, or direct file path if containerPath has an extension
        std::string targetFilePath = "";
        if (useDir.containerPath.find('.') != std::string::npos && 
            (useDir.containerPath.find(".cls") != std::string::npos || useDir.containerPath.find(".bas") != std::string::npos)) {
            targetFilePath = useDir.containerPath;
            // Resolve relative to sourcePath directory if needed
            size_t slash = sourcePath.find_last_of("/\\");
            if (slash != std::string::npos && targetFilePath.find('/') == std::string::npos && targetFilePath.find('\\') == std::string::npos) {
                targetFilePath = sourcePath.substr(0, slash + 1) + targetFilePath;
            }
        } else {
            auto it = g_moduleFileIndex.find(toLowerStr(targetModName));
            if (it != g_moduleFileIndex.end()) {
                targetFilePath = it->second;
            } else if (!useDir.containerPath.empty()) {
                auto it2 = g_moduleFileIndex.find(toLowerStr(useDir.containerPath));
                if (it2 != g_moduleFileIndex.end()) targetFilePath = it2->second;
            } else {
                auto it3 = g_moduleFileIndex.find(toLowerStr(useDir.targetPath));
                if (it3 != g_moduleFileIndex.end()) targetFilePath = it3->second;
            }
        }

        if (targetFilePath.empty()) continue;
        auto targetMod = getOrParseModule(targetFilePath);
        if (!targetMod) continue;

        if (targetMod->isClass) {
            irEmitter.registerClassInstancing(targetMod->name, targetMod->instancing);
            if (!useDir.aliasName.empty()) {
                irEmitter.registerClassInstancing(useDir.aliasName, targetMod->instancing);
            }
            llbc::StructureNode classStruct;
            classStruct.name = targetMod->name;
            for (const auto& m : targetMod->members) {
                if (auto dim = dynamic_cast<const llbc::DimStmtNode*>(m.get())) {
                    llbc::StructureField f;
                    f.name = dim->varName;
                    f.type = dim->type;
                    classStruct.fields.push_back(f);
                    if (!dim->isPublic) {
                        irEmitter.registerPrivateField(targetMod->name, dim->varName);
                        if (!useDir.aliasName.empty()) {
                            irEmitter.registerPrivateField(useDir.aliasName, dim->varName);
                        }
                    }
                }
            }
            irEmitter.emitStructure(classStruct);
            if (!useDir.aliasName.empty() && useDir.aliasName != targetMod->name) {
                classStruct.name = useDir.aliasName;
                irEmitter.emitStructure(classStruct);
            }
        }

        // Register the class and its methods
        for (const auto& member : targetMod->members) {
            if (auto proc = dynamic_cast<const llbc::ProcedureNode*>(member.get())) {
                if (proc->isPublic) {
                    std::vector<llbc::TypeSpec> pTypes;
                    // First parameter for class method is Me (pointer to class struct)
                    if (targetMod->isClass) {
                        pTypes.push_back(llbc::TypeSpec{targetMod->name, 1});
                    }
                    for (const auto& p : proc->parameters) {
                        llbc::TypeSpec pt = p.type;
                        if (p.isByRef) pt.pointerDepth++;
                        pTypes.push_back(pt);
                    }
                    llbc::TypeSpec retType = proc->isFunction ? proc->returnType : llbc::TypeSpec{"void"};

                    std::vector<llbc::ExprASTNode*> defExprs;
                    for (const auto& p : proc->parameters) {
                        defExprs.push_back(p.defaultValue.get());
                    }

                    std::string symbolMangled = targetMod->name + "_" + proc->name;
                    for (auto& ch : symbolMangled) if (ch == '.') ch = '_';

                    irEmitter.registerExternalProcedure(targetMod->name + "." + proc->name, retType, pTypes, symbolMangled, defExprs);
                    irEmitter.registerExternalProcedure(targetMod->name + "_" + proc->name, retType, pTypes, symbolMangled, defExprs);
                    if (!useDir.aliasName.empty()) {
                        irEmitter.registerExternalProcedure(useDir.aliasName + "." + proc->name, retType, pTypes, symbolMangled, defExprs);
                        irEmitter.registerExternalProcedure(useDir.aliasName + "_" + proc->name, retType, pTypes, symbolMangled, defExprs);
                    }
                }
            }
        }
    }

    if (!irEmitter.emitModule(*moduleAST)) {
        std::cerr << "Error: IR Verification failed for module " << moduleAST->name << "\n";
        return "";
    }

    {
        std::error_code ec;
        std::string llName = moduleAST->name + ".ll";
        std::string llPath = outDir.empty() ? llName : (fs::path(outDir) / llName).lexically_normal().string();
        llvm::raw_fd_ostream irOut(llPath, ec);
        if (!ec) {
            irEmitter.getModule()->print(irOut, nullptr);
        }
    }

    std::string stem = moduleAST->name + ".o";
    std::string objFilename = outDir.empty() ? stem
                                             : (fs::path(outDir) / stem).lexically_normal().string();
    llbc::TargetConfig targetConfig;
    if (!targetTriple.empty()) {
        targetConfig.targetTriple = targetTriple;
    }
    targetConfig.optLevel = optLevel;
    llbc::TargetEmitter targetEmitter(targetConfig);
    if (!targetEmitter.emitObjectFile(irEmitter.getModule(), objFilename)) {
        std::cerr << "Error: Failed to generate object file: " << objFilename << "\n";
        return "";
    }

    std::cout << "  [+] Compiled LLB Source: " << sourcePath << " -> " << objFilename << "\n";
    return objFilename;
}

struct CliOptions {
    std::string outputFile = "output.elf";
    std::string linkerScript = "";
    std::string entryPoint = "";
    std::string targetTriple = "";
    std::string sysroot = "";
    bool isShared = false;
    bool isStatic = false;
    bool isFreestanding = false;
    bool isRawBinary = false;
    bool enableDebugInfo = false;
    int optLevel = 0;
    int scriptTimeout = 30;
    bool skipPostBuild = false;

    bool cliHasOutputFile = false;
    bool cliHasOptLevel = false;
    bool cliHasTarget = false;
    bool cliHasLinkerScript = false;
    bool cliHasEntryPoint = false;
    bool cliHasFreestanding = false;
    bool cliHasSysroot = false;
    bool cliHasTimeout = false;
};

static int buildSingleProject(const std::string& manifestPath, const CliOptions& opts, const std::vector<std::string>& extraObjectFiles) {
    std::cout << "[llbc] Loading project manifest: " << manifestPath << "\n";
    
    // Clear project module index for clean build
    g_moduleFileIndex.clear();

    llbc::ProjectConfig config = llbc::ProjectParser::parse(manifestPath);
    if (config.sourceFiles.empty() && config.assemblyFiles.empty()) {
        std::cerr << "Error: No source or assembly files specified in project manifest: " << manifestPath << "\n";
        return 1;
    }

    std::vector<std::string> objectFiles = extraObjectFiles;
    std::string outputFile = opts.cliHasOutputFile ? opts.outputFile : config.outputFile;
    std::string linkerScript = (!opts.cliHasLinkerScript && !config.linkerScript.empty()) ? config.linkerScript : opts.linkerScript;
    std::string entryPoint = opts.cliHasEntryPoint ? opts.entryPoint : (config.isFreestanding ? config.entryPoint : "");
    bool isFreestanding = opts.cliHasFreestanding ? opts.isFreestanding : config.isFreestanding;
    int scriptTimeout = opts.cliHasTimeout ? opts.scriptTimeout : config.scriptTimeout;
    bool isShared = opts.isShared;
    bool isStatic = opts.isStatic;
    bool isRawBinary = opts.isRawBinary;
    int optLevel = opts.cliHasOptLevel ? opts.optLevel : 0;
    std::string targetTriple = opts.targetTriple;

    // For hosted Executables: pass arch to LLVM codegen (per compileSourceFile call)
    // but do NOT set the global targetTriple used by the linker — let LLD use host CRT.
    // For bare-metal / cross targets the full triple must drive both codegen and linking.
    bool isHostedExe = (config.type == "Executable" && !isFreestanding);
    if (!opts.cliHasTarget && !config.targetArch.empty() && !isHostedExe) {
        targetTriple = config.targetArch;
    }
    if (config.type == "SharedLibrary" || config.type == "DynamicLibrary") {
        isShared = true;
    } else if (config.type == "StaticLibrary" || config.type == "Archive") {
        isStatic = true;
    } else if (config.type == "RawBinary" || config.type == "FlatBinary" || config.type == "Binary") {
        isRawBinary = true;
        isFreestanding = true;
    }

    // Validate that all manifest source files exist
    for (const auto& src : config.sourceFiles) {
        if (!fs::exists(src)) {
            std::cerr << "Error: Project source file not found: " << src << "\n";
            return 1;
        }
        if (fs::is_directory(src)) {
            std::cerr << "Error: Project source file is a directory, not a file: " << src << "\n";
            return 1;
        }
        getOrParseModule(src);
    }
    for (const auto& asmFile : config.assemblyFiles) {
        if (!fs::exists(asmFile)) {
            std::cerr << "Error: Project assembly file not found: " << asmFile << "\n";
            return 1;
        }
        if (fs::is_directory(asmFile)) {
            std::cerr << "Error: Project assembly file is a directory, not a file: " << asmFile << "\n";
            return 1;
        }
    }

    // Compile LLB Modules (.bas / .cls)
    std::string codegenTriple = !config.targetArch.empty() ? config.targetArch : targetTriple;
    for (const auto& srcFile : config.sourceFiles) {
        std::string objFile = compileSourceFile(srcFile, optLevel, opts.enableDebugInfo, codegenTriple, opts.sysroot, config.outDir);
        if (objFile.empty()) return 1;
        objectFiles.push_back(objFile);
    }

    // Assemble Raw Assembly Files (.S)
    for (const auto& asmFile : config.assemblyFiles) {
        std::string asmStem = fs::path(asmFile).stem().string() + "_asm.o";
        std::string objFile = config.outDir.empty() ? asmStem
                                                    : (fs::path(config.outDir) / asmStem).lexically_normal().string();
        std::cout << "  [+] Assembling GNU Assembly: " << asmFile << " -> " << objFile << "\n";

        std::string asmTarget = !config.targetArch.empty() ? config.targetArch : targetTriple;
        if (!llbc::AsmCompiler::compileAssemblyFile(asmFile, objFile, asmTarget)) {
            std::cerr << "Error: Assembly compilation failed for " << asmFile << "\n";
            return 1;
        }
        objectFiles.push_back(objFile);
    }

    // Auto-detect static archive from output file extension (.a)
    if (hasExtension(outputFile, ".a")) {
        isStatic = true;
    }

    // Ensure parent directory of outputFile exists
    fs::path outFilePath(outputFile);
    if (outFilePath.has_parent_path()) {
        std::error_code ec;
        fs::create_directories(outFilePath.parent_path(), ec);
    }

    // Link or Archive
    if (isStatic) {
        std::cout << "[llbc] Archiving " << objectFiles.size() << " object file(s) into static library " << outputFile << "...\n";
        if (llbc::TargetEmitter::createStaticArchive(objectFiles, outputFile)) {
            std::cout << "[llbc] SUCCESS: Static Library created -> " << outputFile << "\n";
        } else {
            std::cerr << "Error: Static library archiving failed!\n";
            return 1;
        }
    } else {
        std::string linkTarget = outputFile;
        if (isRawBinary) {
            linkTarget = outputFile + ".elf";
        }

        std::cout << "[llbc] Linking " << objectFiles.size() << " object file(s) into " << linkTarget << "...\n";
        if (llbc::TargetEmitter::linkExecutable(objectFiles, linkTarget, linkerScript, isShared, isFreestanding, targetTriple, opts.sysroot, entryPoint)) {
            if (isRawBinary) {
                std::cout << "[llbc] Extracting flat binary -> " << outputFile << "...\n";
                if (llbc::TargetEmitter::emitRawBinary(linkTarget, outputFile)) {
                    std::cout << "[llbc] SUCCESS: Raw Binary created -> " << outputFile << "\n";
                } else {
                    std::cerr << "Error: Raw binary extraction failed!\n";
                    return 1;
                }
            } else if (isShared) {
                std::cout << "[llbc] SUCCESS: Dynamic Library created -> " << outputFile << "\n";
            } else {
                std::cout << "[llbc] SUCCESS: Executable created -> " << outputFile << "\n";
            }
        } else {
            std::cerr << "Error: LLD Linking stage failed!\n";
            return 1;
        }
    }

    // Execute Post-Build Commands / Scripts
    if (!opts.skipPostBuild && !config.postBuildCommands.empty()) {
        std::cout << "[llbc] Running " << config.postBuildCommands.size() << " post-build command(s)...\n";
        for (size_t idx = 0; idx < config.postBuildCommands.size(); ++idx) {
            const auto& cmd = config.postBuildCommands[idx];
            std::cout << "  [>] (" << (idx + 1) << "/" << config.postBuildCommands.size() << ") " << cmd;
            if (scriptTimeout > 0) {
                std::cout << " (timeout: " << scriptTimeout << "s)";
            }
            std::cout << "\n";

            int ret = runCommandWithTimeout(cmd, scriptTimeout);
            if (ret != 0) {
                std::cerr << "Error: Post-build command failed with exit code " << ret << ": " << cmd << "\n";
                return ret;
            }
        }
    } else if (opts.skipPostBuild && !config.postBuildCommands.empty()) {
        std::cout << "[llbc] Skipping " << config.postBuildCommands.size() << " post-build command(s) (--no-script requested)\n";
    }

    return 0;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "Usage:\n";
        std::cout << "  Project Mode: llbc <project.llbproj>... [options]\n";
        std::cout << "  Single File:  llbc <source.bas|boot.S>... [options]\n";
        std::cout << "Run 'llbc --help' for complete documentation.\n";
        return 1;
    }

    std::vector<std::string> inputFiles;
    std::vector<std::string> objectFiles;
    CliOptions cliOpts;

    // 1. Parse CLI options and collect input source files
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            std::cout << "Low-Level Basic Compiler (llbc) - Version 0.1.0\n"
                      << "Bare-metal & hosted systems programming language compiler based on LLVM/LLD.\n\n"
                      << "Usage:\n"
                      << "  llbc <project.llbproj>... [options]\n"
                      << "  llbc <source.bas|class.cls|boot.S>... [options]\n\n"
                      << "Project Manifest Mode:\n"
                      << "  Passing one or more .llbproj files builds each project sequentially according\n"
                      << "  to its descriptor manifest. CLI options override defaults in all manifests.\n\n"
                      << "Basic Options:\n"
                      << "  -o <file>                Specify final output file path (executable, lib, or raw bin)\n"
                      << "  -O0, -O1, -O2, -O3       Optimization level (-O0 default, -O2 recommended for release)\n"
                      << "  -g                       Generate DWARF debug information\n"
                      << "  -I <dir>                 Add directory to search path for Use / Import / Class files\n"
                      << "  -D <name>[=<val>]        Define preprocessor conditional macro (e.g. -D DEBUG=1)\n"
                      << "  -h, --help               Display this comprehensive help message and exit\n"
                      << "  -v, --version            Display compiler version and target information\n\n"
                      << "Target & Environment Options:\n"
                      << "  --target=<triple>        Target architecture triple (e.g. x86_64-unknown-none-elf)\n"
                      << "  -target <triple>         Alias for --target\n"
                      << "  --sysroot=<dir>          Override sysroot directory for system headers/libraries\n"
                      << "  -T <script>              Linker script for bare-metal kernel memory layouts\n"
                      << "  -e <symbol>, --entry     Specify custom entry point symbol (e.g. -e MainEntry or -e _start)\n\n"
                      << "Output Format & Runtime Mode:\n"
                      << "  --flat-binary, -flat-binary, -raw-binary, -O binary\n"
                      << "                           Emit flat raw binary image (.bin) extracted via objcopy\n"
                      << "  --freestanding, -nostdlib\n"
                      << "                           Freestanding mode: disables standard CRT startup and libc\n"
                      << "  --shared, -shared        Produce a shared dynamic library (.so)\n"
                      << "  --static, -static        Produce an archived static library (.a)\n\n"
                      << "Post-Build Script Options:\n"
                      << "  --no-script, --skip-scripts\n"
                      << "                           Skip post-build commands/scripts defined in [Script] section\n"
                      << "  --script-timeout=<sec>   Set maximum execution timeout per script (default: 30s, 0=off)\n\n"
                      << "Precedence Note:\n"
                      << "  Command-line arguments always override corresponding keys in .llbproj files.\n";
            return 0;
        } else if (arg == "--version" || arg == "-v") {
            std::cout << "llbc (Low-Level Basic Compiler) 0.1.0\n"
                      << "Copyright (c) 2026 karunci. All rights reserved.\n"
                      << "LLVM backend target: freestanding and hosted x86_64/AArch64/RISC-V.\n";
            return 0;
        } else if (arg == "-o" && i + 1 < argc) {
            cliOpts.outputFile = argv[++i];
            cliOpts.cliHasOutputFile = true;
        } else if (arg == "-g") {
            cliOpts.enableDebugInfo = true;
        } else if (arg == "-I" && i + 1 < argc) {
            g_includeDirs.push_back(argv[++i]);
        } else if (arg.rfind("-I", 0) == 0 && arg.size() > 2) {
            g_includeDirs.push_back(arg.substr(2));
        } else if (arg == "-T" && i + 1 < argc) {
            cliOpts.linkerScript = argv[++i];
            cliOpts.cliHasLinkerScript = true;
        } else if (arg == "-e" && i + 1 < argc) {
            cliOpts.entryPoint = argv[++i];
            cliOpts.cliHasEntryPoint = true;
        } else if (arg.rfind("-e", 0) == 0 && arg.size() > 2) {
            cliOpts.entryPoint = arg.substr(2);
            cliOpts.cliHasEntryPoint = true;
        } else if (arg == "--entry" && i + 1 < argc) {
            cliOpts.entryPoint = argv[++i];
            cliOpts.cliHasEntryPoint = true;
        } else if (arg.rfind("--entry=", 0) == 0) {
            cliOpts.entryPoint = arg.substr(8);
            cliOpts.cliHasEntryPoint = true;
        } else if (arg == "--target" && i + 1 < argc) {
            cliOpts.targetTriple = argv[++i];
            cliOpts.cliHasTarget = true;
        } else if (arg == "-target" && i + 1 < argc) {
            cliOpts.targetTriple = argv[++i];
            cliOpts.cliHasTarget = true;
        } else if (arg.rfind("--target=", 0) == 0) {
            cliOpts.targetTriple = arg.substr(9);
            cliOpts.cliHasTarget = true;
        } else if (arg.rfind("-target=", 0) == 0) {
            cliOpts.targetTriple = arg.substr(8);
            cliOpts.cliHasTarget = true;
        } else if (arg == "--sysroot" && i + 1 < argc) {
            cliOpts.sysroot = argv[++i];
            cliOpts.cliHasSysroot = true;
        } else if (arg.rfind("--sysroot=", 0) == 0) {
            cliOpts.sysroot = arg.substr(10);
            cliOpts.cliHasSysroot = true;
        } else if (arg == "--no-script" || arg == "--skip-scripts" || arg == "--skip-post-build") {
            cliOpts.skipPostBuild = true;
        } else if (arg.rfind("--script-timeout=", 0) == 0) {
            try {
                cliOpts.scriptTimeout = std::stoi(arg.substr(17));
                cliOpts.cliHasTimeout = true;
            } catch (...) {}
        } else if (arg == "--script-timeout" && i + 1 < argc) {
            try {
                cliOpts.scriptTimeout = std::stoi(argv[++i]);
                cliOpts.cliHasTimeout = true;
            } catch (...) {}
        } else if (arg == "-D" && i + 1 < argc) {
            std::string def = argv[++i];
            size_t eqPos = def.find('=');
            if (eqPos != std::string::npos) {
                std::string k = def.substr(0, eqPos);
                int64_t v = std::stoll(def.substr(eqPos + 1));
                g_defines[k] = v;
            } else {
                g_defines[def] = 1;
            }
        } else if (arg.rfind("-D", 0) == 0 && arg.size() > 2) {
            std::string def = arg.substr(2);
            size_t eqPos = def.find('=');
            if (eqPos != std::string::npos) {
                std::string k = def.substr(0, eqPos);
                int64_t v = std::stoll(def.substr(eqPos + 1));
                g_defines[k] = v;
            } else {
                g_defines[def] = 1;
            }
        } else if (arg == "-shared" || arg == "--shared") {
            cliOpts.isShared = true;
        } else if (arg == "-static" || arg == "--static" || arg == "-archive") {
            cliOpts.isStatic = true;
        } else if (arg == "-raw-binary" || arg == "--raw-binary" ||
                   arg == "-flat-binary" || arg == "--flat-binary" ||
                   (arg == "-O" && i + 1 < argc && std::string(argv[i + 1]) == "binary")) {
            if (arg == "-O") ++i;
            cliOpts.isRawBinary = true;
            cliOpts.isFreestanding = true;
        } else if (arg == "-freestanding" || arg == "--freestanding" || arg == "-nostdlib" || arg == "--nostdlib") {
            cliOpts.isFreestanding = true;
            cliOpts.cliHasFreestanding = true;
        } else if (arg == "-O0") {
            cliOpts.optLevel = 0;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O1") {
            cliOpts.optLevel = 1;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O2") {
            cliOpts.optLevel = 2;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O3") {
            cliOpts.optLevel = 3;
            cliOpts.cliHasOptLevel = true;
        } else if (arg.rfind("-l", 0) == 0 || arg.rfind("-L", 0) == 0) {
            // Forward library flags to object / link inputs
            objectFiles.push_back(arg);
        } else if (!arg.empty() && arg[0] != '-') {
            inputFiles.push_back(arg);
        } else {
            std::cerr << "Error: Unrecognized command-line option '" << arg << "'\n"
                      << "Run 'llbc --help' for a full list of available options.\n";
            return 1;
        }
    }

    if (inputFiles.empty() && objectFiles.empty()) {
        std::cerr << "Error: No input files specified.\n"
                  << "Run 'llbc --help' for usage syntax.\n";
        return 1;
    }

    // Validate that include directories exist
    for (const auto& inc : g_includeDirs) {
        if (!fs::exists(inc)) {
            std::cerr << "Error: Include directory does not exist: " << inc << "\n";
            return 1;
        }
        if (!fs::is_directory(inc)) {
            std::cerr << "Error: Include path is not a directory: " << inc << "\n";
            return 1;
        }
    }

    // Validate linker script if specified
    if (cliOpts.cliHasLinkerScript && !cliOpts.linkerScript.empty()) {
        if (!fs::exists(cliOpts.linkerScript)) {
            std::cerr << "Error: Linker script file not found: " << cliOpts.linkerScript << "\n";
            return 1;
        }
        if (fs::is_directory(cliOpts.linkerScript)) {
            std::cerr << "Error: Linker script path is a directory: " << cliOpts.linkerScript << "\n";
            return 1;
        }
    }

    // Separate project manifests from source/object files and validate inputs
    std::vector<std::string> manifestFiles;
    std::vector<std::string> directSourceFiles;

    for (const auto& file : inputFiles) {
        // File existence check
        if (!fs::exists(file)) {
            std::cerr << "Error: Input file does not exist: " << file << "\n";
            return 1;
        }
        // Directory check
        if (fs::is_directory(file)) {
            std::cerr << "Error: Input path is a directory, not a file: " << file << "\n";
            return 1;
        }

        // Extension check
        if (hasExtension(file, ".llbproj")) {
            manifestFiles.push_back(file);
        } else if (hasExtension(file, ".bas") || hasExtension(file, ".cls") ||
                   hasExtension(file, ".S")   || hasExtension(file, ".s") ||
                   hasExtension(file, ".o")   || hasExtension(file, ".a") ||
                   hasExtension(file, ".so")) {
            directSourceFiles.push_back(file);
        } else {
            std::cerr << "Error: Unsupported file format/extension: '" << file << "'\n"
                      << "Supported inputs: .llbproj, .bas, .cls, .S, .s, .o, .a, .so\n";
            return 1;
        }
    }

    // Reject mixing manifests with individual source files
    if (!manifestFiles.empty() && !directSourceFiles.empty()) {
        std::cerr << "Error: Cannot mix project manifest (.llbproj) with individual source files.\n"
                  << "Specify either .llbproj file(s) or individual source files.\n";
        return 1;
    }

    // Mode A: Build one or more project manifests sequentially
    if (!manifestFiles.empty()) {
        for (size_t i = 0; i < manifestFiles.size(); ++i) {
            if (manifestFiles.size() > 1) {
                std::cout << "\n==================================================\n"
                          << "[llbc] [" << (i + 1) << "/" << manifestFiles.size() << "] Building project: " << manifestFiles[i] << "\n"
                          << "==================================================\n";
            }
            int ret = buildSingleProject(manifestFiles[i], cliOpts, objectFiles);
            if (ret != 0) {
                std::cerr << "\n[llbc] Build failed for project: " << manifestFiles[i] << " (exit code " << ret << ")\n";
                return ret;
            }
        }
        if (manifestFiles.size() > 1) {
            std::cout << "\n[llbc] All " << manifestFiles.size() << " projects built successfully.\n";
        }
        return 0;
    }

    // Mode B: Direct Source File Compilation & Linking
    std::vector<std::string> sourceFilesToCompile;
    std::vector<std::string> rawAsmFiles;

    for (const auto& file : directSourceFiles) {
        if (hasExtension(file, ".S") || hasExtension(file, ".s")) {
            rawAsmFiles.push_back(file);
        } else if (hasExtension(file, ".o") || hasExtension(file, ".a") || hasExtension(file, ".so")) {
            objectFiles.push_back(file);
        } else {
            sourceFilesToCompile.push_back(file);
        }
    }

    // Transitive Import Discovery
    std::vector<std::string> allSources;
    resolveDependencies(sourceFilesToCompile, allSources);

    // Compile all discovered LLB modules
    for (const auto& file : allSources) {
        std::string objFile = compileSourceFile(file, cliOpts.optLevel, cliOpts.enableDebugInfo, cliOpts.targetTriple, cliOpts.sysroot);
        if (objFile.empty()) return 1;
        objectFiles.push_back(objFile);
    }

    // Assemble Raw Assembly Files
    for (const auto& file : rawAsmFiles) {
        std::string objFile = fs::path(file).stem().string() + "_asm.o";
        std::string asmTarget = !cliOpts.targetTriple.empty() ? cliOpts.targetTriple : "x86_64-unknown-none-elf";
        if (llbc::AsmCompiler::compileAssemblyFile(file, objFile, asmTarget)) {
            std::cout << "  [+] Assembled " << file << " -> " << objFile << "\n";
            objectFiles.push_back(objFile);
        } else {
            return 1;
        }
    }

    // Auto-detect static archive from output file extension (.a)
    bool isStatic = cliOpts.isStatic || hasExtension(cliOpts.outputFile, ".a");

    // Ensure parent directory of outputFile exists (especially if specified via CLI -o)
    fs::path outFilePath(cliOpts.outputFile);
    if (outFilePath.has_parent_path()) {
        std::error_code ec;
        fs::create_directories(outFilePath.parent_path(), ec);
    }

    // Link or Archive All Generated Object Files
    if (isStatic) {
        std::cout << "[llbc] Archiving " << objectFiles.size() << " object file(s) into static library " << cliOpts.outputFile << "...\n";
        if (llbc::TargetEmitter::createStaticArchive(objectFiles, cliOpts.outputFile)) {
            std::cout << "[llbc] SUCCESS: Static Library created -> " << cliOpts.outputFile << "\n";
        } else {
            std::cerr << "Error: Static library archiving failed!\n";
            return 1;
        }
    } else {
        std::string linkTarget = cliOpts.outputFile;
        if (cliOpts.isRawBinary) {
            linkTarget = cliOpts.outputFile + ".elf";
        }

        std::cout << "[llbc] Linking " << objectFiles.size() << " object file(s) into " << linkTarget << "...\n";
        if (llbc::TargetEmitter::linkExecutable(objectFiles, linkTarget, cliOpts.linkerScript, cliOpts.isShared, cliOpts.isFreestanding, cliOpts.targetTriple, cliOpts.sysroot, cliOpts.entryPoint)) {
            if (cliOpts.isRawBinary) {
                std::cout << "[llbc] Extracting flat binary -> " << cliOpts.outputFile << "...\n";
                if (llbc::TargetEmitter::emitRawBinary(linkTarget, cliOpts.outputFile)) {
                    std::cout << "[llbc] SUCCESS: Raw Binary created -> " << cliOpts.outputFile << "\n";
                } else {
                    std::cerr << "Error: Raw binary extraction failed!\n";
                    return 1;
                }
            } else if (cliOpts.isShared) {
                std::cout << "[llbc] SUCCESS: Dynamic Library created -> " << cliOpts.outputFile << "\n";
            } else {
                std::cout << "[llbc] SUCCESS: Executable created -> " << cliOpts.outputFile << "\n";
            }
        } else {
            std::cerr << "Error: LLD Linking stage failed!\n";
            return 1;
        }
    }

    return 0;
}