/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/LlvmEmitter.hpp
 * Summary: LLVM IR Code Generator pass for Stage-0 bootstrap compiler.
 */

#ifndef LLBC_LLVM_EMITTER_HPP
#define LLBC_LLVM_EMITTER_HPP

#include "../frontend/AST.hpp"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Value.h>
#include <memory>
#include <unordered_map>
#include <string>

namespace llbc {

class LlvmEmitter {
public:
    explicit LlvmEmitter(const std::string& moduleName);
    
    // Lower AST to LLVM IR
    bool emitModule(const ModuleNode& moduleNode);
    
    // Print IR to std::cout or file
    void printIR() const;
    
    // Get raw LLVM Module
    llvm::Module* getModule() const { return m_module.get(); }

private:
    std::unique_ptr<llvm::LLVMContext> m_context;
    std::unique_ptr<llvm::Module> m_module;
    std::unique_ptr<llvm::IRBuilder<>> m_builder;

    // Symbol table for variable alloca mappings within a function
    std::unordered_map<std::string, llvm::AllocaInst*> m_namedValues;

    // Type Translation Helpers
    llvm::Type* getLlvmType(const TypeSpec& typeSpec);
    
    // IR Lowering Passes
    llvm::Function* emitProcedure(const ProcedureNode& procNode);
    void emitDimStatement(const DimStmtNode& dimNode);
};

} // namespace llbc

#endif // LLBC_LLVM_EMITTER_HPP