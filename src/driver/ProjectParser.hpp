/*
 * Project Name: PRK-OS / Low-Level Basic Compiler (llbc)
 * Filename: src/driver/ProjectParser.hpp
 * Workspace Path: src/driver/ProjectParser.hpp
 * Summary: Simple INI/Key-Value descriptor parser supporting Assembly files.
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
    std::string targetArch{"x86_64-unknown-none-elf"};
    std::string entryPoint;
    std::string outputFile;
    std::string linkerScript;
    bool isFreestanding{false};
    std::vector<std::string> sourceFiles;    // .bas / .cls
    std::vector<std::string> assemblyFiles;  // .S / .s
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

        std::string line;
        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '\'') continue;

            auto eqPos = line.find('=');
            if (eqPos != std::string::npos) {
                std::string key = line.substr(0, eqPos);
                std::string value = line.substr(eqPos + 1);

                // Trim spaces, quotes & carriage return
                key.erase(0, key.find_first_not_of(" \t\r\n"));
                auto lastKey = key.find_last_not_of(" \t\r\n");
                if (lastKey != std::string::npos) key.erase(lastKey + 1);

                value.erase(0, value.find_first_not_of(" \t\r\n\""));
                auto lastVal = value.find_last_not_of(" \t\r\n\"");
                if (lastVal != std::string::npos) value.erase(lastVal + 1);

                if (key == "Name") config.name = value;
                else if (key == "Type") {
                    config.type = value;
                    if (value == "Kernel" || value == "Freestanding" || value == "BareMetal") {
                        config.isFreestanding = true;
                    }
                } else if (key == "Freestanding") {
                    config.isFreestanding = (value == "True" || value == "true" || value == "1");
                }
                else if (key == "Arch") config.targetArch = value;
                else if (key == "EntryPoint") config.entryPoint = value;
                else if (key == "LinkerScript") config.linkerScript = resolvePath(value);
                else if (key == "Module" || key == "Class") {
                    config.sourceFiles.push_back(resolvePath(value));
                } else if (key == "Assembly") {
                    config.assemblyFiles.push_back(resolvePath(value));
                }
            }
        }

        config.outputFile = resolvePath(config.name + ".elf");
        return config;
    }
};

} // namespace llbc

#endif // LLBC_PROJECT_PARSER_HPP