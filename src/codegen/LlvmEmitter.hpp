/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/LlvmEmitter.hpp
 * Summary: LLVM IR Generator lowering Low-Level Basic AST into LLVM IR.
 */

#ifndef LLBC_LLVM_EMITTER_HPP
#define LLBC_LLVM_EMITTER_HPP

#include "../frontend/AST.hpp"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/LLVMContext.h>
#include <memory>
#include <unordered_map>

namespace llbc {

class LlvmEmitter {
public:
    explicit LlvmEmitter(const std::string& moduleName);

    bool emitModule(const ModuleNode& moduleNode);
    llvm::Function* emitProcedure(const ProcedureNode& procNode);
    void emitDimStatement(const DimStmtNode& dimNode);
    void emitAssignStatement(const AssignStmtNode& assignNode);
    void emitCallStatement(const CallExprASTNode& callNode);
    llvm::Value* emitExpression(ExprASTNode* expr);

    llvm::Module* getModule() const { return m_module.get(); }
    void printIR() const;

private:
    llvm::Type* getLlvmType(const TypeSpec& typeSpec);

    std::unique_ptr<llvm::LLVMContext> m_context;
    std::unique_ptr<llvm::Module> m_module;
    std::unique_ptr<llvm::IRBuilder<>> m_builder;
    std::unordered_map<std::string, llvm::AllocaInst*> m_namedValues;
};

} // namespace llbc

#endif // LLBC_LLVM_EMITTER_HPP