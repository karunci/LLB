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

namespace fs = std::filesystem;

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

    // Inject exported symbols from all imported modules into this emitter
    for (const auto& imp : moduleAST->imports) {
        std::string impPath = resolveImportPath(imp, sourcePath);
        if (impPath.empty()) continue;

        auto targetMod = getOrParseModule(impPath);
        if (!targetMod) continue;

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

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "Usage:\n";
        std::cout << "  Project Mode: llbc-stage0 <project.llbproj> [--target=<triple>] [--sysroot=<path>] [-nostdlib]\n";
        std::cout << "  Single File:  llbc-stage0 <source.bas|boot.S> [-I include_dir] [-o output.elf] [-T linker.ld] [--target=<triple>] [--sysroot=<path>] [-nostdlib]\n";
        return 1;
    }

    std::vector<std::string> inputFiles;
    std::vector<std::string> objectFiles;
    std::string outputFile = "output.elf";
    std::string linkerScript = "";
    std::string targetTriple = "";
    std::string sysroot = "";
    bool isShared = false;
    bool isStatic = false;
    bool isFreestanding = false;
    bool isRawBinary = false;
    bool enableDebugInfo = false;
    int optLevel = 0;

    // 1. Parse CLI options and collect input source files
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-o" && i + 1 < argc) {
            outputFile = argv[++i];
        } else if (arg == "-g") {
            enableDebugInfo = true;
        } else if (arg == "-I" && i + 1 < argc) {
            g_includeDirs.push_back(argv[++i]);
        } else if (arg.rfind("-I", 0) == 0 && arg.size() > 2) {
            g_includeDirs.push_back(arg.substr(2));
        } else if (arg == "-T" && i + 1 < argc) {
            linkerScript = argv[++i];
        } else if (arg == "--target" && i + 1 < argc) {
            targetTriple = argv[++i];
        } else if (arg == "-target" && i + 1 < argc) {
            targetTriple = argv[++i];
        } else if (arg.rfind("--target=", 0) == 0) {
            targetTriple = arg.substr(9);
        } else if (arg.rfind("-target=", 0) == 0) {
            targetTriple = arg.substr(8);
        } else if (arg == "--sysroot" && i + 1 < argc) {
            sysroot = argv[++i];
        } else if (arg.rfind("--sysroot=", 0) == 0) {
            sysroot = arg.substr(10);
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
            isShared = true;
        } else if (arg == "-static" || arg == "--static" || arg == "-archive") {
            isStatic = true;
        } else if (arg == "-raw-binary" || arg == "--raw-binary" || (arg == "-O" && i + 1 < argc && std::string(argv[i + 1]) == "binary")) {
            if (arg == "-O") ++i;
            isRawBinary = true;
            isFreestanding = true;
        } else if (arg == "-freestanding" || arg == "--freestanding" || arg == "-nostdlib" || arg == "--nostdlib") {
            isFreestanding = true;
        } else if (arg == "-O0") {
            optLevel = 0;
        } else if (arg == "-O1") {
            optLevel = 1;
        } else if (arg == "-O2") {
            optLevel = 2;
        } else if (arg == "-O3") {
            optLevel = 3;
        } else if (arg.rfind("-l", 0) == 0 || arg.rfind("-L", 0) == 0) {
            // Forward library flags to object / link inputs
            objectFiles.push_back(arg);
        } else if (!arg.empty() && arg[0] != '-') {
            inputFiles.push_back(arg);
        }
    }

    if (inputFiles.empty() && objectFiles.empty()) {
        std::cerr << "Error: No input files specified.\n";
        return 1;
    }

    // 2. Process project manifest or compile input files
    if (inputFiles.size() == 1 && hasExtension(inputFiles[0], ".llbproj")) {
        std::string inputPath = inputFiles[0];
        std::cout << "[llbc] Loading project manifest: " << inputPath << "\n";
        
        llbc::ProjectConfig config = llbc::ProjectParser::parse(inputPath);
        if (config.sourceFiles.empty() && config.assemblyFiles.empty()) {
            std::cerr << "Error: No source or assembly files specified in project manifest.\n";
            return 1;
        }

        outputFile = config.outputFile;
        if (!config.linkerScript.empty()) linkerScript = config.linkerScript;
        if (config.isFreestanding) isFreestanding = true;

        // For hosted Executables: pass arch to LLVM codegen (per compileSourceFile call)
        // but do NOT set the global targetTriple used by the linker — let LLD use host CRT.
        // For bare-metal / cross targets the full triple must drive both codegen and linking.
        bool isHostedExe = (config.type == "Executable" && !config.isFreestanding);
        if (!config.targetArch.empty() && targetTriple.empty() && !isHostedExe) {
            targetTriple = config.targetArch;
        }
        if (config.type == "SharedLibrary" || config.type == "DynamicLibrary") {
            isShared = true;
        } else if (config.type == "StaticLibrary" || config.type == "Archive") {
            isStatic = true;
        } else if (config.type == "RawBinary") {
            isRawBinary = true;
            isFreestanding = true;
        }

        // Register all project sources in module file catalog
        for (const auto& src : config.sourceFiles) {
            getOrParseModule(src);
        }

        // Compile LLB Modules (.bas / .cls)
        // Use config.targetArch for codegen (may differ from link-time targetTriple
        // for hosted Executables where LLD must use the host CRT/ABI).
        std::string codegenTriple = !config.targetArch.empty() ? config.targetArch : targetTriple;
        for (const auto& srcFile : config.sourceFiles) {
            std::string objFile = compileSourceFile(srcFile, optLevel, enableDebugInfo, codegenTriple, sysroot, config.outDir);
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
    } else {
        // Collect source files and recursively discover imported dependencies
        std::vector<std::string> sourceFilesToCompile;
        std::vector<std::string> rawAsmFiles;

        for (const auto& file : inputFiles) {
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
            std::string objFile = compileSourceFile(file, optLevel, enableDebugInfo, targetTriple, sysroot);
            if (objFile.empty()) return 1;
            objectFiles.push_back(objFile);
        }

        // Assemble Raw Assembly Files
        for (const auto& file : rawAsmFiles) {
            std::string objFile = fs::path(file).stem().string() + "_asm.o";
            std::string asmTarget = !targetTriple.empty() ? targetTriple : "x86_64-unknown-none-elf";
            if (llbc::AsmCompiler::compileAssemblyFile(file, objFile, asmTarget)) {
                std::cout << "  [+] Assembled " << file << " -> " << objFile << "\n";
                objectFiles.push_back(objFile);
            } else {
                return 1;
            }
        }
    }

    // Auto-detect static archive from output file extension (.a)
    if (hasExtension(outputFile, ".a")) {
        isStatic = true;
    }

    // 3. Link or Archive All Generated Object Files
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
        if (llbc::TargetEmitter::linkExecutable(objectFiles, linkTarget, linkerScript, isShared, isFreestanding, targetTriple, sysroot)) {
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

    return 0;
}