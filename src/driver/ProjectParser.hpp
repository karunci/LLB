/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#ifndef LLBC_PROJECT_PARSER_HPP
#define LLBC_PROJECT_PARSER_HPP

#include <string>
#include <vector>
#include <fstream>
#include <iostream>

namespace llbc {

struct ProjectConfig {
    std::string name;
    std::string type;
    std::string author;
    std::string license;
    std::string version;
    std::string platform;
    std::string targetArch;               // empty = host triple (Executable); explicit for cross/bare-metal
    std::string entryPoint;
    std::string outputFile;
    std::string outDir;                   // resolved absolute path to the output directory
    std::string linkerScript;
    bool isFreestanding{false};
    bool emitDebugInfo{false};
    int optLevel{0};
    bool hasOptLevel{false};
    bool disableStandardLibrary{false};
    std::vector<std::string> sourceFiles;    // .bas / .cls
    std::vector<std::string> assemblyFiles;  // .S / .s
    std::vector<std::string> postBuildCommands; // sequential post-build commands/scripts
    int scriptTimeout{30};               // default post-build timeout in seconds (0 = disabled)
};

class ProjectParser {
public:
    static ProjectConfig parse(const std::string& projectFilePath) {
        ProjectConfig config;
        std::ifstream file(projectFilePath);
        if (!file.is_open()) {
            std::cerr << "Error: Could not open project file " << projectFilePath << "\n";
            return config;
        }

        std::filesystem::path baseDir = std::filesystem::path(projectFilePath).parent_path();
        auto resolvePath = [&](const std::string& p) -> std::string {
            if (p.empty() || std::filesystem::path(p).is_absolute() || baseDir.empty()) {
                return p;
            }
            return (baseDir / p).lexically_normal().string();
        };

        std::string currentSection = "";
        std::string line;
        bool inFilesArray = false;

        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '\'' || line[0] == ';') continue;

            // Handle multi-line Files = [ ... ] parsing
            if (inFilesArray) {
                size_t endBracket = line.find(']');
                std::string slice = (endBracket != std::string::npos) ? line.substr(0, endBracket) : line;
                
                // Parse comma-separated quoted string paths
                size_t p = 0;
                while (p < slice.size()) {
                    size_t q1 = slice.find('"', p);
                    if (q1 == std::string::npos) break;
                    size_t q2 = slice.find('"', q1 + 1);
                    if (q2 == std::string::npos) break;
                    std::string item = slice.substr(q1 + 1, q2 - q1 - 1);
                    if (!item.empty()) {
                        if (item.rfind(".S") != std::string::npos || item.rfind(".s") != std::string::npos) {
                            config.assemblyFiles.push_back(resolvePath(item));
                        } else {
                            config.sourceFiles.push_back(resolvePath(item));
                        }
                    }
                    p = q2 + 1;
                }
                if (endBracket != std::string::npos) {
                    inFilesArray = false;
                }
                continue;
            }

            // Section header e.g. [Project], [Target], [CompilerOptions], [Sources], etc.
            auto firstChar = line.find_first_not_of(" \t\r\n");
            if (firstChar != std::string::npos && line[firstChar] == '[') {
                auto closeBracket = line.find(']', firstChar);
                if (closeBracket != std::string::npos) {
                    currentSection = line.substr(firstChar + 1, closeBracket - firstChar - 1);
                    // Trim section name
                    currentSection.erase(0, currentSection.find_first_not_of(" \t\r\n"));
                    auto lastSec = currentSection.find_last_not_of(" \t\r\n");
                    if (lastSec != std::string::npos) currentSection.erase(lastSec + 1);
                    continue;
                }
            }

            auto eqPos = line.find('=');
            if (eqPos != std::string::npos) {
                std::string key = line.substr(0, eqPos);
                std::string value = line.substr(eqPos + 1);

                // Strip inline comment (e.g., ' comment or ; comment)
                size_t commentPos = std::string::npos;
                bool inQuotes = false;
                for (size_t i = 0; i < value.size(); ++i) {
                    if (value[i] == '"') inQuotes = !inQuotes;
                    else if (!inQuotes && (value[i] == '\'' || value[i] == ';')) {
                        commentPos = i;
                        break;
                    }
                }
                if (commentPos != std::string::npos) {
                    value = value.substr(0, commentPos);
                }

                // Trim spaces, quotes & carriage return
                key.erase(0, key.find_first_not_of(" \t\r\n"));
                auto lastKey = key.find_last_not_of(" \t\r\n");
                if (lastKey != std::string::npos) key.erase(lastKey + 1);

                value.erase(0, value.find_first_not_of(" \t\r\n"));
                auto lastVal = value.find_last_not_of(" \t\r\n");
                if (lastVal != std::string::npos) value.erase(lastVal + 1);

                // Check for Files array: Files = [ ... ]
                if (key == "Files" && value.find('[') != std::string::npos) {
                    if (value.find(']') == std::string::npos) {
                        inFilesArray = true;
                    }
                    size_t p = value.find('[');
                    size_t endB = value.find(']');
                    std::string slice = (endB != std::string::npos) ? value.substr(p + 1, endB - p - 1) : value.substr(p + 1);
                    size_t qIdx = 0;
                    while (qIdx < slice.size()) {
                        size_t q1 = slice.find('"', qIdx);
                        if (q1 == std::string::npos) break;
                        size_t q2 = slice.find('"', q1 + 1);
                        if (q2 == std::string::npos) break;
                        std::string item = slice.substr(q1 + 1, q2 - q1 - 1);
                        if (!item.empty()) {
                            if (item.rfind(".S") != std::string::npos || item.rfind(".s") != std::string::npos) {
                                config.assemblyFiles.push_back(resolvePath(item));
                            } else {
                                config.sourceFiles.push_back(resolvePath(item));
                            }
                        }
                        qIdx = q2 + 1;
                    }
                    continue;
                }

                // Strip surrounding quotes from scalar value
                if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
                    value = value.substr(1, value.size() - 2);
                }

                if (currentSection == "PostBuild" || currentSection == "Script" || currentSection == "RejectionTests") {
                    if (key == "Cmd" || key == "Run" || key == "Command") {
                        std::string resolved = resolvePath(value);
                        if (std::filesystem::exists(resolved)) {
                            if (resolved.rfind(".sh") != std::string::npos) {
                                config.postBuildCommands.push_back("bash \"" + resolved + "\"");
                            } else {
                                config.postBuildCommands.push_back("\"" + resolved + "\"");
                            }
                        } else {
                            config.postBuildCommands.push_back(value);
                        }
                    } else if (key == "Script" || key == "Bash" || key == "Sh") {
                        std::string scriptPath = resolvePath(value);
                        if (key == "Bash" || key == "Sh" || scriptPath.rfind(".sh") != std::string::npos) {
                            config.postBuildCommands.push_back("bash \"" + scriptPath + "\"");
                        } else {
                            config.postBuildCommands.push_back("\"" + scriptPath + "\"");
                        }
                    } else if (key == "Timeout" || key == "ScriptTimeout") {
                        try {
                            config.scriptTimeout = std::stoi(value);
                        } catch (...) {
                            config.scriptTimeout = 30;
                        }
                    } else {
                        std::string scriptPath = resolvePath(value);
                        config.postBuildCommands.push_back(key + " \"" + scriptPath + "\"");
                    }
                } else if (key == "Name") {
                    config.name = value;
                } else if (key == "Author") {
                    config.author = value;
                } else if (key == "License") {
                    config.license = value;
                } else if (key == "Version") {
                    config.version = value;
                } else if (key == "Platform") {
                    config.platform = value;
                    if (value == "freestanding" || value == "baremetal") {
                        config.isFreestanding = true;
                    }
                } else if (key == "Type") {
                    config.type = value;
                    if (value == "Kernel" || value == "Freestanding" || value == "BareMetal" ||
                        value == "BareMetalExecutable" || value == "RawBinary" ||
                        value == "FlatBinary" || value == "Binary") {
                        config.isFreestanding = true;
                    }
                } else if (key == "Freestanding") {
                    config.isFreestanding = (value == "True" || value == "true" || value == "1");
                } else if (key == "Arch" || key == "Architecture") {
                    config.targetArch = value;
                } else if (key == "EntryPoint") {
                    config.entryPoint = value;
                } else if (key == "LinkerScript") {
                    config.linkerScript = resolvePath(value);
                } else if (key == "OutDir" || key == "OutputDirectory") {
                    config.outDir = (baseDir / value).lexically_normal().string();
                } else if (key == "OutFile" || key == "BinaryName") {
                    config.outputFile = value;
                } else if (key == "Module" || key == "Class") {
                    config.sourceFiles.push_back(resolvePath(value));
                } else if (key == "Assembly") {
                    config.assemblyFiles.push_back(resolvePath(value));
                } else if (key == "OptimizationLevel" || key == "OptLevel") {
                    config.hasOptLevel = true;
                    if (value == "O0" || value == "0") config.optLevel = 0;
                    else if (value == "O1" || value == "1") config.optLevel = 1;
                    else if (value == "O2" || value == "2") config.optLevel = 2;
                    else if (value == "O3" || value == "3") config.optLevel = 3;
                    else if (value == "Os" || value == "s") config.optLevel = 2; // size-optimized mapped to O2 passes
                } else if (key == "EmitDebugInfo" || key == "Debug") {
                    config.emitDebugInfo = (value == "True" || value == "true" || value == "1");
                } else if (key == "DisableStandardLibrary" || key == "NoStdLib") {
                    config.disableStandardLibrary = (value == "True" || value == "true" || value == "1");
                }
            }
        }

        // Build final output file path: baseDir / outDir / outFile
        bool isBin = (config.type == "RawBinary" || config.type == "FlatBinary" || config.type == "Binary");
        std::string ext = isBin ? ".bin" : ".elf";
        std::string outFile = config.outputFile.empty() ? (config.name + ext) : config.outputFile;
        if (config.outDir.empty()) {
            config.outputFile = (baseDir / outFile).lexically_normal().string();
        } else {
            // Ensure the output directory exists
            std::error_code ec;
            std::filesystem::create_directories(config.outDir, ec);
            config.outputFile = (std::filesystem::path(config.outDir) / outFile).lexically_normal().string();
        }
        return config;
    }
};

} // namespace llbc

#endif // LLBC_PROJECT_PARSER_HPP