/*
 * Project: Low-Level Basic Compiler (llbc)
 * File: src/frontend/Diagnostic.hpp
 * Description: ANSI-colored, high-signal diagnostic engine for compiler syntax and semantic errors.
 */

#ifndef LLBC_DIAGNOSTIC_HPP
#define LLBC_DIAGNOSTIC_HPP

#include <string>
#include <iostream>
#include <sstream>
#include <vector>
#include <cstdio>

#if defined(_WIN32)
#include <io.h>
#define LLBC_ISATTY _isatty
#define LLBC_FILENO _fileno
#else
#include <unistd.h>
#define LLBC_ISATTY isatty
#define LLBC_FILENO fileno
#endif

namespace llbc {

class Diagnostic {
public:
    static bool colorsEnabled() {
        static bool enabled = []() {
            return LLBC_ISATTY(LLBC_FILENO(stderr)) != 0;
        }();
        return enabled;
    }

    /**
     * @brief Emits a formatted, ANSI-colored diagnostic message with source context and caret.
     * @param filename Path or name of the source file.
     * @param line 1-based line number.
     * @param col 1-based column number.
     * @param isError True for errors (red), false for warnings (yellow).
     * @param message Explanatory diagnostic message.
     * @param sourceText Full source text of the file (or empty if unavailable).
     */
    static void report(const std::string& filename,
                       size_t line,
                       size_t col,
                       bool isError,
                       const std::string& message,
                       const std::string& sourceText = "") {
        bool useColors = colorsEnabled();

        const char* colorReset = useColors ? "\033[0m" : "";
        const char* colorBold = useColors ? "\033[1m" : "";
        const char* colorRed = useColors ? "\033[1;31m" : "";
        const char* colorYellow = useColors ? "\033[1;33m" : "";
        const char* colorCyan = useColors ? "\033[1;36m" : "";
        const char* colorLineNum = useColors ? "\033[34m" : "";

        const char* severityColor = isError ? colorRed : colorYellow;
        const char* severityTag = isError ? "error: " : "warning: ";

        // Header: filename:line:col: error: message
        std::cerr << colorBold << (filename.empty() ? "<source>" : filename) << ":"
                  << line << ":" << col << ": " << colorReset
                  << severityColor << severityTag << colorReset
                  << colorBold << message << colorReset << "\n";

        // If source text is available, print context line and caret
        if (!sourceText.empty() && line > 0) {
            std::string lineContent = extractLine(sourceText, line);
            if (!lineContent.empty()) {
                // Print line number gutter: "  14 | "
                std::string lineStr = std::to_string(line);
                std::string gutterPad(lineStr.length() < 4 ? 4 - lineStr.length() : 1, ' ');

                std::cerr << colorLineNum << gutterPad << lineStr << " | " << colorReset
                          << lineContent << "\n";

                // Print caret indicator: "     |       ^"
                std::string caretPad(gutterPad.length() + lineStr.length() + 3, ' ');
                std::cerr << colorLineNum << caretPad << "| " << colorReset;

                size_t caretCol = col > 0 ? col - 1 : 0;
                for (size_t i = 0; i < caretCol && i < lineContent.size(); ++i) {
                    if (lineContent[i] == '\t') {
                        std::cerr << "    ";
                    } else {
                        std::cerr << " ";
                    }
                }
                std::cerr << colorCyan << "^" << colorReset << "\n";
            }
        }
    }

private:
    static std::string extractLine(const std::string& text, size_t targetLine) {
        size_t curLine = 1;
        size_t startPos = 0;

        for (size_t i = 0; i < text.size(); ++i) {
            if (curLine == targetLine) {
                size_t endPos = i;
                while (endPos < text.size() && text[endPos] != '\n' && text[endPos] != '\r') {
                    endPos++;
                }
                return text.substr(startPos, endPos - startPos);
            }
            if (text[i] == '\n') {
                curLine++;
                startPos = i + 1;
            }
        }
        if (curLine == targetLine && startPos < text.size()) {
            return text.substr(startPos);
        }
        return "";
    }
};

} // namespace llbc

#endif // LLBC_DIAGNOSTIC_HPP
