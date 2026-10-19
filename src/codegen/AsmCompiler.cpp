/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#include "AsmCompiler.hpp"

#include <llvm/MC/MCAsmBackend.h>
#include <llvm/MC/MCAsmInfo.h>
#include <llvm/MC/MCCodeEmitter.h>
#include <llvm/MC/MCContext.h>
#include <llvm/MC/MCInstrInfo.h>
#include <llvm/MC/MCObjectFileInfo.h>
#include <llvm/MC/MCObjectWriter.h>
#include <llvm/MC/MCParser/MCAsmParser.h>
#include <llvm/MC/MCParser/MCTargetAsmParser.h>
#include <llvm/MC/MCRegisterInfo.h>
#include <llvm/MC/MCStreamer.h>
#include <llvm/MC/MCSubtargetInfo.h>
#include <llvm/MC/MCTargetOptions.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/SourceMgr.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/TargetParser/Triple.h>

#include <iostream>

namespace llbc {

/**
 * @brief Compiles an assembly source file into a native object file using in-process LLVM MC infrastructure.
 * @param asmFilePath Path to the input .s/.S assembly file.
 * @param outputObjPath Target path for the output .o object file.
 * @param targetTriple Target triple string (e.g. "x86_64-unknown-none-elf").
 * @return True on successful parsing and object emission, false otherwise.
 */
bool AsmCompiler::compileAssemblyFile(
    const std::string& asmFilePath,
    const std::string& outputObjPath,
    const std::string& targetTriple
) {
    // 1. Load Assembly Source File into Memory
    auto bufferOrErr = llvm::MemoryBuffer::getFile(asmFilePath);
    if (!bufferOrErr) {
        std::cerr << "[AsmCompiler Error] Could not open assembly file: " << asmFilePath << "\n";
        return false;
    }

    // Preprocess in-memory assembly source:
    // Translate C-preprocessor style directives like '#define NAME VALUE' into GNU assembler '.equ NAME, VALUE'
    std::string rawContent = (*bufferOrErr)->getBuffer().str();
    std::string processedContent;
    processedContent.reserve(rawContent.size());

    size_t pos = 0;
    while (pos < rawContent.size()) {
        size_t lineEnd = rawContent.find('\n', pos);
        if (lineEnd == std::string::npos) {
            lineEnd = rawContent.size();
        }
        std::string line = rawContent.substr(pos, lineEnd - pos);

        // Check if line begins with optional whitespace followed by #define
        size_t firstNonWs = line.find_first_not_of(" \t\r");
        if (firstNonWs != std::string::npos && line.compare(firstNonWs, 7, "#define") == 0) {
            size_t nameStart = line.find_first_not_of(" \t", firstNonWs + 7);
            if (nameStart != std::string::npos) {
                size_t nameEnd = line.find_first_of(" \t", nameStart);
                if (nameEnd != std::string::npos) {
                    std::string macroName = line.substr(nameStart, nameEnd - nameStart);
                    size_t valStart = line.find_first_not_of(" \t", nameEnd);
                    std::string macroVal = (valStart != std::string::npos) ? line.substr(valStart) : "1";
                    // Strip trailing comments if any
                    size_t commentPos = macroVal.find("/*");
                    if (commentPos != std::string::npos) {
                        macroVal = macroVal.substr(0, commentPos);
                    }
                    size_t lineCommentPos = macroVal.find("//");
                    if (lineCommentPos != std::string::npos) {
                        macroVal = macroVal.substr(0, lineCommentPos);
                    }
                    // Trim trailing whitespace
                    size_t lastNonWs = macroVal.find_last_not_of(" \t\r");
                    if (lastNonWs != std::string::npos) {
                        macroVal = macroVal.substr(0, lastNonWs + 1);
                    }
                    line = line.substr(0, firstNonWs) + ".equ " + macroName + ", " + macroVal;
                }
            }
        }

        processedContent += line;
        if (lineEnd < rawContent.size()) {
            processedContent += '\n';
        }
        pos = lineEnd + 1;
    }

    llvm::SourceMgr srcMgr;
    auto processedBuf = llvm::MemoryBuffer::getMemBufferCopy(processedContent, asmFilePath);
    srcMgr.AddNewSourceBuffer(std::move(processedBuf), llvm::SMLoc());

    // 2. Lookup Target Machine (e.g. x86_64-unknown-none-elf)
    std::string error;
    llvm::Triple triple(targetTriple.empty() ? llvm::sys::getDefaultTargetTriple() : targetTriple);
    const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple.str(), error);
    if (!target) {
        std::cerr << "[AsmCompiler Error] Target lookup failed: " << error << "\n";
        return false;
    }

    // 3. Initialize Target Components for Assembly Parsing
    llvm::MCTargetOptions mcOptions;
    std::unique_ptr<llvm::MCRegisterInfo> mri(target->createMCRegInfo(triple.str()));
    if (!mri) {
        std::cerr << "[AsmCompiler Error] Failed to create MCRegisterInfo for triple: " << triple.str() << "\n";
        return false;
    }

    std::unique_ptr<llvm::MCAsmInfo> mai(target->createMCAsmInfo(*mri, triple.str(), mcOptions));
    if (!mai) {
        std::cerr << "[AsmCompiler Error] Failed to create MCAsmInfo for triple: " << triple.str() << "\n";
        return false;
    }

    std::unique_ptr<llvm::MCSubtargetInfo> sti(target->createMCSubtargetInfo(triple.str(), "", ""));
    if (!sti) {
        std::cerr << "[AsmCompiler Error] Failed to create MCSubtargetInfo for triple: " << triple.str() << "\n";
        return false;
    }

    std::unique_ptr<llvm::MCInstrInfo> mii(target->createMCInstrInfo());
    if (!mii) {
        std::cerr << "[AsmCompiler Error] Failed to create MCInstrInfo for triple: " << triple.str() << "\n";
        return false;
    }

    llvm::MCContext ctx(triple, mai.get(), mri.get(), sti.get(), &srcMgr, &mcOptions);

    // Initialize target-specific MCObjectFileInfo and associate with MCContext
    std::unique_ptr<llvm::MCObjectFileInfo> mofi(target->createMCObjectFileInfo(ctx, /*PIC=*/false));
    ctx.setObjectFileInfo(mofi.get());

    // 4. Open Output Object File Stream
    std::error_code ec;
    llvm::raw_fd_ostream outStream(outputObjPath, ec, llvm::sys::fs::OF_None);
    if (ec) {
        std::cerr << "[AsmCompiler Error] Failed to create output file: " << ec.message() << "\n";
        return false;
    }

    // 5. Build Code Emitter and Assembly Streamer
    std::unique_ptr<llvm::MCCodeEmitter> emitter(target->createMCCodeEmitter(*mii, ctx));
    std::unique_ptr<llvm::MCAsmBackend> asmBackend(target->createMCAsmBackend(*sti, *mri, mcOptions));
    if (!emitter || !asmBackend) {
        std::cerr << "[AsmCompiler Error] Failed to create MCCodeEmitter or MCAsmBackend\n";
        return false;
    }

    std::unique_ptr<llvm::MCObjectWriter> objWriter = asmBackend->createObjectWriter(outStream);
    std::unique_ptr<llvm::MCStreamer> streamer(
        target->createMCObjectStreamer(
            triple,
            ctx,
            std::move(asmBackend),
            std::move(objWriter),
            std::move(emitter),
            *sti
        )
    );
    if (!streamer) {
        std::cerr << "[AsmCompiler Error] Failed to create MCObjectStreamer\n";
        return false;
    }

    // 6. Create Target Assembly Parser and Execute
    std::unique_ptr<llvm::MCAsmParser> parser(llvm::createMCAsmParser(srcMgr, ctx, *streamer, *mai));
    if (!parser) {
        std::cerr << "[AsmCompiler Error] Failed to create MCAsmParser\n";
        return false;
    }

    std::unique_ptr<llvm::MCTargetAsmParser> targetParser(target->createMCAsmParser(*sti, *parser, *mii, mcOptions));
    if (!targetParser) {
        std::cerr << "[AsmCompiler Error] Target does not support inline assembly parsing!\n";
        return false;
    }

    parser->setTargetParser(*targetParser);

    // Run the Assembly Parsing Pass
    bool parseFailed = parser->Run(false);
    outStream.flush();

    if (parseFailed) {
        std::cerr << "[AsmCompiler Error] Assembly parsing/emission failed for: " << asmFilePath << "\n";
        return false;
    }

    return true;
}

} // namespace llbc