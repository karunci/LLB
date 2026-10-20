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
    std::string targetArch;               // empty = host triple (Executable); explicit for cross/bare-metal
    std::string entryPoint;
    std::string outputFile;
    std::string outDir;                   // resolved absolute path to the output directory
    std::string linkerScript;
    bool isFreestanding{false};
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
        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '\'' || line[0] == ';') continue;

            // Section header e.g. [Project], [PostBuild], [Script], etc.
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

                value.erase(0, value.find_first_not_of(" \t\r\n\""));
                auto lastVal = value.find_last_not_of(" \t\r\n\"");
                if (lastVal != std::string::npos) value.erase(lastVal + 1);

                if (currentSection == "PostBuild" || currentSection == "Script" || currentSection == "RejectionTests") {
                    if (key == "Cmd" || key == "Run" || key == "Command") {
                        // If value refers to a script file in the project base directory, resolve it
                        std::string resolved = resolvePath(value);
                        if (std::filesystem::exists(resolved)) {
                            if (resolved.rfind(".sh") != std::string::npos) {
                                config.postBuildCommands.push_back("bash \"" + resolved + "\"");
                            } else {
                                config.postBuildCommands.push_back("\"" + resolved + "\"");
                            }
                        } else {
                            // Otherwise treat as raw command line
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
                        // Key is interpreter/executable (e.g. bash = "script.sh", python = "verify.py")
                        std::string scriptPath = resolvePath(value);
                        config.postBuildCommands.push_back(key + " \"" + scriptPath + "\"");
                    }
                } else if (key == "Name") config.name = value;
                else if (key == "Type") {
                    config.type = value;
                    if (value == "Kernel" || value == "Freestanding" || value == "BareMetal" ||
                        value == "BareMetalExecutable" || value == "RawBinary" ||
                        value == "FlatBinary" || value == "Binary") {
                        config.isFreestanding = true;
                    }
                } else if (key == "Freestanding") {
                    config.isFreestanding = (value == "True" || value == "true" || value == "1");
                }
                else if (key == "Arch") config.targetArch = value;
                else if (key == "EntryPoint") config.entryPoint = value;
                else if (key == "LinkerScript") config.linkerScript = resolvePath(value);
                else if (key == "OutDir")  config.outDir  = (baseDir / value).lexically_normal().string();
                else if (key == "OutFile") config.outputFile = value;   // stored raw; resolved below
                else if (key == "Module" || key == "Class") {
                    config.sourceFiles.push_back(resolvePath(value));
                } else if (key == "Assembly") {
                    config.assemblyFiles.push_back(resolvePath(value));
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