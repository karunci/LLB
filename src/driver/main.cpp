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
        size_t dotPos = imp.moduleName.rfind('.');
        if (dotPos != std::string::npos && dotPos + 1 < imp.moduleName.size()) {
            std::string tail = imp.moduleName.substr(dotPos + 1);
            std::string lowerTail = toLowerStr(tail);
            candidates.push_back(tail + ".bas");
            candidates.push_back(tail + ".cls");
            candidates.push_back(lowerTail + ".bas");
            candidates.push_back(lowerTail + ".cls");
        }

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

        std::string modNameLower = toLowerStr(mod->name);
        g_moduleFileIndex[modNameLower] = sourcePath;

        // Also index short name if dotted (e.g. "Gdt" for "Arch.X86_64.Gdt")
        size_t lastDot = modNameLower.rfind('.');
        if (lastDot != std::string::npos && lastDot + 1 < modNameLower.size()) {
            std::string shortName = modNameLower.substr(lastDot + 1);
            if (g_moduleFileIndex.find(shortName) == g_moduleFileIndex.end()) {
                g_moduleFileIndex[shortName] = sourcePath;
            }
        }
        // Also index namespace prefix if applicable (e.g. "Arch.X86_64")
        if (lastDot != std::string::npos) {
            std::string nsPrefix = modNameLower.substr(0, lastDot);
            if (g_moduleFileIndex.find(nsPrefix) == g_moduleFileIndex.end()) {
                g_moduleFileIndex[nsPrefix] = sourcePath;
            }
        }

        std::function<void(const std::shared_ptr<llbc::ModuleNode>&)> indexInner = [&](const std::shared_ptr<llbc::ModuleNode>& m) {
            if (!m) return;
            for (const auto& member : m->members) {
                if (auto iface = dynamic_cast<const llbc::InterfaceNode*>(member.get())) {
                    std::string ifLower = toLowerStr(iface->name);
                    g_moduleFileIndex[ifLower] = sourcePath;
                    if (!m->name.empty() && ifLower.find('.') == std::string::npos) {
                        g_moduleFileIndex[toLowerStr(m->name + "." + iface->name)] = sourcePath;
                    }
                }
            }
            for (const auto& inMod : m->innerModules) {
                if (!inMod) continue;
                std::string inLower = toLowerStr(inMod->name);
                g_moduleFileIndex[inLower] = sourcePath;
                size_t d = inLower.rfind('.');
                if (d != std::string::npos && d + 1 < inLower.size()) {
                    std::string sName = inLower.substr(d + 1);
                    if (g_moduleFileIndex.find(sName) == g_moduleFileIndex.end()) {
                        g_moduleFileIndex[sName] = sourcePath;
                    }
                }
                indexInner(inMod);
            }
        };
        indexInner(mod);
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

        for (const auto& useDir : mod->uses) {
            std::string targetFilePath = "";
            if (useDir.containerPath.find('.') != std::string::npos && 
                (useDir.containerPath.find(".cls") != std::string::npos || useDir.containerPath.find(".bas") != std::string::npos)) {
                targetFilePath = useDir.containerPath;
                size_t slash = curFile.find_last_of("/\\");
                if (slash != std::string::npos && targetFilePath.find('/') == std::string::npos && targetFilePath.find('\\') == std::string::npos) {
                    std::string cand = curFile.substr(0, slash + 1) + targetFilePath;
                    if (fs::exists(cand)) {
                        targetFilePath = cand;
                    } else if (fs::exists(targetFilePath)) {
                        // targetFilePath exists as-is
                    } else {
                        targetFilePath = cand;
                    }
                }
            } else {
                std::string targetModName = !useDir.containerPath.empty()
                    ? (useDir.containerPath + "." + useDir.targetPath)
                    : useDir.targetPath;
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
            if (!targetFilePath.empty() && !visited.count(targetFilePath)) {
                getOrParseModule(targetFilePath);
                worklist.push_back(targetFilePath);
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

    // Pre-register all interfaces, delegates, structures, and enums discovered across the compilation unit
    std::function<void(const std::shared_ptr<llbc::ModuleNode>&)> preRegisterAll = [&](const std::shared_ptr<llbc::ModuleNode>& m) {
        if (!m) return;
        for (const auto& member : m->members) {
            if (auto iface = dynamic_cast<const llbc::InterfaceNode*>(member.get())) {
                irEmitter.emitInterface(*iface);
            } else if (auto del = dynamic_cast<const llbc::DelegateNode*>(member.get())) {
                irEmitter.emitDelegate(*del);
            } else if (auto st = dynamic_cast<const llbc::StructureNode*>(member.get())) {
                irEmitter.emitStructure(*st);
                if (!m->name.empty()) {
                    llbc::StructureNode qualSt = *st;
                    qualSt.name = m->name + "." + st->name;
                    irEmitter.emitStructure(qualSt);
                }
            } else if (auto en = dynamic_cast<const llbc::EnumNode*>(member.get())) {
                irEmitter.emitEnum(*en);
            }
        }
        for (const auto& inMod : m->innerModules) {
            preRegisterAll(inMod);
        }
    };
    for (const auto& pair : g_parsedModules) {
        preRegisterAll(pair.second);
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

        std::vector<std::shared_ptr<llbc::ModuleNode>> targetList;
        std::function<void(const std::shared_ptr<llbc::ModuleNode>&)> collectTargets = [&](const std::shared_ptr<llbc::ModuleNode>& m) {
            if (!m) return;
            targetList.push_back(m);
            for (const auto& inMod : m->innerModules) {
                collectTargets(inMod);
            }
        };

        std::shared_ptr<llbc::ModuleNode> specificChild = nullptr;
        std::function<void(const std::shared_ptr<llbc::ModuleNode>&)> findChild = [&](const std::shared_ptr<llbc::ModuleNode>& m) {
            if (!m || specificChild) return;
            if (toLowerStr(m->name) == toLowerStr(imp.moduleName)) {
                specificChild = m;
                return;
            }
            for (const auto& inMod : m->innerModules) {
                findChild(inMod);
            }
        };
        if (!imp.moduleName.empty() && toLowerStr(targetMod->name) != toLowerStr(imp.moduleName)) {
            findChild(targetMod);
        }
        if (specificChild) {
            collectTargets(specificChild);
        } else {
            collectTargets(targetMod);
        }

        for (const auto& curMod : targetList) {
            // Strict role enforcement: Import is strictly for procedural Modules, Namespaces, and Interfaces.
            // Classes must be brought in using 'Use <ClassName>'.
            if (curMod->isClass && (specificChild == curMod || (!imp.moduleName.empty() && toLowerStr(curMod->name) == toLowerStr(imp.moduleName)))) {
                llbc::Diagnostic::report(sourcePath, imp.line, imp.column, true,
                    "Cannot 'Import' Class '" + curMod->name + "'. Use 'Use " + curMod->name + "' instead.");
                return "";
            }
            if (curMod->isClass) {
                irEmitter.registerClassInstancing(curMod->name, curMod->instancing);
                if (!imp.moduleName.empty() && imp.moduleName == curMod->name) {
                    irEmitter.registerClassInstancing(imp.moduleName, curMod->instancing);
                }
                llbc::StructureNode classStruct;
                classStruct.name = curMod->name;
                for (const auto& m : curMod->members) {
                    if (auto dim = dynamic_cast<const llbc::DimStmtNode*>(m.get())) {
                        llbc::StructureField f;
                        f.name = dim->varName;
                        f.type = dim->type;
                        classStruct.fields.push_back(f);
                    }
                }
                irEmitter.emitStructure(classStruct);
                if (!imp.moduleName.empty() && imp.moduleName != curMod->name && imp.moduleName == curMod->name) {
                    classStruct.name = imp.moduleName;
                    irEmitter.emitStructure(classStruct);
                }
            }

            for (const auto& member : curMod->members) {
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
                        if (!curMod->name.empty()) {
                            llbc::StructureNode qualSt = *st;
                            qualSt.name = curMod->name + "." + st->name;
                            irEmitter.emitStructure(qualSt);
                        }
                    }
                }
                // Import Constants
                else if (auto c = dynamic_cast<const llbc::ConstStmtNode*>(member.get())) {
                    if (c->isPublic && (imp.symbolName.empty() || imp.symbolName == c->name)) {
                        std::string pref = curMod->name;
                        irEmitter.declareConstant(*c, pref);
                    }
                }
                // Import Procedures (Public Functions & Subs)
                else if (auto proc = dynamic_cast<const llbc::ProcedureNode*>(member.get())) {
                    if (proc->isPublic) {
                        bool matchSymbol = imp.symbolName.empty() || imp.symbolName == proc->name || imp.symbolName == curMod->name;
                        if (matchSymbol) {
                            std::vector<llbc::TypeSpec> pTypes;
                            std::vector<bool> paramByRefs;
                            if (curMod->isClass) {
                                pTypes.push_back(llbc::TypeSpec{curMod->name, 1}); // Me pointer
                                paramByRefs.push_back(false);
                            }
                            bool hasParamArray = false;
                            for (const auto& p : proc->parameters) {
                                llbc::TypeSpec pt = p.type;
                                if (p.isByRef) pt.pointerDepth++;
                                pTypes.push_back(pt);
                                paramByRefs.push_back(p.isByRef);
                                if (p.isParamArray) hasParamArray = true;
                            }
                            llbc::TypeSpec retType = proc->isFunction ? proc->returnType : llbc::TypeSpec{"void"};

                            std::vector<llbc::ExprASTNode*> defExprs;
                            if (curMod->isClass) {
                                defExprs.push_back(nullptr); // Me default
                            }
                            for (const auto& p : proc->parameters) {
                                defExprs.push_back(p.defaultValue.get());
                            }

                            std::string targetPrefix = "";
                            if (curMod->name.find('.') != std::string::npos) {
                                targetPrefix = curMod->name;
                                for (auto& ch : targetPrefix) {
                                    if (ch == '.') ch = '_';
                                }
                            }

                            std::string symbolMangled = !targetPrefix.empty() ? (targetPrefix + "_" + proc->name) : proc->name;
                            std::string alias = (!imp.aliasName.empty() && !imp.symbolName.empty()) ? imp.aliasName : symbolMangled;
                            irEmitter.registerExternalProcedure(proc->name, retType, pTypes, alias, defExprs, paramByRefs, hasParamArray);

                            std::string qualTarget = curMod->name + "." + proc->name;
                            irEmitter.registerExternalProcedure(qualTarget, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                            if (!imp.moduleName.empty() && imp.moduleName == curMod->name) {
                                std::string qual = imp.moduleName + "." + proc->name;
                                irEmitter.registerExternalProcedure(qual, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                            }
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
                std::string cand = sourcePath.substr(0, slash + 1) + targetFilePath;
                if (fs::exists(cand)) {
                    targetFilePath = cand;
                } else if (fs::exists(targetFilePath)) {
                    // targetFilePath exists as-is in cwd
                } else {
                    targetFilePath = cand;
                }
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

        std::vector<std::shared_ptr<llbc::ModuleNode>> useTargets;
        if (!targetMod->innerModules.empty()) {
            for (const auto& inMod : targetMod->innerModules) {
                std::string inLower = toLowerStr(inMod->name);
                std::string reqLower = toLowerStr(useDir.targetPath);
                bool matchPath = (inLower == reqLower) || reqLower.empty();
                std::string suffix = "." + reqLower;
                if (!matchPath && inLower.size() >= suffix.size() && inLower.compare(inLower.size() - suffix.size(), suffix.size(), suffix) == 0) {
                    matchPath = true;
                }
                if (matchPath) {
                    useTargets.push_back(inMod);
                }
            }
            if (useTargets.empty()) {
                useTargets.push_back(targetMod);
            }
        } else {
            useTargets.push_back(targetMod);
        }

        for (const auto& curMod : useTargets) {
            // Strict role enforcement: Use is strictly for instantiable Classes.
            // Procedural modules must be brought in using 'Import <ModuleName>'.
            if (!curMod->isClass && !curMod->isNamespace) {
                llbc::Diagnostic::report(sourcePath, useDir.line, useDir.column, true,
                    "Cannot 'Use' procedural Module '" + curMod->name + "'. Use 'Import " + curMod->name + "' instead.");
                return "";
            }
            if (curMod->isClass) {
                irEmitter.registerClassInstancing(curMod->name, curMod->instancing);
                if (!useDir.aliasName.empty()) {
                    irEmitter.registerClassInstancing(useDir.aliasName, curMod->instancing);
                }
                llbc::StructureNode classStruct;
                classStruct.name = curMod->name;
                for (const auto& m : curMod->members) {
                    if (auto dim = dynamic_cast<const llbc::DimStmtNode*>(m.get())) {
                        llbc::StructureField f;
                        f.name = dim->varName;
                        f.type = dim->type;
                        classStruct.fields.push_back(f);
                        if (!dim->isPublic) {
                            irEmitter.registerPrivateField(curMod->name, dim->varName);
                            if (!useDir.aliasName.empty()) {
                                irEmitter.registerPrivateField(useDir.aliasName, dim->varName);
                            }
                        }
                    }
                }
                irEmitter.emitStructure(classStruct);
                if (!useDir.aliasName.empty() && useDir.aliasName != curMod->name) {
                    classStruct.name = useDir.aliasName;
                    irEmitter.emitStructure(classStruct);
                }
            }

            // Register class enums, structures, constants, and methods
            for (const auto& member : curMod->members) {
                if (auto en = dynamic_cast<const llbc::EnumNode*>(member.get())) {
                    if (en->isPublic) {
                        irEmitter.emitEnum(*en);
                    }
                } else if (auto st = dynamic_cast<const llbc::StructureNode*>(member.get())) {
                    irEmitter.emitStructure(*st);
                    if (!curMod->name.empty()) {
                        llbc::StructureNode qualSt = *st;
                        qualSt.name = curMod->name + "." + st->name;
                        irEmitter.emitStructure(qualSt);
                    }
                } else if (auto c = dynamic_cast<const llbc::ConstStmtNode*>(member.get())) {
                    if (c->isPublic) {
                        std::string pref = curMod->name;
                        irEmitter.declareConstant(*c, pref);
                        if (!useDir.aliasName.empty() && useDir.aliasName != curMod->name) {
                            irEmitter.declareConstant(*c, useDir.aliasName);
                        }
                    }
                } else if (auto proc = dynamic_cast<const llbc::ProcedureNode*>(member.get())) {
                    if (proc->isPublic) {
                        std::vector<llbc::TypeSpec> pTypes;
                        // First parameter for class method is Me (pointer to class struct)
                        if (curMod->isClass) {
                            pTypes.push_back(llbc::TypeSpec{curMod->name, 1});
                        }
                        bool hasParamArray = false;
                        for (const auto& p : proc->parameters) {
                            llbc::TypeSpec pt = p.type;
                            if (p.isByRef) pt.pointerDepth++;
                            pTypes.push_back(pt);
                            if (p.isParamArray) hasParamArray = true;
                        }
                        llbc::TypeSpec retType = proc->isFunction ? proc->returnType : llbc::TypeSpec{"void"};

                        std::vector<llbc::ExprASTNode*> defExprs;
                        std::vector<bool> paramByRefs;
                        if (curMod->isClass) {
                            defExprs.push_back(nullptr); // Me pointer has no default expression
                            paramByRefs.push_back(false); // Me pointer is passed by value
                        }
                        for (const auto& p : proc->parameters) {
                            defExprs.push_back(p.defaultValue.get());
                            paramByRefs.push_back(p.isByRef);
                        }

                        std::string symbolMangled = curMod->name + "_" + proc->name;
                        for (auto& ch : symbolMangled) if (ch == '.') ch = '_';

                        irEmitter.registerExternalProcedure(curMod->name + "." + proc->name, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                        irEmitter.registerExternalProcedure(curMod->name + "_" + proc->name, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                        if (!useDir.aliasName.empty()) {
                            irEmitter.registerExternalProcedure(useDir.aliasName + "." + proc->name, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                            irEmitter.registerExternalProcedure(useDir.aliasName + "_" + proc->name, retType, pTypes, symbolMangled, defExprs, paramByRefs, hasParamArray);
                        }
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

    std::string sourceStem = fs::path(sourcePath).stem().string();
    std::string stem = sourceStem + ".o";
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
    bool compileOnly = false;      // -c: compile and assemble only, do not link
    bool emitLlvm = false;         // -emit-llvm / -S: generate human-readable LLVM IR (.ll)
    int optLevel = 0;
    int scriptTimeout = 30;
    bool skipPostBuild = false;
    bool keepTemps = false;

    bool cliHasOutputFile = false;
    bool cliHasOptLevel = false;
    bool cliHasTarget = false;
    bool cliHasLinkerScript = false;
    bool cliHasEntryPoint = false;
    bool cliHasFreestanding = false;
    bool cliHasSysroot = false;
    bool cliHasTimeout = false;
    bool cliHasKeepTemps = false;
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
    int optLevel = opts.cliHasOptLevel ? opts.optLevel : (config.hasOptLevel ? config.optLevel : 0);
    bool enableDebugInfo = opts.enableDebugInfo || config.emitDebugInfo;
    std::string targetTriple = opts.targetTriple;

    // For hosted Executables and Shared Libraries: pass arch to LLVM codegen (per compileSourceFile call)
    // but do NOT set the global targetTriple used by the linker — let LLD use host CRT.
    // For bare-metal / cross targets the full triple must drive both codegen and linking.
    bool isHostedTarget = ((config.type == "Executable" || config.type == "SharedLibrary" || config.type == "DynamicLibrary") && !isFreestanding);
    if (!opts.cliHasTarget && !config.targetArch.empty() && !isHostedTarget) {
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
    std::vector<std::string> compiledObjects;
    std::string codegenTriple = !config.targetArch.empty() ? config.targetArch : targetTriple;
    for (const auto& srcFile : config.sourceFiles) {
        std::string objFile = compileSourceFile(srcFile, optLevel, enableDebugInfo, codegenTriple, opts.sysroot, config.outDir);
        if (objFile.empty()) return 1;
        objectFiles.push_back(objFile);
        compiledObjects.push_back(objFile);
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
        compiledObjects.push_back(objFile);
    }

    // Append libraries specified in project manifest
    for (const auto& lib : config.libraries) {
        objectFiles.push_back(lib);
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

    // Clean intermediate object files unless keepTemps or Debug info is requested
    bool keepTemps = opts.cliHasKeepTemps ? opts.keepTemps
                   : (config.hasKeepTemps ? config.keepTemps : enableDebugInfo);
    if (!keepTemps) {
        for (const auto& obj : compiledObjects) {
            if (obj != outputFile && fs::exists(obj)) {
                std::error_code ec;
                fs::remove(obj, ec);
            }
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
                      << "  -c                       Compile and assemble only; do not link\n"
                      << "  -S, -emit-llvm           Emit human-readable LLVM IR (.ll) disassembly\n"
                      << "  -O0, -O1, -O2, -O3       Optimization level (-O0 default, -O2 recommended for release)\n"
                      << "  -Os, -Oz                 Optimize for code size\n"
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
        } else if (arg == "--keep-temps" || arg == "-save-temps" || arg == "--save-temps") {
            cliOpts.keepTemps = true;
            cliOpts.cliHasKeepTemps = true;
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
        } else if (arg == "-c") {
            cliOpts.compileOnly = true;
        } else if (arg == "-emit-llvm" || arg == "--emit-llvm") {
            cliOpts.emitLlvm = true;
        } else if (arg == "-S") {
            // In compiler convention, -S means emit assembly or readable IR; we support emitLlvm / compileOnly
            cliOpts.emitLlvm = true;
            cliOpts.compileOnly = true;
        } else if (arg == "-Wall" || arg == "-Wextra" || arg == "-Werror") {
            // Accepted standard compiler warning flags
        } else if (arg == "-O0") {
            cliOpts.optLevel = 0;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O1") {
            cliOpts.optLevel = 1;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O2" || arg == "-O") {
            cliOpts.optLevel = 2;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-O3") {
            cliOpts.optLevel = 3;
            cliOpts.cliHasOptLevel = true;
        } else if (arg == "-Os" || arg == "-Oz") {
            // Size optimizations map to level 2
            cliOpts.optLevel = 2;
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
    std::vector<std::string> compiledObjects;
    for (const auto& file : allSources) {
        std::string objFile = compileSourceFile(file, cliOpts.optLevel, cliOpts.enableDebugInfo, cliOpts.targetTriple, cliOpts.sysroot);
        if (objFile.empty()) return 1;
        objectFiles.push_back(objFile);
        compiledObjects.push_back(objFile);
    }

    // Assemble Raw Assembly Files
    for (const auto& file : rawAsmFiles) {
        std::string objFile = fs::path(file).stem().string() + "_asm.o";
        std::string asmTarget = !cliOpts.targetTriple.empty() ? cliOpts.targetTriple : "x86_64-unknown-none-elf";
        if (llbc::AsmCompiler::compileAssemblyFile(file, objFile, asmTarget)) {
            std::cout << "  [+] Assembled " << file << " -> " << objFile << "\n";
            objectFiles.push_back(objFile);
            compiledObjects.push_back(objFile);
        } else {
            return 1;
        }
    }

    // If -c (compile only) was requested, bypass linking stage
    if (cliOpts.compileOnly) {
        if (cliOpts.cliHasOutputFile && !allSources.empty()) {
            // If -o was explicitly provided with -c and there is a compiled object, rename/copy to outputFile
            std::string generatedObj = objectFiles.back();
            if (generatedObj != cliOpts.outputFile && fs::exists(generatedObj)) {
                std::error_code ec;
                fs::rename(generatedObj, cliOpts.outputFile, ec);
                if (ec) {
                    fs::copy_file(generatedObj, cliOpts.outputFile, fs::copy_options::overwrite_existing, ec);
                    fs::remove(generatedObj, ec);
                }
            }
        }
        return 0;
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

    // Clean intermediate object files unless keepTemps or Debug info is requested
    bool keepTemps = cliOpts.cliHasKeepTemps ? cliOpts.keepTemps : cliOpts.enableDebugInfo;
    if (!keepTemps) {
        for (const auto& obj : compiledObjects) {
            if (obj != cliOpts.outputFile && fs::exists(obj)) {
                std::error_code ec;
                fs::remove(obj, ec);
            }
        }
    }

    return 0;
}