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

        std::string line;
        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '\'') continue;

            auto eqPos = line.find('=');
            if (eqPos != std::string::npos) {
                std::string key = line.substr(0, eqPos);
                std::string value = line.substr(eqPos + 1);

                // Trim spaces & quotes
                key.erase(0, key.find_first_not_of(" \t"));
                key.erase(key.find_last_not_of(" \t") + 1);
                value.erase(0, value.find_first_not_of(" \t\""));
                value.erase(value.find_last_not_of(" \t\"") + 1);

                if (key == "Name") config.name = value;
                else if (key == "EntryPoint") config.entryPoint = value;
                else if (key == "LinkerScript") config.linkerScript = value;
                else if (key == "Module" || key == "Class") {
                    config.sourceFiles.push_back(value);
                } else if (key == "Assembly") {
                    config.assemblyFiles.push_back(value);
                }
            }
        }

        config.outputFile = config.name + ".elf";
        return config;
    }
};

} // namespace llbc

#endif // LLBC_PROJECT_PARSER_HPP