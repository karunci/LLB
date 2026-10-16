/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/codegen/LlvmEmitter.cpp
 * Summary: Implementation of LLVM IR emission from LLB AST nodes.
 */

#include "LlvmEmitter.hpp"
#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>
#include <iostream>

namespace llbc {

LlvmEmitter::LlvmEmitter(const std::string& moduleName) {
    m_context = std::make_unique<llvm::LLVMContext>();
    m_module = std::make_unique<llvm::Module>(moduleName, *m_context);
    m_builder = std::make_unique<llvm::IRBuilder<>>(*m_context);
}

llvm::Type* LlvmEmitter::getLlvmType(const TypeSpec& typeSpec) {
    llvm::Type* baseType = nullptr;

    std::string typeName = typeSpec.name;
    for (auto& c : typeName) c = static_cast<char>(std::tolower(c));

    // Primitive Type Mapping
    if (typeName == "byte" || typeName == "ubyte") {
        baseType = llvm::Type::getInt8Ty(*m_context);
    } else if (typeName == "uint16" || typeName == "int16") {
        baseType = llvm::Type::getInt16Ty(*m_context);
    } else if (typeName == "uint32" || typeName == "int32" || typeName == "long") {
        baseType = llvm::Type::getInt32Ty(*m_context);
    } else if (typeName == "uint64" || typeName == "int64") {
        baseType = llvm::Type::getInt64Ty(*m_context);
    } else if (typeName == "boolean") {
        baseType = llvm::Type::getInt1Ty(*m_context);
    } else if (typeName == "void") {
        baseType = llvm::Type::getVoidTy(*m_context);
    } else {
        baseType = llvm::Type::getInt64Ty(*m_context);
    }

    if (typeSpec.pointerDepth > 0) {
        return llvm::PointerType::get(*m_context, 0); 
    }

    return baseType;
}

void LlvmEmitter::emitDimStatement(const DimStmtNode& dimNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Type* varType = getLlvmType(dimNode.type);

    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* alloca = tmpBuilder.CreateAlloca(varType, nullptr, dimNode.varName);

    m_namedValues[dimNode.varName] = alloca;
}

void LlvmEmitter::emitCallStatement(const CallExprASTNode& callNode) {
    llvm::Function* callee = m_module->getFunction(callNode.funcName);
    if (!callee) {
        std::cerr << "[IR Error] Unknown function called: " << callNode.funcName << "\n";
        return;
    }

    std::vector<llvm::Value*> args;
    for (const auto& arg : callNode.args) {
        args.push_back(emitExpression(arg.get()));
    }

    m_builder->CreateCall(callee, args);
}

llvm::Value* LlvmEmitter::emitExpression(ExprASTNode* expr) {
    if (auto num = dynamic_cast<NumberExprASTNode*>(expr)) {
        return llvm::ConstantInt::get(*m_context, llvm::APInt(32, num->val, true));
    }
    if (auto str = dynamic_cast<StringExprASTNode*>(expr)) {
        return m_builder->CreateGlobalString(str->val);
    }
    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_namedValues.find(var->name);
        if (it != m_namedValues.end()) {
            llvm::AllocaInst* alloca = it->second;
            return m_builder->CreateLoad(alloca->getAllocatedType(), alloca, var->name.c_str());
        }
    }
    if (auto bin = dynamic_cast<BinaryExprASTNode*>(expr)) {
        llvm::Value* l = emitExpression(bin->lhs.get());
        llvm::Value* r = emitExpression(bin->rhs.get());
        if (bin->op == '+') return m_builder->CreateAdd(l, r, "addtmp");
        if (bin->op == '-') return m_builder->CreateSub(l, r, "subtmp");
        if (bin->op == '<') return m_builder->CreateICmpSLT(l, r, "cmptmp");
    }
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        llvm::Function* callee = m_module->getFunction(call->funcName);
        std::vector<llvm::Value*> args;
        for (auto& arg : call->args) {
            args.push_back(emitExpression(arg.get()));
        }
        return m_builder->CreateCall(callee, args, "calltmp");
    }
    return nullptr;
}

void LlvmEmitter::emitAssignStatement(const AssignStmtNode& assignNode) {
    auto it = m_namedValues.find(assignNode.varName);
    if (it != m_namedValues.end()) {
        llvm::Value* val = emitExpression(assignNode.value.get());
        m_builder->CreateStore(val, it->second);
    }
}

llvm::Function* LlvmEmitter::emitProcedure(const ProcedureNode& procNode) {
    m_namedValues.clear();

    // 1. Resolve Return Type
    llvm::Type* retType = procNode.isFunction ? getLlvmType(procNode.returnType) 
                                              : llvm::Type::getVoidTy(*m_context);

    // 2. Resolve Parameter Types
    std::vector<llvm::Type*> paramTypes;
    for (const auto& param : procNode.parameters) {
        llvm::Type* pType = getLlvmType(param.type);
        if (param.isByRef) {
            pType = llvm::PointerType::get(*m_context, 0);
        }
        paramTypes.push_back(pType);
    }

    // 3. Create Function Prototype
    llvm::FunctionType* funcType = llvm::FunctionType::get(retType, paramTypes, false);
    llvm::GlobalValue::LinkageTypes linkage = procNode.isPublic ? llvm::Function::ExternalLinkage 
                                                                : llvm::Function::InternalLinkage;

    llvm::Function* func = llvm::Function::Create(funcType, linkage, procNode.name, m_module.get());

    // 4. Set Call Convention & Attributes
    func->setCallingConv(llvm::CallingConv::C);

    if (procNode.isDeclare) {
        return func; 
    }

    // Create Entry Basic Block
    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    m_builder->SetInsertPoint(entryBB);

    // 5. Store Parameters in Entry Allocas
    size_t paramIdx = 0;
    for (auto& arg : func->args()) {
        const auto& paramNode = procNode.parameters[paramIdx++];
        arg.setName(paramNode.name);

        llvm::AllocaInst* alloca = m_builder->CreateAlloca(arg.getType(), nullptr, paramNode.name + ".addr");
        m_builder->CreateStore(&arg, alloca);
        m_namedValues[paramNode.name] = alloca;
    }

    // 6. Allocate return variable if procedure is a Function
    llvm::AllocaInst* retAlloca = nullptr;
    if (procNode.isFunction) {
        retAlloca = m_builder->CreateAlloca(retType, nullptr, procNode.name + ".result");
        m_namedValues[procNode.name] = retAlloca;
    }

    // 7. Lower Body Statements
    for (const auto& stmt : procNode.body) {
        if (auto dimStmt = dynamic_cast<const DimStmtNode*>(stmt.get())) {
            emitDimStatement(*dimStmt);
        } else if (auto assignStmt = dynamic_cast<const AssignStmtNode*>(stmt.get())) {
            emitAssignStatement(*assignStmt);
        } else if (auto callStmt = dynamic_cast<CallExprASTNode*>(stmt.get())) {
            std::vector<llvm::Value*> args;
            for (auto& arg : callStmt->args) {
                args.push_back(emitExpression(arg.get()));
            }
            llvm::Function* callee = m_module->getFunction(callStmt->funcName);
            if (callee) m_builder->CreateCall(callee, args);
        }
    }

    // 8. Terminate Function Block
    if (procNode.isFunction) {
        llvm::Value* retVal = m_builder->CreateLoad(retType, retAlloca, "retval");
        m_builder->CreateRet(retVal);
    } else {
        m_builder->CreateRetVoid();
    }

    llvm::verifyFunction(*func);
    return func;
}

bool LlvmEmitter::emitModule(const ModuleNode& moduleNode) {
    for (const auto& member : moduleNode.members) {
        if (auto proc = dynamic_cast<const ProcedureNode*>(member.get())) {
            emitProcedure(*proc);
        }
    }
    
    return !llvm::verifyModule(*m_module, &llvm::errs());
}

void LlvmEmitter::printIR() const {
    m_module->print(llvm::outs(), nullptr);
}

} // namespace llbc