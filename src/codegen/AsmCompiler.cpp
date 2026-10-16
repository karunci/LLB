/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/AsmCompiler.cpp
 * Summary: Implementation of in-process assembly parsing and native object emission for LLVM 21.
 */

#include "AsmCompiler.hpp"

#include <llvm/MC/MCAsmBackend.h>
#include <llvm/MC/MCAsmInfo.h>
#include <llvm/MC/MCCodeEmitter.h>
#include <llvm/MC/MCContext.h>
#include <llvm/MC/MCInstrInfo.h>
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
#include <llvm/TargetParser/Triple.h>

#include <iostream>

namespace llbc {

/**
 * @brief Compiles an assembly source file into a native object file using in-process LLVM MC infrastructure.
 * @param asmFilePath Path to the input .s assembly file.
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

    llvm::SourceMgr srcMgr;
    srcMgr.AddNewSourceBuffer(std::move(*bufferOrErr), llvm::SMLoc());

    // 2. Lookup Target Machine (e.g. x86_64-unknown-none-elf)
    std::string error;
    llvm::Triple triple(targetTriple);
    const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple.str(), error);
    if (!target) {
        std::cerr << "[AsmCompiler Error] Target lookup failed: " << error << "\n";
        return false;
    }

    // 3. Initialize Target Components for Assembly Parsing
    llvm::MCTargetOptions mcOptions;
    std::unique_ptr<llvm::MCRegisterInfo> mri(target->createMCRegInfo(triple.str()));
    std::unique_ptr<llvm::MCAsmInfo> mai(target->createMCAsmInfo(*mri, triple.str(), mcOptions));
    std::unique_ptr<llvm::MCSubtargetInfo> sti(target->createMCSubtargetInfo(triple.str(), "x86-64", ""));
    std::unique_ptr<llvm::MCInstrInfo> mii(target->createMCInstrInfo());

    llvm::MCContext ctx(triple, mai.get(), mri.get(), sti.get(), &srcMgr, &mcOptions);

    // 4. Open Output Object File Stream
    std::error_code ec;
    llvm::raw_fd_ostream outStream(outputObjPath, ec, llvm::sys::fs::OF_None);
    if (ec) {
        std::cerr << "[AsmCompiler Error] Failed to create output file: " << ec.message() << "\n";
        return false;
    }

    // 5. Build Code Emitter and Assembly Streamer
    llvm::MCCodeEmitter* emitter = target->createMCCodeEmitter(*mii, ctx);
    llvm::MCAsmBackend* asmBackend = target->createMCAsmBackend(*sti, *mri, mcOptions);

    // LLVM 21 updated 6-parameter createMCObjectStreamer call
    std::unique_ptr<llvm::MCStreamer> streamer(
        target->createMCObjectStreamer(
            triple,
            ctx,
            std::unique_ptr<llvm::MCAsmBackend>(asmBackend),
            asmBackend->createObjectWriter(outStream),
            std::unique_ptr<llvm::MCCodeEmitter>(emitter),
            *sti
        )
    );

    // 6. Create Target Assembly Parser and Execute
    std::unique_ptr<llvm::MCAsmParser> parser(llvm::createMCAsmParser(srcMgr, ctx, *streamer, *mai));
    std::unique_ptr<llvm::MCTargetAsmParser> targetParser(target->createMCAsmParser(*sti, *parser, *mii, mcOptions));

    if (!targetParser) {
        std::cerr << "[AsmCompiler Error] Target does not support inline assembly parsing!\n";
        return false;
    }

    parser->setTargetParser(*targetParser);

    // Run the Assembly Parsing Pass
    bool parseFailed = parser->Run(false);
    outStream.flush();

    return !parseFailed;
}

} // namespace llbc