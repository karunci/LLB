/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#ifndef LLBC_LLVM_EMITTER_HPP
#define LLBC_LLVM_EMITTER_HPP

#include "../frontend/AST.hpp"
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/InlineAsm.h>
#include <llvm/IR/DIBuilder.h>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <string>

namespace llbc {

class LlvmEmitter {
public:
    explicit LlvmEmitter(const std::string& moduleName, bool enableDebugInfo = false, const std::string& targetTriple = "");

    bool emitModule(const ModuleNode& moduleNode);
    void registerExternalProcedure(const std::string& name, const TypeSpec& retType, const std::vector<TypeSpec>& paramTypes, const std::string& aliasName = "", const std::vector<ExprASTNode*>& defExprs = {});
    void registerClassInstancing(const std::string& className, InstancingKind instancing);
    void declareConstant(const ConstStmtNode& constNode, const std::string& prefix = "");
    llvm::Function* emitProcedure(const ProcedureNode& procNode, const std::string& className = "", const std::vector<std::unique_ptr<ASTNode>>* bodyStatements = nullptr, bool isClassMethod = false);

    void emitStructure(const StructureNode& structNode);
    void emitStatement(ASTNode* stmt);
    void emitDimStatement(const DimStmtNode& dimNode);
    void emitConstStatement(const ConstStmtNode& constNode);
    void emitAssignStatement(const AssignStmtNode& assignNode);
    void emitCallStatement(const CallExprASTNode& callNode);
    void emitIfStatement(const IfStmtNode& ifNode);
    void emitForStatement(const ForStmtNode& forNode);
    void emitForEachStatement(const ForEachStmtNode& forEachNode);
    void emitDoLoopStatement(const DoLoopStmtNode& doNode);
    void emitWhileStatement(const WhileStmtNode& whileNode);
    void emitExitStatement(const ExitStmtNode& exitNode);
    void emitSelectStatement(const SelectStmtNode& selectNode);
    void emitMatchStatement(const MatchStmtNode& matchNode);
    void emitAsmStatement(const AsmStmtNode& asmNode);
    void emitEnum(const EnumNode& enumNode);
    void emitWithStatement(const WithStmtNode& withNode);
    void emitPrintStatement(const PrintStmtNode& printNode);
    void emitPrintFileStatement(const PrintFileStmtNode& printFileNode);
    void emitOpenStatement(const OpenStmtNode& openNode);
    void emitCloseStatement(const CloseStmtNode& closeNode);
    void emitLineInputStatement(const LineInputStmtNode& lineInputNode);
    void emitInputFileStatement(const InputFileStmtNode& inputFileNode);
    void emitInputStatement(const InputStmtNode& inputNode);
    void emitDeleteStatement(const DeleteStmtNode& delNode);
    void emitReDimStatement(const ReDimStmtNode& redimNode);
    void emitEraseStatement(const EraseStmtNode& eraseNode);
    void emitLabelStatement(const LabelStmtNode& labelNode);
    void emitGoToStatement(const GoToStmtNode& gotoNode);
    void emitTryStatement(const TryStmtNode& tryNode);
    void emitUsingStatement(const UsingStmtNode& usingNode);

    llvm::Value* emitExpression(ExprASTNode* expr);
    llvm::Value* coerceType(llvm::Value* val, llvm::Type* targetType);

    llvm::Module* getModule() const { return m_module.get(); }
    void printIR() const;

private:
    llvm::Type* getLlvmType(const TypeSpec& typeSpec);
    llvm::Type* getElementType(const TypeSpec& typeSpec);
    llvm::Value* getPointerToExpr(ExprASTNode* expr);

    bool isStringExpr(ExprASTNode* expr);
    llvm::Function* getOrCreateMalloc();
    llvm::Function* getOrCreateStrlen();
    llvm::Function* getOrCreateI64ToStr();
    llvm::Function* getOrCreateStrMid();
    llvm::Function* getOrCreateStrRight();
    llvm::Function* getOrCreateStrTrim();
    llvm::Function* getOrCreateStrLTrim();
    llvm::Function* getOrCreateStrRTrim();
    llvm::Function* getOrCreatePanic();
    void emitZeroDivCheck(llvm::Value* divisor, const std::string& opName);
    llvm::Function* getOrCreateStrInStr();
    llvm::Function* getOrCreateStrVal();
    llvm::Function* getOrCreateAsc();
    llvm::Function* getOrCreateChr();
    llvm::Function* getOrCreateStrcmp();
    llvm::Function* getOrCreatePrintStr();
    llvm::Function* getOrCreateMapCreate();
    llvm::Function* getOrCreateMapSet();
    llvm::Function* getOrCreateMapGet();
    llvm::Function* getOrCreateMapHas();
    llvm::Function* getOrCreateLikeMatch();
    llvm::Function* getOrCreateFileOpen();
    llvm::Function* getOrCreateFileClose();
    llvm::Function* getOrCreateFilePrintStr();
    llvm::Function* getOrCreateFileLineInput();
    llvm::Function* getOrCreateFileEof();
    llvm::Function* getOrCreateFileLof();
    llvm::GlobalVariable* getOrCreateFileTable();
    llvm::GlobalVariable* getOrCreateErrNumber();
    llvm::GlobalVariable* getOrCreateErrSource();
    llvm::GlobalVariable* getOrCreateErrDescription();
    llvm::Value* convertToString(llvm::Value* val);
    llvm::Value* concatStrings(llvm::Value* s1, llvm::Value* s2);
    bool isUnsignedExpr(ExprASTNode* expr);
    TypeSpec deduceExprType(ExprASTNode* expr);
    void emitBoundsCheck(llvm::Value* indexVal, uint64_t bound, const std::string& varName);
    void emitNullCheck(llvm::Value* ptrVal, const std::string& exprName);
    void checkConstantOverflow(const TypeSpec& targetType, ExprASTNode* expr, size_t line, size_t col);

    std::unique_ptr<llvm::LLVMContext> m_context;
    std::unique_ptr<llvm::Module> m_module;
    std::unique_ptr<llvm::IRBuilder<>> m_builder;

    std::unordered_map<std::string, llvm::AllocaInst*> m_namedValues;
    std::unordered_map<std::string, TypeSpec> m_variableTypes;
    std::unordered_map<std::string, TypeSpec> m_globalVariableTypes;
    std::unordered_map<std::string, llvm::StructType*> m_structTypes;
    std::unordered_set<std::string> m_unionTypes;
    std::unordered_map<std::string, std::unordered_map<std::string, unsigned>> m_structFieldIndices;
    std::unordered_map<std::string, std::unordered_map<std::string, TypeSpec>> m_structFieldTypes;
    std::unordered_map<std::string, TypeSpec> m_procReturnTypes;
    std::unordered_map<std::string, int64_t> m_enumConstants;
    std::unordered_map<std::string, std::unordered_map<std::string, int64_t>> m_enums;
    std::unordered_map<std::string, std::string> m_funcAliases;
    std::unordered_map<std::string, std::vector<ExprASTNode*>> m_procDefaults;
    std::unordered_map<std::string, std::vector<std::string>> m_procParamNames;
    std::unordered_map<std::string, bool> m_procParamArray;
    std::unordered_map<std::string, const StructureNode*> m_genericStructTemplates;
    std::unordered_map<std::string, const ProcedureNode*> m_genericProcTemplates;
    std::unordered_map<std::string, InstancingKind> m_classInstancing;
    std::unordered_map<std::string, llvm::GlobalVariable*> m_classSingletons;
    std::unordered_set<std::string> m_singleUseInstantiated;
    std::unordered_set<std::string> m_initializedObjects;
    std::unordered_set<std::string> m_constants;
    std::unordered_map<std::string, const InterfaceNode*> m_interfaces;


    std::string instantiateGenericStruct(const TypeSpec& typeSpec);
    std::string instantiateGenericProcedure(const std::string& baseName, const std::vector<TypeSpec>& typeArgs);
    TypeSpec substituteTypeSpec(const TypeSpec& spec, const std::unordered_map<std::string, TypeSpec>& typeMap);

    std::vector<std::pair<llvm::Value*, TypeSpec>> m_withStack;

    llvm::BasicBlock* m_exitBlock{nullptr};
    llvm::AllocaInst* m_retAlloca{nullptr};
    std::vector<llvm::BasicBlock*> m_breakStack;
    std::vector<llvm::BasicBlock*> m_continueStack;
    std::unordered_map<std::string, llvm::BasicBlock*> m_labels;
    std::vector<llvm::BasicBlock*> m_catchStack;
    std::vector<llvm::AllocaInst*> m_tryErrAllocaStack;
    std::unordered_set<std::string> m_byRefParams;
    bool m_currentProcIsUnsafe{false};

    // DWARF Debug Information Generation (-g)
    bool m_enableDebugInfo{false};
    std::unique_ptr<llvm::DIBuilder> m_diBuilder;
    llvm::DICompileUnit* m_diCompileUnit{nullptr};
    llvm::DIFile* m_diFile{nullptr};
    std::vector<llvm::DIScope*> m_diScopes;

    void emitDebugLocation(size_t line, size_t col);

    std::string m_sourceFilePath{"<unknown>"};
    std::string m_sourceText;
    size_t m_currentLine{1};
    size_t m_currentCol{1};
    bool m_hadError{false};
};

} // namespace llbc

#endif // LLBC_LLVM_EMITTER_HPP