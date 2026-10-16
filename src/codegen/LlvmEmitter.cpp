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
        // Fallback/Opaque Structure Default to 64-bit Int/Opaque Pointer
        baseType = llvm::Type::getInt64Ty(*m_context);
    }

    // Low-Level Basic Pointer Type Translation
    if (typeSpec.pointerDepth > 0) {
        // LLVM 15+ uses opaque pointers, so all indirections map to generic ptr
        return llvm::PointerType::get(*m_context, 0); 
    }

    return baseType;
}

void LlvmEmitter::emitDimStatement(const DimStmtNode& dimNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Type* varType = getLlvmType(dimNode.type);

    // Create entry block allocation for local variable
    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* alloca = tmpBuilder.CreateAlloca(varType, nullptr, dimNode.varName);

    // Track symbol in scope table
    m_namedValues[dimNode.varName] = alloca;
}

void LlvmEmitter::emitCallStatement(const CallExprASTNode& callNode) {
    llvm::Function* callee = m_module->getFunction(callNode.funcName);
    if (!callee) {
        std::cerr << "[IR Error] Unknown function called: " << callNode.funcName << "\n";
        return;
    }

    std::vector<llvm::Value*> args;
    for (const auto& strArg : callNode.stringArgs) {
        // Create global string constant for CPtr(Pointer To Byte, "...") literals
        llvm::Value* strVal = m_builder->CreateGlobalStringPtr(strArg);
        args.push_back(strVal);
    }

    // Emit LLVM Call Instruction
    m_builder->CreateCall(callee, args);
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
            // ByRef parameters are passed as explicit pointers
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

    // --- NEW LOGIC: Do not generate a body if it's an external C declaration ---
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
        } else if (auto callStmt = dynamic_cast<const CallExprASTNode*>(stmt.get())) {
            emitCallStatement(*callStmt);
        }
    }

    // 8. Terminate Function Block
    if (procNode.isFunction) {
        llvm::Value* retVal = m_builder->CreateLoad(retType, retAlloca, "retval");
        m_builder->CreateRet(retVal);
    } else {
        m_builder->CreateRetVoid();
    }

    // Verify Function
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