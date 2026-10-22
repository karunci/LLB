/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#include "LlvmEmitter.hpp"
#include "../frontend/Diagnostic.hpp"
#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm>

namespace llbc {

static std::string toLower(const std::string& str) {
    std::string res;
    res.reserve(str.size());
    for (char c : str) res += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return res;
}

static llvm::GlobalVariable* findGlobalCaseInsensitive(llvm::Module* mod, const std::string& name) {
    if (!mod) return nullptr;
    llvm::GlobalVariable* g = mod->getGlobalVariable(name);
    if (g && !g->hasPrivateLinkage()) return g;
    std::string lowerName = toLower(name);
    for (auto& gv : mod->globals()) {
        if (gv.hasPrivateLinkage()) continue;
        if (toLower(gv.getName().str()) == lowerName) {
            return &gv;
        }
    }
    return nullptr;
}

static llvm::Function* findFunctionCaseInsensitive(llvm::Module* mod, const std::string& name) {
    if (!mod) return nullptr;
    llvm::Function* fn = mod->getFunction(name);
    if (fn) return fn;
    std::string lowerName = toLower(name);
    for (auto& f : mod->functions()) {
        if (toLower(f.getName().str()) == lowerName) {
            return &f;
        }
    }
    return nullptr;
}

LlvmEmitter::LlvmEmitter(const std::string& moduleName, bool enableDebugInfo, const std::string& targetTriple) 
    : m_enableDebugInfo(enableDebugInfo) {
    m_context = std::make_unique<llvm::LLVMContext>();
    m_module = std::make_unique<llvm::Module>(moduleName, *m_context);
    if (!targetTriple.empty()) {
        m_module->setTargetTriple(llvm::Triple(targetTriple));
    }
    m_builder = std::make_unique<llvm::IRBuilder<>>(*m_context);

    if (m_enableDebugInfo) {
        m_diBuilder = std::make_unique<llvm::DIBuilder>(*m_module);
        // LLVM debug metadata flags: Dwarf Version 4, Debug Info Version
        m_module->addModuleFlag(llvm::Module::Warning, "Debug Info Version", llvm::DEBUG_METADATA_VERSION);
        m_module->addModuleFlag(llvm::Module::Warning, "Dwarf Version", 4);
    }
}

void LlvmEmitter::emitDebugLocation(size_t line, size_t col) {
    if (!m_enableDebugInfo || m_diScopes.empty()) return;
    llvm::DILocation* loc = llvm::DILocation::get(*m_context, line, col, m_diScopes.back());
    m_builder->SetCurrentDebugLocation(loc);
}

llvm::Type* LlvmEmitter::getLlvmType(const TypeSpec& typeSpec) {
    std::string typeName = toLower(typeSpec.name);

    if (typeSpec.pointerDepth > 0) {
        return llvm::PointerType::get(*m_context, 0);
    }

    llvm::Type* baseType = nullptr;
    if (typeName == "byte" || typeName == "ubyte") {
        baseType = llvm::Type::getInt8Ty(*m_context);
    } else if (typeName == "uint16" || typeName == "int16" || typeName == "short" || typeName == "ushort") {
        baseType = llvm::Type::getInt16Ty(*m_context);
    } else if (typeName == "uint32" || typeName == "int32" || typeName == "long" || typeName == "ulong" || typeName == "integer" || typeName == "uinteger") {
        baseType = llvm::Type::getInt32Ty(*m_context);
    } else if (typeName == "uint64" || typeName == "int64" || typeName == "currency" || typeName == "decimal") {
        baseType = llvm::Type::getInt64Ty(*m_context);
    } else if (typeName == "boolean") {
        baseType = llvm::Type::getInt1Ty(*m_context);
    } else if (typeName == "single") {
        baseType = llvm::Type::getFloatTy(*m_context);
    } else if (typeName == "double") {
        baseType = llvm::Type::getDoubleTy(*m_context);
    } else if (typeName == "string") {
        baseType = llvm::PointerType::get(*m_context, 0);
    } else if (typeName == "void") {
        baseType = llvm::Type::getVoidTy(*m_context);
    } else if (typeName == "result" || typeName.rfind("result_", 0) == 0) {
        // Built-in Result sum type: { i1 is_ok, i32 err_code, i64 value }
        auto resIt = m_structTypes.find("Result");
        if (resIt != m_structTypes.end()) {
            baseType = resIt->second;
        } else {
            llvm::StructType* resSt = llvm::StructType::create(*m_context, "Result");
            resSt->setBody({
                llvm::Type::getInt1Ty(*m_context),  // is_ok
                llvm::Type::getInt32Ty(*m_context), // err_code
                llvm::Type::getInt64Ty(*m_context)  // value
            }, /*isPacked=*/false);
            m_structTypes["Result"] = resSt;
            m_structTypes["result"] = resSt;
            m_structFieldIndices["Result"] = {{"is_ok", 0}, {"isok", 0}, {"ok", 0}, {"err_code", 1}, {"errcode", 1}, {"error", 1}, {"value", 2}, {"val", 2}};
            m_structFieldIndices["result"] = m_structFieldIndices["Result"];
            TypeSpec bSpec{"Boolean"};
            TypeSpec iSpec{"Int32"};
            TypeSpec vSpec{"Int64"};
            m_structFieldTypes["Result"] = {{"is_ok", bSpec}, {"isok", bSpec}, {"ok", bSpec}, {"err_code", iSpec}, {"errcode", iSpec}, {"error", iSpec}, {"value", vSpec}, {"val", vSpec}};
            m_structFieldTypes["result"] = m_structFieldTypes["Result"];
            baseType = resSt;
        }
    } else {
        std::string resolvedName = typeSpec.name;
        if (!typeSpec.typeArgs.empty()) {
            resolvedName = instantiateGenericStruct(typeSpec);
        }
        auto it = m_structTypes.find(resolvedName);
        if (it != m_structTypes.end()) {
            baseType = it->second;
        } else {
            auto itLower = m_structTypes.find(toLower(resolvedName));
            if (itLower != m_structTypes.end()) {
                baseType = itLower->second;
            } else if (m_enums.count(resolvedName) || m_enums.count(toLower(resolvedName))) {
                baseType = llvm::Type::getInt32Ty(*m_context);
            } else if (m_delegates.count(resolvedName) || m_delegates.count(toLower(resolvedName))) {
                baseType = llvm::PointerType::get(*m_context, 0);
            } else if (m_interfaces.count(resolvedName) || m_interfaces.count(toLower(resolvedName))) {
                baseType = llvm::PointerType::get(*m_context, 0);
            } else {
                Diagnostic::report(m_sourceFilePath, m_currentLine, m_currentCol, true,
                                   "Undeclared type '" + typeSpec.name + "'.", m_sourceText);
                m_hadError = true;
                baseType = llvm::Type::getInt64Ty(*m_context);
            }
        }
    }


    if (typeSpec.isArray && typeSpec.arraySize > 0) {
        return llvm::ArrayType::get(baseType, typeSpec.arraySize);
    }

    return baseType;
}

llvm::Type* LlvmEmitter::getElementType(const TypeSpec& typeSpec) {
    if (toLower(typeSpec.name) == "string") {
        return llvm::Type::getInt8Ty(*m_context);
    }
    TypeSpec decayed = typeSpec;
    if (decayed.isArray) {
        decayed.isArray = false;
        decayed.arraySize = 0;
        decayed.dimensions.clear();
        return getLlvmType(decayed);
    }
    if (decayed.pointerDepth > 0) {
        decayed.pointerDepth--;
        return getLlvmType(decayed);
    }
    return llvm::Type::getInt8Ty(*m_context);
}

llvm::Value* LlvmEmitter::coerceType(llvm::Value* val, llvm::Type* targetType) {
    if (!val || val->getType() == targetType) return val;

    llvm::Type* srcType = val->getType();

    // Integer to Integer
    if (srcType->isIntegerTy() && targetType->isIntegerTy()) {
        unsigned srcBits = srcType->getIntegerBitWidth();
        unsigned dstBits = targetType->getIntegerBitWidth();
        if (srcBits < dstBits) {
            return m_builder->CreateZExt(val, targetType, "zext");
        } else if (srcBits > dstBits) {
            return m_builder->CreateTrunc(val, targetType, "trunc");
        }
        return val;
    }

    // Integer to Pointer
    if (srcType->isIntegerTy() && targetType->isPointerTy()) {
        return m_builder->CreateIntToPtr(val, targetType, "inttoptr");
    }

    // Pointer to Integer
    if (srcType->isPointerTy() && targetType->isIntegerTy()) {
        return m_builder->CreatePtrToInt(val, targetType, "ptrtoint");
    }

    // Pointer to Pointer
    if (srcType->isPointerTy() && targetType->isPointerTy()) {
        return m_builder->CreatePointerCast(val, targetType, "ptrcast");
    }

    // Floating-Point conversions
    if (srcType->isFloatingPointTy() && targetType->isFloatingPointTy()) {
        if (srcType->isFloatTy() && targetType->isDoubleTy()) {
            return m_builder->CreateFPExt(val, targetType, "fpext");
        } else if (srcType->isDoubleTy() && targetType->isFloatTy()) {
            return m_builder->CreateFPTrunc(val, targetType, "fptrunc");
        }
        return val;
    }
    if (srcType->isIntegerTy() && targetType->isFloatingPointTy()) {
        return m_builder->CreateSIToFP(val, targetType, "sitofp");
    }
    if (srcType->isFloatingPointTy() && targetType->isIntegerTy()) {
        return m_builder->CreateFPToSI(val, targetType, "fptosi");
    }

    return val;
}

llvm::Value* LlvmEmitter::getPointerToExpr(ExprASTNode* expr) {
    if (!expr) return nullptr;

    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_namedValues.find(var->name);
        if (it == m_namedValues.end()) {
            it = m_namedValues.find(toLower(var->name));
        }
        if (it != m_namedValues.end()) {
            auto tIt = m_variableTypes.find(var->name);
            if (tIt == m_variableTypes.end()) {
                tIt = m_variableTypes.find(toLower(var->name));
            }
            if (tIt != m_variableTypes.end()) {
                if (tIt->second.pointerDepth > 0 || m_byRefParams.count(var->name) || m_byRefParams.count(toLower(var->name))) {
                    return m_builder->CreateLoad(it->second->getAllocatedType(), it->second, var->name);
                }
            }
            return it->second;
        }
        llvm::GlobalVariable* gVar = m_module->getGlobalVariable(var->name);
        if (!gVar) {
            gVar = findGlobalCaseInsensitive(m_module.get(), var->name);
        }
        if (gVar) {
            return gVar;
        }
        return nullptr;
    }

    if (auto idx = dynamic_cast<IndexExprASTNode*>(expr)) {
        llvm::Value* baseVal = nullptr;
        TypeSpec baseType;
        if (auto varBase = dynamic_cast<VariableExprASTNode*>(idx->base.get())) {
            auto it = m_namedValues.find(varBase->name);
            auto tIt = m_variableTypes.find(varBase->name);
            if (tIt != m_variableTypes.end()) baseType = tIt->second;
            if (it != m_namedValues.end()) {
                if (baseType.isArray) {
                    baseVal = it->second;
                } else {
                    baseVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, varBase->name);
                }
            } else {
                llvm::GlobalVariable* gVar = m_module->getGlobalVariable(varBase->name);
                if (!gVar) gVar = findGlobalCaseInsensitive(m_module.get(), varBase->name);
                if (gVar) {
                    baseVal = gVar;
                    if (baseType.name.empty()) {
                        baseType.name = gVar->getValueType()->isStructTy() ? gVar->getValueType()->getStructName().str() : "";
                        baseType.isArray = true;
                    }
                }
            }
        }
        if (!baseVal) {
            baseVal = emitExpression(idx->base.get());
        }

        llvm::Value* flatIdx = nullptr;
        if (!idx->indices.empty()) {
            flatIdx = emitExpression(idx->indices[0].get());
        } else if (idx->index) {
            flatIdx = emitExpression(idx->index.get());
        }

        if (baseVal && flatIdx) {
            llvm::Type* elemType = nullptr;
            if (baseType.pointerDepth > 0 || baseType.isArray) {
                elemType = getElementType(baseType);
            } else if (baseVal->getType()->isPointerTy()) {
                elemType = llvm::Type::getInt32Ty(*m_context);
            } else {
                elemType = llvm::Type::getInt8Ty(*m_context);
            }
            flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));
            return m_builder->CreateGEP(elemType, baseVal, flatIdx, "idxgep");
        }
    }

    if (auto member = dynamic_cast<MemberAccessExprASTNode*>(expr)) {
        llvm::Value* basePtr = member->base ? getPointerToExpr(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().first : nullptr);
        if (basePtr) {
            std::string memberLower = toLower(member->memberName);
            TypeSpec baseType = member->base ? deduceExprType(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().second : TypeSpec());
            std::string explicitStructName = !baseType.name.empty() ? toLower(baseType.name) : "";

            for (const auto& pair : m_structFieldIndices) {
                if (!explicitStructName.empty() && toLower(pair.first) != explicitStructName) {
                    continue;
                }
                auto fIt = pair.second.find(memberLower);
                if (fIt != pair.second.end()) {
                    unsigned fieldIdx = fIt->second;
                    auto stIt = m_structTypes.find(pair.first);
                    if (stIt != m_structTypes.end()) {
                        if (m_unionTypes.count(pair.first)) {
                            return basePtr;
                        }
                        return m_builder->CreateStructGEP(stIt->second, basePtr, fieldIdx, "membergep");
                    }
                }
            }
        }
    }

    // CallExprASTNode: array or pointer indexing like entriesPtr(slot1) or idtEntries(0)
    // Returns the GEP (pointer to element) without loading the value.
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        if (!call->calleeExpr && !call->args.empty()) {
            auto it = m_namedValues.find(call->funcName);
            auto tIt = m_variableTypes.find(call->funcName);
            if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(call->funcName));
            llvm::GlobalVariable* gVar = nullptr;
            if (it == m_namedValues.end() && tIt != m_variableTypes.end()) {
                gVar = findGlobalCaseInsensitive(m_module.get(), call->funcName);
            }
            if (it != m_namedValues.end() || gVar) {
                TypeSpec baseType = (tIt != m_variableTypes.end()) ? tIt->second : TypeSpec();
                if (gVar && baseType.name.empty() && gVar->getValueType()->isArrayTy()) {
                    baseType.isArray = true;
                }
                llvm::Value* baseVal = nullptr;
                if (it != m_namedValues.end()) {
                    if (baseType.isArray) {
                        baseVal = it->second;
                    } else {
                        baseVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, call->funcName);
                    }
                } else if (gVar) {
                    baseVal = gVar;
                }

                if (baseVal && (baseType.pointerDepth > 0 || baseType.isArray)) {
                    llvm::Value* idxVal = emitExpression(call->args[0].get());
                    if (idxVal) {
                        llvm::Type* elemType = getElementType(baseType);
                        idxVal = coerceType(idxVal, llvm::Type::getInt64Ty(*m_context));
                        return m_builder->CreateGEP(elemType, baseVal, idxVal, "callidxgep");
                    }
                }
            }
        }
    }

    llvm::Value* val = emitExpression(expr);
    if (val && val->getType()->isPointerTy()) {
        return val;
    }
    return nullptr;
}

bool LlvmEmitter::isStringExpr(ExprASTNode* expr) {
    if (!expr) return false;
    if (dynamic_cast<StringExprASTNode*>(expr)) return true;
    TypeSpec ts = deduceExprType(expr);
    std::string lowerTsName = toLower(ts.name);
    if (lowerTsName == "string" && ts.pointerDepth == 0 && !ts.isArray) return true;
    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_variableTypes.find(var->name);
        if (it == m_variableTypes.end()) it = m_variableTypes.find(toLower(var->name));
        if (it != m_variableTypes.end()) {
            std::string vtName = toLower(it->second.name);
            if (vtName == "string" && it->second.pointerDepth == 0 && !it->second.isArray) return true;
        }
    }
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        std::string fn = toLower(call->funcName);
        if (fn == "mid" || fn == "mid$" ||
            fn == "left" || fn == "left$" ||
            fn == "right" || fn == "right$" ||
            fn == "trim" || fn == "trim$" ||
            fn == "ltrim" || fn == "ltrim$" ||
            fn == "rtrim" || fn == "rtrim$" ||
            fn == "chr" || fn == "chr$" ||
            fn == "cstr" || fn == "str" || fn == "str$") {
            return true;
        }
    }
    if (auto bin = dynamic_cast<BinaryExprASTNode*>(expr)) {
        if (bin->op == "&") return true;
        if (bin->op == "+" && (isStringExpr(bin->lhs.get()) || isStringExpr(bin->rhs.get()))) return true;
    }
    if (auto mem = dynamic_cast<MemberAccessExprASTNode*>(expr)) {
        if (mem->base) {
            if (auto varBase = dynamic_cast<VariableExprASTNode*>(mem->base.get())) {
                if (toLower(varBase->name) == "err") {
                    std::string prop = toLower(mem->memberName);
                    if (prop == "description" || prop == "source") return true;
                }
            }
        }
    }
    return false;
}

bool LlvmEmitter::isUnsignedExpr(ExprASTNode* expr) {
    if (!expr) return false;
    auto isUnsignedType = [](const std::string& name) {
        std::string t = toLower(name);
        return (t == "byte" || t == "ubyte" || t == "uint8" || t == "uint16" || 
                t == "ushort" || t == "uint32" || t == "ulong" || 
                t == "uinteger" || t == "uint64" || t == "uintptr");
    };

    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_variableTypes.find(var->name);
        if (it != m_variableTypes.end()) {
            if (it->second.pointerDepth > 0) return true;
            return isUnsignedType(it->second.name);
        }
    }
    if (auto cast = dynamic_cast<CastExprASTNode*>(expr)) {
        if (cast->targetType.pointerDepth > 0) return true;
        return isUnsignedType(cast->targetType.name);
    }
    if (auto mem = dynamic_cast<MemberAccessExprASTNode*>(expr)) {
        if (auto baseVar = dynamic_cast<VariableExprASTNode*>(mem->base.get())) {
            auto bIt = m_variableTypes.find(baseVar->name);
            if (bIt != m_variableTypes.end()) {
                std::string sName = toLower(bIt->second.name);
                auto sIt = m_structFieldTypes.find(sName);
                if (sIt != m_structFieldTypes.end()) {
                    auto fIt = sIt->second.find(toLower(mem->memberName));
                    if (fIt != sIt->second.end()) {
                        if (fIt->second.pointerDepth > 0) return true;
                        return isUnsignedType(fIt->second.name);
                    }
                }
            }
        }
    }
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        auto it = m_variableTypes.find(call->funcName);
        if (it != m_variableTypes.end()) {
            if (it->second.pointerDepth > 0) return true;
            return isUnsignedType(it->second.name);
        }
        auto pIt = m_procReturnTypes.find(toLower(call->funcName));
        if (pIt != m_procReturnTypes.end()) {
            if (pIt->second.pointerDepth > 0) return true;
            return isUnsignedType(pIt->second.name);
        }
    }
    if (auto bin = dynamic_cast<BinaryExprASTNode*>(expr)) {
        return isUnsignedExpr(bin->lhs.get()) || isUnsignedExpr(bin->rhs.get());
    }
    return false;
}

TypeSpec LlvmEmitter::deduceExprType(ExprASTNode* expr) {
    TypeSpec res;
    if (!expr) return res;

    if (dynamic_cast<StringExprASTNode*>(expr)) {
        res.name = "String";
        return res;
    }
    if (auto num = dynamic_cast<NumberExprASTNode*>(expr)) {
        if (num->typeHint == "Boolean") {
            res.name = "Boolean";
            return res;
        }
        if (num->isFloat) {
            res.name = "Double";
        } else {
            res.name = "Int32";
        }
        return res;
    }
    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_variableTypes.find(var->name);
        if (it != m_variableTypes.end()) return it->second;
        auto itLower = m_variableTypes.find(toLower(var->name));
        if (itLower != m_variableTypes.end()) return itLower->second;
    }
    if (auto cast = dynamic_cast<CastExprASTNode*>(expr)) {
        return cast->targetType;
    }
    if (auto newExpr = dynamic_cast<NewExprASTNode*>(expr)) {
        return newExpr->typeSpec;
    }
    if (auto mem = dynamic_cast<MemberAccessExprASTNode*>(expr)) {
        if (mem->base) {
            if (auto varBase = dynamic_cast<VariableExprASTNode*>(mem->base.get())) {
                if (toLower(varBase->name) == "err") {
                    std::string prop = toLower(mem->memberName);
                    if (prop == "number") return TypeSpec{"Int32"};
                    if (prop == "source" || prop == "description") {
                        TypeSpec strSpec{"Byte"};
                        strSpec.pointerDepth = 1;
                        return strSpec;
                    }
                }
            }
        }
        TypeSpec baseType = deduceExprType(mem->base.get());
        std::string sName = toLower(baseType.name);
        auto sIt = m_structFieldTypes.find(sName);
        if (sIt != m_structFieldTypes.end()) {
            auto fIt = sIt->second.find(toLower(mem->memberName));
            if (fIt != sIt->second.end()) return fIt->second;
        }
    }
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        auto it = m_variableTypes.find(call->funcName);
        if (it != m_variableTypes.end()) {
            TypeSpec elemType = it->second;
            if (elemType.isArray) {
                elemType.isArray = false;
                elemType.arraySize = 0;
                elemType.dimensions.clear();
            } else if (elemType.pointerDepth > 0) {
                elemType.pointerDepth--;
            }
            return elemType;
        }
        std::string lowerCall = toLower(call->funcName);
        if (lowerCall == "ok" || lowerCall == "err") {
            TypeSpec r;
            r.name = "Result";
            return r;
        }
        if (lowerCall == "isok") {
            TypeSpec b;
            b.name = "Boolean";
            return b;
        }
        if (lowerCall == "eof") {
            TypeSpec b;
            b.name = "Boolean";
            return b;
        }
        if (lowerCall == "lof") {
            TypeSpec l;
            l.name = "Int64";
            return l;
        }
        auto pIt = m_procReturnTypes.find(lowerCall);
        if (pIt != m_procReturnTypes.end()) return pIt->second;
    }
    if (auto lambda = dynamic_cast<LambdaExprASTNode*>(expr)) {
        TypeSpec fnPtrSpec;
        fnPtrSpec.name = "Pointer";
        fnPtrSpec.pointerDepth = 1;
        return fnPtrSpec;
    }
    if (auto idx = dynamic_cast<IndexExprASTNode*>(expr)) {
        TypeSpec elemType = deduceExprType(idx->base.get());
        if (elemType.isArray) {
            elemType.isArray = false;
            elemType.arraySize = 0;
            elemType.dimensions.clear();
        } else if (elemType.pointerDepth > 0) {
            elemType.pointerDepth--;
        }
        return elemType;
    }
    if (auto bin = dynamic_cast<BinaryExprASTNode*>(expr)) {
        std::string op = toLower(bin->op);
        if (op == "&" || (op == "+" && (isStringExpr(bin->lhs.get()) || isStringExpr(bin->rhs.get())))) {
            res.name = "String";
            return res;
        }
        if (op == "=" || op == "<>" || op == "<" || op == "<=" || op == ">" || op == ">=" ||
            op == "and" || op == "or" || op == "xor" || op == "like") {
            res.name = "Boolean";
            return res;
        }
        return deduceExprType(bin->lhs.get());
    }
    if (auto un = dynamic_cast<UnaryExprASTNode*>(expr)) {
        if (toLower(un->op) == "not") {
            res.name = "Boolean";
            return res;
        }
        return deduceExprType(un->expr.get());
    }
    return res;
}

void LlvmEmitter::emitBoundsCheck(llvm::Value* indexVal, uint64_t bound, const std::string& varName) {
    if (m_currentProcIsUnsafe || !indexVal) return;

    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    if (!currentFunc) return;

    llvm::Value* idx64 = coerceType(indexVal, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* boundVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), bound);

    // Unsigned comparison: if idx < 0 or idx >= bound, (uint64_t)idx >= bound is true
    llvm::Value* outOfBounds = m_builder->CreateICmpUGE(idx64, boundVal, "is_oob");

    llvm::BasicBlock* panicBB = llvm::BasicBlock::Create(*m_context, "panic.oob", currentFunc);
    llvm::BasicBlock* passBB = llvm::BasicBlock::Create(*m_context, "pass.bounds", currentFunc);

    m_builder->CreateCondBr(outOfBounds, panicBB, passBB);

    m_builder->SetInsertPoint(panicBB);
    llvm::Function* panicFn = getOrCreatePanic();
    llvm::Value* fileStr = m_builder->CreateGlobalString(m_sourceFilePath, "panic.file");
    llvm::Value* reasonStr = m_builder->CreateGlobalString("Subscript out of range (" + varName + ")", "panic.reason");
    llvm::Value* lineVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentLine));
    llvm::Value* colVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentCol));
    m_builder->CreateCall(panicFn, {fileStr, lineVal, colVal, reasonStr});
    m_builder->CreateUnreachable();

    m_builder->SetInsertPoint(passBB);
}

void LlvmEmitter::emitNullCheck(llvm::Value* ptrVal, const std::string& exprName) {
    if (m_currentProcIsUnsafe || !ptrVal || !ptrVal->getType()->isPointerTy()) return;

    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    if (!currentFunc) return;

    llvm::Value* isNull = m_builder->CreateIsNull(ptrVal, "is_null_guard");

    llvm::BasicBlock* panicBB = llvm::BasicBlock::Create(*m_context, "panic.null", currentFunc);
    llvm::BasicBlock* passBB = llvm::BasicBlock::Create(*m_context, "pass.null", currentFunc);

    m_builder->CreateCondBr(isNull, panicBB, passBB);

    m_builder->SetInsertPoint(panicBB);
    llvm::Function* panicFn = getOrCreatePanic();
    llvm::Value* fileStr = m_builder->CreateGlobalString(m_sourceFilePath, "panic.file");
    llvm::Value* reasonStr = m_builder->CreateGlobalString("Null pointer dereference (" + exprName + ")", "panic.reason");
    llvm::Value* lineVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentLine));
    llvm::Value* colVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentCol));
    m_builder->CreateCall(panicFn, {fileStr, lineVal, colVal, reasonStr});
    m_builder->CreateUnreachable();

    m_builder->SetInsertPoint(passBB);
}

void LlvmEmitter::emitZeroDivCheck(llvm::Value* divisor, const std::string& opName) {
    if (!divisor || m_currentProcIsUnsafe) return;
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    if (!currentFunc) return;

    llvm::Value* zeroVal = llvm::ConstantInt::get(divisor->getType(), 0);
    llvm::Value* isZero = m_builder->CreateICmpEQ(divisor, zeroVal, "is_zero_div");

    llvm::BasicBlock* panicBB = llvm::BasicBlock::Create(*m_context, "panic.dbz", currentFunc);
    llvm::BasicBlock* passBB = llvm::BasicBlock::Create(*m_context, "pass.div", currentFunc);

    m_builder->CreateCondBr(isZero, panicBB, passBB);

    m_builder->SetInsertPoint(panicBB);
    llvm::Function* panicFn = getOrCreatePanic();
    llvm::Value* fileStr = m_builder->CreateGlobalString(m_sourceFilePath, "panic.file");
    llvm::Value* reasonStr = m_builder->CreateGlobalString("Division by zero in operator '" + opName + "'", "panic.reason");
    llvm::Value* lineVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentLine));
    llvm::Value* colVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<uint32_t>(m_currentCol));
    m_builder->CreateCall(panicFn, {fileStr, lineVal, colVal, reasonStr});
    m_builder->CreateUnreachable();

    m_builder->SetInsertPoint(passBB);
}

void LlvmEmitter::checkConstantOverflow(const TypeSpec& targetType, ExprASTNode* expr, size_t line, size_t col) {
    if (!expr) return;
    if (auto num = dynamic_cast<NumberExprASTNode*>(expr)) {
        if (num->isFloat) return;
        std::string tName = toLower(targetType.name);
        int64_t v = num->val;
        bool overflow = false;
        int64_t minB = 0, maxB = 0;
        if (targetType.pointerDepth == 0 && !targetType.isArray) {
            if (tName == "byte" || tName == "ubyte" || tName == "uint8") {
                minB = 0; maxB = 255;
                if (v < minB || v > maxB) overflow = true;
            } else if (tName == "int8" || tName == "sbyte") {
                minB = -128; maxB = 127;
                if (v < minB || v > maxB) overflow = true;
            } else if (tName == "uint16" || tName == "ushort") {
                minB = 0; maxB = 65535;
                if (v < minB || v > maxB) overflow = true;
            } else if (tName == "int16" || tName == "short") {
                minB = -32768; maxB = 32767;
                if (v < minB || v > maxB) overflow = true;
            } else if (tName == "uint32" || tName == "ulong") {
                minB = 0; maxB = 4294967295ULL;
                if (v < 0 || static_cast<uint64_t>(v) > 4294967295ULL) overflow = true;
            } else if (tName == "int32" || tName == "long") {
                minB = -2147483648LL; maxB = 2147483647LL;
                if (v < minB || v > maxB) overflow = true;
            }
        }
        if (overflow) {
            Diagnostic::report(m_sourceFilePath, line > 0 ? line : m_currentLine, col > 0 ? col : m_currentCol,
                               true, "Integer literal " + std::to_string(v) + " overflows target type '" + targetType.name + "' [" + std::to_string(minB) + ".." + std::to_string(maxB) + "]", m_sourceText);
            m_hadError = true;
        }
    }
}

llvm::Function* LlvmEmitter::getOrCreatePanic() {
    llvm::Function* func = m_module->getFunction("__llbc_panic");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getVoidTy(*m_context),
            {
                llvm::PointerType::get(*m_context, 0), // file
                llvm::Type::getInt32Ty(*m_context),    // line
                llvm::Type::getInt32Ty(*m_context),    // col
                llvm::PointerType::get(*m_context, 0)  // reason
            },
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_panic", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    m_builder->SetInsertPoint(entryBB);

    llvm::Value* fileArg = func->getArg(0);
    llvm::Value* lineArg = func->getArg(1);
    llvm::Value* colArg = func->getArg(2);
    llvm::Value* reasonArg = func->getArg(3);

    // Formatted diagnostic output matching LLB diagnostic styling
    llvm::Value* fmt = m_builder->CreateGlobalString("\n\033[1;31m[LLB Runtime Panic]\033[0m %s:%d:%d: \033[1;37m%s\033[0m\n", "panic.fmt");

    llvm::FunctionType* dprintfTy = llvm::FunctionType::get(
        llvm::Type::getInt32Ty(*m_context),
        {llvm::Type::getInt32Ty(*m_context), llvm::PointerType::get(*m_context, 0)},
        true
    );
    llvm::FunctionCallee dprintfFn = m_module->getOrInsertFunction("dprintf", dprintfTy);
    llvm::Value* stderrFd = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 2);
    m_builder->CreateCall(dprintfFn, {stderrFd, fmt, fileArg, lineArg, colArg, reasonArg});

    llvm::FunctionType* abortTy = llvm::FunctionType::get(
        llvm::Type::getVoidTy(*m_context),
        false
    );
    llvm::FunctionCallee abortFn = m_module->getOrInsertFunction("abort", abortTy);
    m_builder->CreateCall(abortFn, {});

    llvm::Function* trapFn = llvm::Intrinsic::getOrInsertDeclaration(m_module.get(), llvm::Intrinsic::trap);
    m_builder->CreateCall(trapFn, {});
    m_builder->CreateUnreachable();

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateMalloc() {
    llvm::Function* func = m_module->getFunction("__llbc_allocate_instance");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_allocate_instance", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    const uint64_t HEAP_SIZE = 1048576;
    llvm::GlobalVariable* heapVar = m_module->getGlobalVariable("__llbc_heap_buffer");
    if (!heapVar) {
        llvm::ArrayType* arrTy = llvm::ArrayType::get(llvm::Type::getInt8Ty(*m_context), HEAP_SIZE);
        heapVar = new llvm::GlobalVariable(
            *m_module,
            arrTy,
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantAggregateZero::get(arrTy),
            "__llbc_heap_buffer"
        );
    }

    llvm::GlobalVariable* offsetVar = m_module->getGlobalVariable("__llbc_heap_offset");
    if (!offsetVar) {
        offsetVar = new llvm::GlobalVariable(
            *m_module,
            llvm::Type::getInt64Ty(*m_context),
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0),
            "__llbc_heap_offset"
        );
    }

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* okBB = llvm::BasicBlock::Create(*m_context, "ok", func);
    llvm::BasicBlock* oomBB = llvm::BasicBlock::Create(*m_context, "oom", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sizeArg = func->getArg(0);

    llvm::Value* add15 = m_builder->CreateAdd(sizeArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 15), "add15");
    llvm::Value* alignedSize = m_builder->CreateAnd(add15, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), ~15ULL), "aligned");

    llvm::Value* curOffset = m_builder->CreateLoad(llvm::Type::getInt64Ty(*m_context), offsetVar, "curoffset");
    llvm::Value* newOffset = m_builder->CreateAdd(curOffset, alignedSize, "newoffset");

    llvm::Value* hasSpace = m_builder->CreateICmpULE(newOffset, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), HEAP_SIZE), "hasspace");
    m_builder->CreateCondBr(hasSpace, okBB, oomBB);

    m_builder->SetInsertPoint(okBB);
    m_builder->CreateStore(newOffset, offsetVar);
    llvm::Value* ptr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), heapVar, curOffset, "allocptr");
    m_builder->CreateRet(ptr);

    m_builder->SetInsertPoint(oomBB);
    m_builder->CreateRet(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)));

    if (prevBB) {
        m_builder->SetInsertPoint(prevBB, prevPoint);
    }
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrlen() {
    llvm::Function* func = m_module->getFunction("__llbc_strlen");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt64Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_strlen", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* loopHeaderBB = llvm::BasicBlock::Create(*m_context, "loop.header", func);
    llvm::BasicBlock* loopBodyBB = llvm::BasicBlock::Create(*m_context, "loop.body", func);
    llvm::BasicBlock* exitBB = llvm::BasicBlock::Create(*m_context, "exit", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, exitBB, loopHeaderBB);

    m_builder->SetInsertPoint(loopHeaderBB);
    llvm::PHINode* lenPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "len");
    lenPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* ptr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, lenPhi, "ptr");
    llvm::Value* ch = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), ptr, "ch");
    llvm::Value* isZero = m_builder->CreateICmpEQ(ch, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "iszero");
    m_builder->CreateCondBr(isZero, exitBB, loopBodyBB);

    m_builder->SetInsertPoint(loopBodyBB);
    llvm::Value* nextLen = m_builder->CreateAdd(lenPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextlen");
    lenPhi->addIncoming(nextLen, loopBodyBB);
    m_builder->CreateBr(loopHeaderBB);

    m_builder->SetInsertPoint(exitBB);
    llvm::PHINode* retPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "retlen");
    retPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);
    retPhi->addIncoming(lenPhi, loopHeaderBB);
    m_builder->CreateRet(retPhi);

    if (prevBB) {
        m_builder->SetInsertPoint(prevBB, prevPoint);
    }
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateI64ToStr() {
    llvm::Function* func = m_module->getFunction("__llbc_i64_to_str");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_i64_to_str", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* checkZeroBB = llvm::BasicBlock::Create(*m_context, "check.zero", func);
    llvm::BasicBlock* isZeroBB = llvm::BasicBlock::Create(*m_context, "is.zero", func);
    llvm::BasicBlock* nonZeroBB = llvm::BasicBlock::Create(*m_context, "non.zero", func);
    llvm::BasicBlock* digitsLoopBB = llvm::BasicBlock::Create(*m_context, "digits.loop", func);
    llvm::BasicBlock* digitsBodyBB = llvm::BasicBlock::Create(*m_context, "digits.body", func);
    llvm::BasicBlock* reverseSetupBB = llvm::BasicBlock::Create(*m_context, "reverse.setup", func);
    llvm::BasicBlock* writeMinusBB = llvm::BasicBlock::Create(*m_context, "write.minus", func);
    llvm::BasicBlock* reverseLoopBB = llvm::BasicBlock::Create(*m_context, "reverse.loop", func);
    llvm::BasicBlock* reverseBodyBB = llvm::BasicBlock::Create(*m_context, "reverse.body", func);
    llvm::BasicBlock* finishBB = llvm::BasicBlock::Create(*m_context, "finish", func);
    llvm::BasicBlock* nullRetBB = llvm::BasicBlock::Create(*m_context, "null.ret", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* bufArg = func->getArg(0);
    llvm::Argument* valArg = func->getArg(1);

    llvm::Value* isBufNull = m_builder->CreateIsNull(bufArg, "isbufnull");
    m_builder->CreateCondBr(isBufNull, nullRetBB, checkZeroBB);

    m_builder->SetInsertPoint(nullRetBB);
    m_builder->CreateRet(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)));

    m_builder->SetInsertPoint(checkZeroBB);
    llvm::Value* isValZero = m_builder->CreateICmpEQ(valArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "isvalzero");
    m_builder->CreateCondBr(isValZero, isZeroBB, nonZeroBB);

    // val == 0: buf[0] = '0', buf[1] = 0, return buf
    m_builder->SetInsertPoint(isZeroBB);
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), bufArg);
    llvm::Value* buf1 = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), bufArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1));
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), buf1);
    m_builder->CreateRet(bufArg);

    // non-zero:
    m_builder->SetInsertPoint(nonZeroBB);
    llvm::AllocaInst* tmpAlloca = m_builder->CreateAlloca(llvm::ArrayType::get(llvm::Type::getInt8Ty(*m_context), 32), nullptr, "tmp");
    llvm::Value* isNeg = m_builder->CreateICmpSLT(valArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "isneg");
    llvm::Value* negVal = m_builder->CreateNeg(valArg, "negval");
    llvm::Value* absVal = m_builder->CreateSelect(isNeg, negVal, valArg, "absval");
    m_builder->CreateBr(digitsLoopBB);

    // digits extraction loop:
    m_builder->SetInsertPoint(digitsLoopBB);
    llvm::PHINode* uvalPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "uval");
    uvalPhi->addIncoming(absVal, nonZeroBB);
    llvm::PHINode* idxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "idx");
    idxPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), nonZeroBB);

    llvm::Value* moreDigits = m_builder->CreateICmpUGT(uvalPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "moredigits");
    m_builder->CreateCondBr(moreDigits, digitsBodyBB, reverseSetupBB);

    m_builder->SetInsertPoint(digitsBodyBB);
    llvm::Value* rem = m_builder->CreateURem(uvalPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 10), "rem");
    llvm::Value* rem8 = m_builder->CreateTrunc(rem, llvm::Type::getInt8Ty(*m_context), "rem8");
    llvm::Value* chDigit = m_builder->CreateAdd(rem8, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), "chdigit");
    llvm::Value* tmpSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), tmpAlloca, idxPhi);
    m_builder->CreateStore(chDigit, tmpSlot);

    llvm::Value* nextUval = m_builder->CreateUDiv(uvalPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 10), "nextuval");
    llvm::Value* nextIdx = m_builder->CreateAdd(idxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextidx");
    uvalPhi->addIncoming(nextUval, digitsBodyBB);
    idxPhi->addIncoming(nextIdx, digitsBodyBB);
    m_builder->CreateBr(digitsLoopBB);

    // reverse setup: check if negative
    m_builder->SetInsertPoint(reverseSetupBB);
    m_builder->CreateCondBr(isNeg, writeMinusBB, reverseLoopBB);

    m_builder->SetInsertPoint(writeMinusBB);
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '-'), bufArg);
    m_builder->CreateBr(reverseLoopBB);

    // reverse loop:
    m_builder->SetInsertPoint(reverseLoopBB);
    llvm::PHINode* outIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 3, "outidx");
    outIdxPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), reverseSetupBB);
    outIdxPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), writeMinusBB);

    llvm::PHINode* revIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 3, "revidx");
    revIdxPhi->addIncoming(idxPhi, reverseSetupBB);
    revIdxPhi->addIncoming(idxPhi, writeMinusBB);

    llvm::Value* hasMoreChars = m_builder->CreateICmpUGT(revIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "hasmore");
    m_builder->CreateCondBr(hasMoreChars, reverseBodyBB, finishBB);

    m_builder->SetInsertPoint(reverseBodyBB);
    llvm::Value* readIdx = m_builder->CreateSub(revIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "readidx");
    llvm::Value* readSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), tmpAlloca, readIdx);
    llvm::Value* readCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), readSlot, "readch");
    llvm::Value* writeSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), bufArg, outIdxPhi);
    m_builder->CreateStore(readCh, writeSlot);

    llvm::Value* nextOutIdx = m_builder->CreateAdd(outIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextoutidx");
    outIdxPhi->addIncoming(nextOutIdx, reverseBodyBB);
    revIdxPhi->addIncoming(readIdx, reverseBodyBB);
    m_builder->CreateBr(reverseLoopBB);

    // finish:
    m_builder->SetInsertPoint(finishBB);
    llvm::Value* nullSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), bufArg, outIdxPhi);
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), nullSlot);
    m_builder->CreateRet(bufArg);

    if (prevBB) {
        m_builder->SetInsertPoint(prevBB, prevPoint);
    }
    return func;
}

llvm::Value* LlvmEmitter::convertToString(llvm::Value* val) {
    if (!val) return nullptr;
    if (val->getType()->isPointerTy()) {
        return val;
    }
    if (val->getType()->isFloatingPointTy()) {
        llvm::Value* val64 = m_builder->CreateFPToSI(val, llvm::Type::getInt64Ty(*m_context), "fptosi");
        llvm::Function* mallocFn = getOrCreateMalloc();
        llvm::Value* bufSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 32);
        llvm::Value* buf = m_builder->CreateCall(mallocFn, {bufSize}, "strbuf");
        llvm::Function* i64ToStrFn = getOrCreateI64ToStr();
        m_builder->CreateCall(i64ToStrFn, {buf, val64});
        return buf;
    }
    if (val->getType()->isIntegerTy()) {
        llvm::Function* mallocFn = getOrCreateMalloc();
        llvm::Value* bufSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 32);
        llvm::Value* buf = m_builder->CreateCall(mallocFn, {bufSize}, "strbuf");

        llvm::Value* val64 = val;
        if (val->getType()->getIntegerBitWidth() < 64) {
            val64 = m_builder->CreateSExt(val, llvm::Type::getInt64Ty(*m_context), "sext64");
        } else if (val->getType()->getIntegerBitWidth() > 64) {
            val64 = m_builder->CreateTrunc(val, llvm::Type::getInt64Ty(*m_context), "trunc64");
        }

        llvm::Function* i64ToStrFn = getOrCreateI64ToStr();
        m_builder->CreateCall(i64ToStrFn, {buf, val64});
        return buf;
    }
    return val;
}

llvm::Value* LlvmEmitter::concatStrings(llvm::Value* s1, llvm::Value* s2) {
    if (!s1 || !s2) return nullptr;
    s1 = convertToString(s1);
    s2 = convertToString(s2);

    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Function* mallocFn = getOrCreateMalloc();

    llvm::Value* len1 = m_builder->CreateCall(strlenFn, {s1}, "len1");
    llvm::Value* len2 = m_builder->CreateCall(strlenFn, {s2}, "len2");

    llvm::Value* sumLen = m_builder->CreateAdd(len1, len2, "sumlen");
    llvm::Value* totalLen = m_builder->CreateAdd(sumLen, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "totallen");

    llvm::Value* dest = m_builder->CreateCall(mallocFn, {totalLen}, "concat_dest");

    m_builder->CreateMemCpy(dest, llvm::MaybeAlign(1), s1, llvm::MaybeAlign(1), len1);

    llvm::Value* destOffset = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), dest, len1, "dest_offset");
    llvm::Value* len2WithNull = m_builder->CreateAdd(len2, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "len2_null");
    m_builder->CreateMemCpy(destOffset, llvm::MaybeAlign(1), s2, llvm::MaybeAlign(1), len2WithNull);

    return dest;
}

llvm::Function* LlvmEmitter::getOrCreateAsc() {
    llvm::Function* func = m_module->getFunction("__llbc_str_asc");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_asc", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* nonNullBB = llvm::BasicBlock::Create(*m_context, "nonnull", func);
    llvm::BasicBlock* retZeroBB = llvm::BasicBlock::Create(*m_context, "retzero", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, retZeroBB, nonNullBB);

    m_builder->SetInsertPoint(nonNullBB);
    llvm::Value* ch = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), sArg, "ch");
    llvm::Value* ch32 = m_builder->CreateZExt(ch, llvm::Type::getInt32Ty(*m_context), "ch32");
    m_builder->CreateRet(ch32);

    m_builder->SetInsertPoint(retZeroBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateChr() {
    llvm::Function* func = m_module->getFunction("__llbc_str_chr");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_chr", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    m_builder->SetInsertPoint(entryBB);

    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* buf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 2)}, "chrbuf");

    llvm::Value* code = func->getArg(0);
    llvm::Value* code8 = m_builder->CreateTrunc(code, llvm::Type::getInt8Ty(*m_context), "ch");
    m_builder->CreateStore(code8, buf);

    llvm::Value* termSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), buf, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1));
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), termSlot);

    m_builder->CreateRet(buf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrcmp() {
    llvm::Function* func = m_module->getFunction("__llbc_strcmp");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_strcmp", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* matchBB = llvm::BasicBlock::Create(*m_context, "match", func);
    llvm::BasicBlock* checkNullBB = llvm::BasicBlock::Create(*m_context, "check.null", func);
    llvm::BasicBlock* s1NullBB = llvm::BasicBlock::Create(*m_context, "s1.null", func);
    llvm::BasicBlock* s2NullBB = llvm::BasicBlock::Create(*m_context, "s2.null", func);
    llvm::BasicBlock* s2RetBB = llvm::BasicBlock::Create(*m_context, "s2.ret", func);
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "loop", func);
    llvm::BasicBlock* checkTermBB = llvm::BasicBlock::Create(*m_context, "check.term", func);
    llvm::BasicBlock* incBB = llvm::BasicBlock::Create(*m_context, "loop.inc", func);
    llvm::BasicBlock* diffBB = llvm::BasicBlock::Create(*m_context, "diff", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* s1 = func->getArg(0);
    llvm::Argument* s2 = func->getArg(1);

    llvm::Value* ptrEq = m_builder->CreateICmpEQ(s1, s2, "ptreq");
    m_builder->CreateCondBr(ptrEq, matchBB, checkNullBB);

    m_builder->SetInsertPoint(matchBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));

    m_builder->SetInsertPoint(checkNullBB);
    llvm::Value* s1Null = m_builder->CreateIsNull(s1, "s1null");
    m_builder->CreateCondBr(s1Null, s1NullBB, s2NullBB);

    m_builder->SetInsertPoint(s1NullBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), -1));

    m_builder->SetInsertPoint(s2NullBB);
    llvm::Value* s2Null = m_builder->CreateIsNull(s2, "s2null");
    m_builder->CreateCondBr(s2Null, s2RetBB, loopBB);

    m_builder->SetInsertPoint(s2RetBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1));

    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* idxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "idx");
    idxPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), s2NullBB);

    llvm::Value* p1 = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), s1, idxPhi, "p1");
    llvm::Value* c1 = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), p1, "c1");
    llvm::Value* p2 = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), s2, idxPhi, "p2");
    llvm::Value* c2 = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), p2, "c2");

    llvm::Value* chEq = m_builder->CreateICmpEQ(c1, c2, "cheq");
    m_builder->CreateCondBr(chEq, checkTermBB, diffBB);

    m_builder->SetInsertPoint(checkTermBB);
    llvm::Value* isTerm = m_builder->CreateICmpEQ(c1, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "isterm");
    m_builder->CreateCondBr(isTerm, matchBB, incBB);

    m_builder->SetInsertPoint(incBB);
    llvm::Value* nextIdx = m_builder->CreateAdd(idxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextidx");
    idxPhi->addIncoming(nextIdx, incBB);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(diffBB);
    llvm::Value* c1_32 = m_builder->CreateZExt(c1, llvm::Type::getInt32Ty(*m_context), "c1_32");
    llvm::Value* c2_32 = m_builder->CreateZExt(c2, llvm::Type::getInt32Ty(*m_context), "c2_32");
    llvm::Value* diff = m_builder->CreateSub(c1_32, c2_32, "diff");
    m_builder->CreateRet(diff);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreatePrintStr() {
    llvm::Function* func = m_module->getFunction("__llbc_print_str");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getVoidTy(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_print_str", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* nonNullBB = llvm::BasicBlock::Create(*m_context, "nonnull", func);
    llvm::BasicBlock* exitBB = llvm::BasicBlock::Create(*m_context, "exit", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, exitBB, nonNullBB);

    m_builder->SetInsertPoint(nonNullBB);
    llvm::Function* fputsFn = m_module->getFunction("fputs");
    if (!fputsFn) {
        llvm::FunctionType* fputsTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        fputsFn = llvm::Function::Create(fputsTy, llvm::Function::ExternalLinkage, "fputs", m_module.get());
    }
    // Auto-declare stdout external pointer
    llvm::GlobalVariable* stdoutVar = m_module->getGlobalVariable("stdout");
    if (!stdoutVar) {
        stdoutVar = new llvm::GlobalVariable(
            *m_module,
            llvm::PointerType::get(*m_context, 0),
            false,
            llvm::GlobalValue::ExternalLinkage,
            nullptr,
            "stdout"
        );
    }
    llvm::Value* stdoutVal = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), stdoutVar, "stdout.val");
    m_builder->CreateCall(fputsFn, {sArg, stdoutVal});
    m_builder->CreateBr(exitBB);

    m_builder->SetInsertPoint(exitBB);
    m_builder->CreateRetVoid();

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

// Fixed-capacity open-addressing Hash Table runtime for Map / Dictionary
// Layout per entry (16 bytes): [Key: ptr (8 bytes), Value: i64 (8 bytes)]
// Table size: 64 entries (1024 bytes)
const uint64_t MAP_CAPACITY = 64;

llvm::Function* LlvmEmitter::getOrCreateMapCreate() {
    llvm::Function* func = m_module->getFunction("__llbc_map_create");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_map_create", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    m_builder->SetInsertPoint(entryBB);

    llvm::Function* mallocFn = getOrCreateMalloc();
    // Allocate 64 entries * 16 bytes = 1024 bytes
    llvm::Value* mapBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), MAP_CAPACITY * 16)}, "mapbuf");

    // Zero-initialize entries: loop 0 to 64*2-1 i64 words
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "zero.loop", func);
    llvm::BasicBlock* loopBodyBB = llvm::BasicBlock::Create(*m_context, "zero.body", func);
    llvm::BasicBlock* doneBB = llvm::BasicBlock::Create(*m_context, "zero.done", func);

    m_builder->CreateBr(loopBB);
    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* zIdx = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "zidx");
    zIdx->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* zCmp = m_builder->CreateICmpSLT(zIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), MAP_CAPACITY * 2), "zcmp");
    m_builder->CreateCondBr(zCmp, loopBodyBB, doneBB);

    m_builder->SetInsertPoint(loopBodyBB);
    llvm::Value* wordPtr = m_builder->CreateGEP(llvm::Type::getInt64Ty(*m_context), mapBuf, zIdx, "wordptr");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), wordPtr);
    llvm::Value* nextZ = m_builder->CreateAdd(zIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextz");
    zIdx->addIncoming(nextZ, loopBodyBB);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(doneBB);
    m_builder->CreateRet(mapBuf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateMapSet() {
    llvm::Function* func = m_module->getFunction("__llbc_map_set");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getVoidTy(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_map_set", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "probe.loop", func);
    llvm::BasicBlock* checkSlotBB = llvm::BasicBlock::Create(*m_context, "check.slot", func);
    llvm::BasicBlock* compareKeyBB = llvm::BasicBlock::Create(*m_context, "compare.key", func);
    llvm::BasicBlock* writeSlotBB = llvm::BasicBlock::Create(*m_context, "write.slot", func);
    llvm::BasicBlock* nextProbeBB = llvm::BasicBlock::Create(*m_context, "next.probe", func);
    llvm::BasicBlock* exitBB = llvm::BasicBlock::Create(*m_context, "exit", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* mapArg = func->getArg(0);
    llvm::Argument* keyArg = func->getArg(1);
    llvm::Argument* valArg = func->getArg(2);

    llvm::Value* isMapNull = m_builder->CreateIsNull(mapArg, "ismapnull");
    llvm::Value* isKeyNull = m_builder->CreateIsNull(keyArg, "iskeynull");
    llvm::Value* invalid = m_builder->CreateOr(isMapNull, isKeyNull, "invalid");
    m_builder->CreateCondBr(invalid, exitBB, loopBB);

    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* probeIdx = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "probe");
    probeIdx->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* probeCmp = m_builder->CreateICmpSLT(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), MAP_CAPACITY), "probecmp");
    m_builder->CreateCondBr(probeCmp, checkSlotBB, exitBB);

    m_builder->SetInsertPoint(checkSlotBB);
    // Each entry is 16 bytes: key at byte offset probe*16, val at probe*16 + 8
    llvm::Value* byteOffset = m_builder->CreateMul(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 16), "boff");
    llvm::Value* keySlotPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), mapArg, byteOffset, "keyslotptr");
    llvm::Value* slotKey = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), keySlotPtr, "slotkey");

    llvm::Value* isSlotEmpty = m_builder->CreateIsNull(slotKey, "slotempty");
    m_builder->CreateCondBr(isSlotEmpty, writeSlotBB, compareKeyBB);

    m_builder->SetInsertPoint(compareKeyBB);
    llvm::Function* strcmpFn = getOrCreateStrcmp();
    llvm::Value* cmpRes = m_builder->CreateCall(strcmpFn, {slotKey, keyArg}, "strcmp");
    llvm::Value* isMatch = m_builder->CreateICmpEQ(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "ismatch");
    m_builder->CreateCondBr(isMatch, writeSlotBB, nextProbeBB);

    m_builder->SetInsertPoint(writeSlotBB);
    m_builder->CreateStore(keyArg, keySlotPtr);
    llvm::Value* valSlotOffset = m_builder->CreateAdd(byteOffset, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 8), "voff");
    llvm::Value* valSlotPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), mapArg, valSlotOffset, "valslotptr");
    m_builder->CreateStore(valArg, valSlotPtr);
    m_builder->CreateBr(exitBB);

    m_builder->SetInsertPoint(nextProbeBB);
    llvm::Value* nextP = m_builder->CreateAdd(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextp");
    probeIdx->addIncoming(nextP, nextProbeBB);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(exitBB);
    m_builder->CreateRetVoid();

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateMapGet() {
    llvm::Function* func = m_module->getFunction("__llbc_map_get");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt64Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_map_get", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "probe.loop", func);
    llvm::BasicBlock* checkSlotBB = llvm::BasicBlock::Create(*m_context, "check.slot", func);
    llvm::BasicBlock* compareKeyBB = llvm::BasicBlock::Create(*m_context, "compare.key", func);
    llvm::BasicBlock* readValBB = llvm::BasicBlock::Create(*m_context, "read.val", func);
    llvm::BasicBlock* nextProbeBB = llvm::BasicBlock::Create(*m_context, "next.probe", func);
    llvm::BasicBlock* notFoundBB = llvm::BasicBlock::Create(*m_context, "not.found", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* mapArg = func->getArg(0);
    llvm::Argument* keyArg = func->getArg(1);

    llvm::Value* isMapNull = m_builder->CreateIsNull(mapArg, "ismapnull");
    llvm::Value* isKeyNull = m_builder->CreateIsNull(keyArg, "iskeynull");
    llvm::Value* invalid = m_builder->CreateOr(isMapNull, isKeyNull, "invalid");
    m_builder->CreateCondBr(invalid, notFoundBB, loopBB);

    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* probeIdx = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "probe");
    probeIdx->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* probeCmp = m_builder->CreateICmpSLT(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), MAP_CAPACITY), "probecmp");
    m_builder->CreateCondBr(probeCmp, checkSlotBB, notFoundBB);

    m_builder->SetInsertPoint(checkSlotBB);
    llvm::Value* byteOffset = m_builder->CreateMul(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 16), "boff");
    llvm::Value* keySlotPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), mapArg, byteOffset, "keyslotptr");
    llvm::Value* slotKey = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), keySlotPtr, "slotkey");

    llvm::Value* isSlotEmpty = m_builder->CreateIsNull(slotKey, "slotempty");
    m_builder->CreateCondBr(isSlotEmpty, notFoundBB, compareKeyBB);

    m_builder->SetInsertPoint(compareKeyBB);
    llvm::Function* strcmpFn = getOrCreateStrcmp();
    llvm::Value* cmpRes = m_builder->CreateCall(strcmpFn, {slotKey, keyArg}, "strcmp");
    llvm::Value* isMatch = m_builder->CreateICmpEQ(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "ismatch");
    m_builder->CreateCondBr(isMatch, readValBB, nextProbeBB);

    m_builder->SetInsertPoint(readValBB);
    llvm::Value* valSlotOffset = m_builder->CreateAdd(byteOffset, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 8), "voff");
    llvm::Value* valSlotPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), mapArg, valSlotOffset, "valslotptr");
    llvm::Value* resVal = m_builder->CreateLoad(llvm::Type::getInt64Ty(*m_context), valSlotPtr, "val");
    m_builder->CreateRet(resVal);

    m_builder->SetInsertPoint(nextProbeBB);
    llvm::Value* nextP = m_builder->CreateAdd(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextp");
    probeIdx->addIncoming(nextP, nextProbeBB);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(notFoundBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateMapHas() {
    llvm::Function* func = m_module->getFunction("__llbc_map_has");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt1Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_map_has", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "probe.loop", func);
    llvm::BasicBlock* checkSlotBB = llvm::BasicBlock::Create(*m_context, "check.slot", func);
    llvm::BasicBlock* compareKeyBB = llvm::BasicBlock::Create(*m_context, "compare.key", func);
    llvm::BasicBlock* nextProbeBB = llvm::BasicBlock::Create(*m_context, "next.probe", func);
    llvm::BasicBlock* foundBB = llvm::BasicBlock::Create(*m_context, "found", func);
    llvm::BasicBlock* notFoundBB = llvm::BasicBlock::Create(*m_context, "not.found", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* mapArg = func->getArg(0);
    llvm::Argument* keyArg = func->getArg(1);

    llvm::Value* isMapNull = m_builder->CreateIsNull(mapArg, "ismapnull");
    llvm::Value* isKeyNull = m_builder->CreateIsNull(keyArg, "iskeynull");
    llvm::Value* invalid = m_builder->CreateOr(isMapNull, isKeyNull, "invalid");
    m_builder->CreateCondBr(invalid, notFoundBB, loopBB);

    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* probeIdx = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "probe");
    probeIdx->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* probeCmp = m_builder->CreateICmpSLT(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), MAP_CAPACITY), "probecmp");
    m_builder->CreateCondBr(probeCmp, checkSlotBB, notFoundBB);

    m_builder->SetInsertPoint(checkSlotBB);
    llvm::Value* byteOffset = m_builder->CreateMul(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 16), "boff");
    llvm::Value* keySlotPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), mapArg, byteOffset, "keyslotptr");
    llvm::Value* slotKey = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), keySlotPtr, "slotkey");

    llvm::Value* isSlotEmpty = m_builder->CreateIsNull(slotKey, "slotempty");
    m_builder->CreateCondBr(isSlotEmpty, notFoundBB, compareKeyBB);

    m_builder->SetInsertPoint(compareKeyBB);
    llvm::Function* strcmpFn = getOrCreateStrcmp();
    llvm::Value* cmpRes = m_builder->CreateCall(strcmpFn, {slotKey, keyArg}, "strcmp");
    llvm::Value* isMatch = m_builder->CreateICmpEQ(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "ismatch");
    m_builder->CreateCondBr(isMatch, foundBB, nextProbeBB);

    m_builder->SetInsertPoint(foundBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1));

    m_builder->SetInsertPoint(nextProbeBB);
    llvm::Value* nextP = m_builder->CreateAdd(probeIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextp");
    probeIdx->addIncoming(nextP, nextProbeBB);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(notFoundBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrMid() {
    llvm::Function* func = m_module->getFunction("__llbc_str_mid");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context), llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_mid", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* validSBB = llvm::BasicBlock::Create(*m_context, "valid.s", func);
    llvm::BasicBlock* calcAvailBB = llvm::BasicBlock::Create(*m_context, "calc.avail", func);
    llvm::BasicBlock* allocBB = llvm::BasicBlock::Create(*m_context, "alloc.dest", func);
    llvm::BasicBlock* emptyBB = llvm::BasicBlock::Create(*m_context, "empty.str", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Argument* startArg = func->getArg(1);
    llvm::Argument* lenArg = func->getArg(2);

    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, emptyBB, validSBB);

    m_builder->SetInsertPoint(emptyBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* emptyBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)}, "emptybuf");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyBuf);
    m_builder->CreateRet(emptyBuf);

    m_builder->SetInsertPoint(validSBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* totalLen = m_builder->CreateCall(strlenFn, {sArg}, "totallen");

    llvm::Value* startLt1 = m_builder->CreateICmpSLT(startArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "startlt1");
    llvm::Value* adjStart = m_builder->CreateSelect(startLt1, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), startArg, "adjstart");

    llvm::Value* startGtLen = m_builder->CreateICmpSGT(adjStart, totalLen, "startgtlen");
    m_builder->CreateCondBr(startGtLen, emptyBB, calcAvailBB);

    m_builder->SetInsertPoint(calcAvailBB);
    llvm::Value* startZeroBased = m_builder->CreateSub(adjStart, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "start0");
    llvm::Value* avail = m_builder->CreateSub(totalLen, startZeroBased, "avail");

    llvm::Value* lenLt0 = m_builder->CreateICmpSLT(lenArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "lenlt0");
    llvm::Value* lenGtAvail = m_builder->CreateICmpSGT(lenArg, avail, "lengtavail");
    llvm::Value* useAvail = m_builder->CreateOr(lenLt0, lenGtAvail, "useavail");
    llvm::Value* count = m_builder->CreateSelect(useAvail, avail, lenArg, "count");

    llvm::Value* countLe0 = m_builder->CreateICmpSLE(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "countle0");
    m_builder->CreateCondBr(countLe0, emptyBB, allocBB);

    m_builder->SetInsertPoint(allocBB);
    llvm::Value* allocSize = m_builder->CreateAdd(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "allocsize");
    llvm::Value* destBuf = m_builder->CreateCall(mallocFn, {allocSize}, "midbuf");

    llvm::Value* srcOffset = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, startZeroBased, "srcoffset");
    m_builder->CreateMemCpy(destBuf, llvm::MaybeAlign(1), srcOffset, llvm::MaybeAlign(1), count);

    llvm::Value* destTerm = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), destBuf, count, "destterm");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), destTerm);
    m_builder->CreateRet(destBuf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrRight() {
    llvm::Function* func = m_module->getFunction("__llbc_str_right");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_right", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* nonNullBB = llvm::BasicBlock::Create(*m_context, "nonnull", func);
    llvm::BasicBlock* emptyBB = llvm::BasicBlock::Create(*m_context, "empty", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Argument* nArg = func->getArg(1);

    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, emptyBB, nonNullBB);

    m_builder->SetInsertPoint(emptyBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* emptyBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)}, "emptybuf");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyBuf);
    m_builder->CreateRet(emptyBuf);

    m_builder->SetInsertPoint(nonNullBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* totalLen = m_builder->CreateCall(strlenFn, {sArg}, "totallen");

    llvm::Value* nLt0 = m_builder->CreateICmpSLE(nArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "nlt0");
    llvm::Value* nGtLen = m_builder->CreateICmpSGT(nArg, totalLen, "ngtlen");
    llvm::Value* clampN = m_builder->CreateSelect(nGtLen, totalLen, nArg, "clampn");
    llvm::Value* finalN = m_builder->CreateSelect(nLt0, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), clampN, "finaln");

    llvm::Value* diff = m_builder->CreateSub(totalLen, finalN, "diff");
    llvm::Value* start1 = m_builder->CreateAdd(diff, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "start1");

    llvm::Function* midFn = getOrCreateStrMid();
    llvm::Value* res = m_builder->CreateCall(midFn, {sArg, start1, finalN}, "rightres");
    m_builder->CreateRet(res);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrTrim() {
    llvm::Function* func = m_module->getFunction("__llbc_str_trim");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_trim", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* validSBB = llvm::BasicBlock::Create(*m_context, "valid.s", func);
    llvm::BasicBlock* startLoopBB = llvm::BasicBlock::Create(*m_context, "start.loop", func);
    llvm::BasicBlock* startBodyBB = llvm::BasicBlock::Create(*m_context, "start.body", func);
    llvm::BasicBlock* endSetupBB = llvm::BasicBlock::Create(*m_context, "end.setup", func);
    llvm::BasicBlock* endLoopBB = llvm::BasicBlock::Create(*m_context, "end.loop", func);
    llvm::BasicBlock* endBodyBB = llvm::BasicBlock::Create(*m_context, "end.body", func);
    llvm::BasicBlock* checkEmptyBB = llvm::BasicBlock::Create(*m_context, "check.empty", func);
    llvm::BasicBlock* copyBB = llvm::BasicBlock::Create(*m_context, "copy", func);
    llvm::BasicBlock* emptyBB = llvm::BasicBlock::Create(*m_context, "empty", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, emptyBB, validSBB);

    m_builder->SetInsertPoint(emptyBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* emptyBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)}, "emptybuf");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyBuf);
    m_builder->CreateRet(emptyBuf);

    m_builder->SetInsertPoint(validSBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* totalLen = m_builder->CreateCall(strlenFn, {sArg}, "totallen");
    m_builder->CreateBr(startLoopBB);

    m_builder->SetInsertPoint(startLoopBB);
    llvm::PHINode* startPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "startidx");
    startPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), validSBB);

    llvm::Value* inBounds = m_builder->CreateICmpSLT(startPhi, totalLen, "inbounds");
    llvm::BasicBlock* checkSpaceBB = llvm::BasicBlock::Create(*m_context, "check.space", func, startBodyBB);
    m_builder->CreateCondBr(inBounds, checkSpaceBB, endSetupBB);

    m_builder->SetInsertPoint(checkSpaceBB);
    llvm::Value* chPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, startPhi, "chptr");
    llvm::Value* chVal = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), chPtr, "chval");
    llvm::Value* isSpace = m_builder->CreateICmpULE(chVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 32), "isspace");
    m_builder->CreateCondBr(isSpace, startBodyBB, endSetupBB);

    m_builder->SetInsertPoint(startBodyBB);
    llvm::Value* nextStart = m_builder->CreateAdd(startPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextstart");
    startPhi->addIncoming(nextStart, startBodyBB);
    m_builder->CreateBr(startLoopBB);

    m_builder->SetInsertPoint(endSetupBB);
    llvm::Value* initEnd = m_builder->CreateSub(totalLen, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "initend");
    m_builder->CreateBr(endLoopBB);

    m_builder->SetInsertPoint(endLoopBB);
    llvm::PHINode* endPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "endidx");
    endPhi->addIncoming(initEnd, endSetupBB);

    llvm::Value* endGeStart = m_builder->CreateICmpSGE(endPhi, startPhi, "endgestart");
    llvm::BasicBlock* checkEndSpaceBB = llvm::BasicBlock::Create(*m_context, "check.endspace", func, endBodyBB);
    m_builder->CreateCondBr(endGeStart, checkEndSpaceBB, checkEmptyBB);

    m_builder->SetInsertPoint(checkEndSpaceBB);
    llvm::Value* endChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, endPhi, "endchptr");
    llvm::Value* endChVal = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), endChPtr, "endchval");
    llvm::Value* isEndSpace = m_builder->CreateICmpULE(endChVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 32), "isendspace");
    m_builder->CreateCondBr(isEndSpace, endBodyBB, checkEmptyBB);

    m_builder->SetInsertPoint(endBodyBB);
    llvm::Value* nextEnd = m_builder->CreateSub(endPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextend");
    endPhi->addIncoming(nextEnd, endBodyBB);
    m_builder->CreateBr(endLoopBB);

    m_builder->SetInsertPoint(checkEmptyBB);
    llvm::Value* countMinus1 = m_builder->CreateSub(endPhi, startPhi, "countm1");
    llvm::Value* count = m_builder->CreateAdd(countMinus1, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "trimcount");
    llvm::Value* countLe0 = m_builder->CreateICmpSLE(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "countle0");
    m_builder->CreateCondBr(countLe0, emptyBB, copyBB);

    m_builder->SetInsertPoint(copyBB);
    llvm::Value* allocSize = m_builder->CreateAdd(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "allocsize");
    llvm::Value* destBuf = m_builder->CreateCall(mallocFn, {allocSize}, "trimbuf");
    llvm::Value* srcStart = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, startPhi, "srcstart");
    m_builder->CreateMemCpy(destBuf, llvm::MaybeAlign(1), srcStart, llvm::MaybeAlign(1), count);
    llvm::Value* termSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), destBuf, count, "term");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), termSlot);
    m_builder->CreateRet(destBuf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrLTrim() {
    llvm::Function* func = m_module->getFunction("__llbc_str_ltrim");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_ltrim", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* validSBB = llvm::BasicBlock::Create(*m_context, "valid.s", func);
    llvm::BasicBlock* startLoopBB = llvm::BasicBlock::Create(*m_context, "start.loop", func);
    llvm::BasicBlock* startBodyBB = llvm::BasicBlock::Create(*m_context, "start.body", func);
    llvm::BasicBlock* checkEmptyBB = llvm::BasicBlock::Create(*m_context, "check.empty", func);
    llvm::BasicBlock* copyBB = llvm::BasicBlock::Create(*m_context, "copy", func);
    llvm::BasicBlock* emptyBB = llvm::BasicBlock::Create(*m_context, "empty", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, emptyBB, validSBB);

    m_builder->SetInsertPoint(emptyBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* emptyBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)}, "emptybuf");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyBuf);
    m_builder->CreateRet(emptyBuf);

    m_builder->SetInsertPoint(validSBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* totalLen = m_builder->CreateCall(strlenFn, {sArg}, "totallen");
    m_builder->CreateBr(startLoopBB);

    m_builder->SetInsertPoint(startLoopBB);
    llvm::PHINode* startPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "startidx");
    startPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), validSBB);

    llvm::Value* inBounds = m_builder->CreateICmpSLT(startPhi, totalLen, "inbounds");
    llvm::BasicBlock* checkSpaceBB = llvm::BasicBlock::Create(*m_context, "check.space", func, startBodyBB);
    m_builder->CreateCondBr(inBounds, checkSpaceBB, checkEmptyBB);

    m_builder->SetInsertPoint(checkSpaceBB);
    llvm::Value* chPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, startPhi, "chptr");
    llvm::Value* chVal = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), chPtr, "chval");
    llvm::Value* isSpace = m_builder->CreateICmpULE(chVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 32), "isspace");
    m_builder->CreateCondBr(isSpace, startBodyBB, checkEmptyBB);

    m_builder->SetInsertPoint(startBodyBB);
    llvm::Value* nextStart = m_builder->CreateAdd(startPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextstart");
    startPhi->addIncoming(nextStart, startBodyBB);
    m_builder->CreateBr(startLoopBB);

    m_builder->SetInsertPoint(checkEmptyBB);
    llvm::Value* count = m_builder->CreateSub(totalLen, startPhi, "ltrimcount");
    llvm::Value* countLe0 = m_builder->CreateICmpSLE(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "countle0");
    m_builder->CreateCondBr(countLe0, emptyBB, copyBB);

    m_builder->SetInsertPoint(copyBB);
    llvm::Value* allocSize = m_builder->CreateAdd(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "allocsize");
    llvm::Value* destBuf = m_builder->CreateCall(mallocFn, {allocSize}, "ltrimbuf");
    llvm::Value* srcStart = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, startPhi, "srcstart");
    m_builder->CreateMemCpy(destBuf, llvm::MaybeAlign(1), srcStart, llvm::MaybeAlign(1), count);
    llvm::Value* termSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), destBuf, count, "term");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), termSlot);
    m_builder->CreateRet(destBuf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrRTrim() {
    llvm::Function* func = m_module->getFunction("__llbc_str_rtrim");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_rtrim", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* validSBB = llvm::BasicBlock::Create(*m_context, "valid.s", func);
    llvm::BasicBlock* endLoopBB = llvm::BasicBlock::Create(*m_context, "end.loop", func);
    llvm::BasicBlock* endBodyBB = llvm::BasicBlock::Create(*m_context, "end.body", func);
    llvm::BasicBlock* checkEmptyBB = llvm::BasicBlock::Create(*m_context, "check.empty", func);
    llvm::BasicBlock* copyBB = llvm::BasicBlock::Create(*m_context, "copy", func);
    llvm::BasicBlock* emptyBB = llvm::BasicBlock::Create(*m_context, "empty", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, emptyBB, validSBB);

    m_builder->SetInsertPoint(emptyBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* emptyBuf = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)}, "emptybuf");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyBuf);
    m_builder->CreateRet(emptyBuf);

    m_builder->SetInsertPoint(validSBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* totalLen = m_builder->CreateCall(strlenFn, {sArg}, "totallen");
    llvm::Value* initEnd = m_builder->CreateSub(totalLen, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "initend");
    m_builder->CreateBr(endLoopBB);

    m_builder->SetInsertPoint(endLoopBB);
    llvm::PHINode* endPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "endidx");
    endPhi->addIncoming(initEnd, validSBB);

    llvm::Value* endGeZero = m_builder->CreateICmpSGE(endPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "endgezero");
    llvm::BasicBlock* checkEndSpaceBB = llvm::BasicBlock::Create(*m_context, "check.endspace", func, endBodyBB);
    m_builder->CreateCondBr(endGeZero, checkEndSpaceBB, checkEmptyBB);

    m_builder->SetInsertPoint(checkEndSpaceBB);
    llvm::Value* endChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, endPhi, "endchptr");
    llvm::Value* endChVal = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), endChPtr, "endchval");
    llvm::Value* isEndSpace = m_builder->CreateICmpULE(endChVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 32), "isendspace");
    m_builder->CreateCondBr(isEndSpace, endBodyBB, checkEmptyBB);

    m_builder->SetInsertPoint(endBodyBB);
    llvm::Value* nextEnd = m_builder->CreateSub(endPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextend");
    endPhi->addIncoming(nextEnd, endBodyBB);
    m_builder->CreateBr(endLoopBB);

    m_builder->SetInsertPoint(checkEmptyBB);
    llvm::Value* count = m_builder->CreateAdd(endPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "rtrimcount");
    llvm::Value* countLe0 = m_builder->CreateICmpSLE(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "countle0");
    m_builder->CreateCondBr(countLe0, emptyBB, copyBB);

    m_builder->SetInsertPoint(copyBB);
    llvm::Value* allocSize = m_builder->CreateAdd(count, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "allocsize");
    llvm::Value* destBuf = m_builder->CreateCall(mallocFn, {allocSize}, "rtrimbuf");
    m_builder->CreateMemCpy(destBuf, llvm::MaybeAlign(1), sArg, llvm::MaybeAlign(1), count);
    llvm::Value* termSlot = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), destBuf, count, "term");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), termSlot);
    m_builder->CreateRet(destBuf);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrInStr() {
    llvm::Function* func = m_module->getFunction("__llbc_str_instr");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_instr", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* checkNullBB = llvm::BasicBlock::Create(*m_context, "check.null", func);
    llvm::BasicBlock* initBB = llvm::BasicBlock::Create(*m_context, "init", func);
    llvm::BasicBlock* outerLoopBB = llvm::BasicBlock::Create(*m_context, "outer.loop", func);
    llvm::BasicBlock* innerSetupBB = llvm::BasicBlock::Create(*m_context, "inner.setup", func);
    llvm::BasicBlock* innerLoopBB = llvm::BasicBlock::Create(*m_context, "inner.loop", func);
    llvm::BasicBlock* innerBodyBB = llvm::BasicBlock::Create(*m_context, "inner.body", func);
    llvm::BasicBlock* outerNextBB = llvm::BasicBlock::Create(*m_context, "outer.next", func);
    llvm::BasicBlock* foundBB = llvm::BasicBlock::Create(*m_context, "found", func);
    llvm::BasicBlock* notFoundBB = llvm::BasicBlock::Create(*m_context, "notfound", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Argument* subArg = func->getArg(1);
    llvm::Argument* startArg = func->getArg(2);

    llvm::Value* isSNull = m_builder->CreateIsNull(sArg, "issnull");
    llvm::Value* isSubNull = m_builder->CreateIsNull(subArg, "issubnull");
    llvm::Value* eitherNull = m_builder->CreateOr(isSNull, isSubNull, "eithernull");
    m_builder->CreateCondBr(eitherNull, notFoundBB, checkNullBB);

    m_builder->SetInsertPoint(notFoundBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));

    m_builder->SetInsertPoint(checkNullBB);
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* sLen = m_builder->CreateCall(strlenFn, {sArg}, "slen");
    llvm::Value* subLen = m_builder->CreateCall(strlenFn, {subArg}, "sublen");

    llvm::Value* subEmpty = m_builder->CreateICmpEQ(subLen, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), "subempty");
    llvm::BasicBlock* subEmptyBB = llvm::BasicBlock::Create(*m_context, "sub.empty", func, initBB);
    m_builder->CreateCondBr(subEmpty, subEmptyBB, initBB);

    m_builder->SetInsertPoint(subEmptyBB);
    llvm::Value* startLt1 = m_builder->CreateICmpSLT(startArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "startlt1");
    llvm::Value* clampStart = m_builder->CreateSelect(startLt1, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), startArg, "clampstart");
    llvm::Value* clampStart32 = m_builder->CreateTrunc(clampStart, llvm::Type::getInt32Ty(*m_context), "clampstart32");
    m_builder->CreateRet(clampStart32);

    m_builder->SetInsertPoint(initBB);
    llvm::Value* initStartLt1 = m_builder->CreateICmpSLT(startArg, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "initstartlt1");
    llvm::Value* effectiveStart = m_builder->CreateSelect(initStartLt1, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), startArg, "effstart");
    llvm::Value* startIdx0 = m_builder->CreateSub(effectiveStart, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "startidx0");

    llvm::Value* maxI = m_builder->CreateSub(sLen, subLen, "maxi");
    llvm::Value* startGtMax = m_builder->CreateICmpSGT(startIdx0, maxI, "startgtmax");
    m_builder->CreateCondBr(startGtMax, notFoundBB, outerLoopBB);

    m_builder->SetInsertPoint(outerLoopBB);
    llvm::PHINode* iPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "i");
    iPhi->addIncoming(startIdx0, initBB);

    llvm::Value* iLeMax = m_builder->CreateICmpSLE(iPhi, maxI, "ilemax");
    m_builder->CreateCondBr(iLeMax, innerSetupBB, notFoundBB);

    m_builder->SetInsertPoint(innerSetupBB);
    m_builder->CreateBr(innerLoopBB);

    m_builder->SetInsertPoint(innerLoopBB);
    llvm::PHINode* jPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "j");
    jPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), innerSetupBB);

    llvm::Value* jLtSubLen = m_builder->CreateICmpSLT(jPhi, subLen, "jltsub");
    m_builder->CreateCondBr(jLtSubLen, innerBodyBB, foundBB);

    m_builder->SetInsertPoint(innerBodyBB);
    llvm::Value* sOffset = m_builder->CreateAdd(iPhi, jPhi, "soffset");
    llvm::Value* sPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, sOffset, "sptr");
    llvm::Value* sChar = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), sPtr, "schar");

    llvm::Value* subPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), subArg, jPhi, "subptr");
    llvm::Value* subChar = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), subPtr, "subchar");

    llvm::Value* charsMatch = m_builder->CreateICmpEQ(sChar, subChar, "charsmatch");
    llvm::BasicBlock* innerIncBB = llvm::BasicBlock::Create(*m_context, "inner.inc", func, outerNextBB);
    m_builder->CreateCondBr(charsMatch, innerIncBB, outerNextBB);

    m_builder->SetInsertPoint(innerIncBB);
    llvm::Value* nextJ = m_builder->CreateAdd(jPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextj");
    jPhi->addIncoming(nextJ, innerIncBB);
    m_builder->CreateBr(innerLoopBB);

    m_builder->SetInsertPoint(outerNextBB);
    llvm::Value* nextI = m_builder->CreateAdd(iPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nexti");
    iPhi->addIncoming(nextI, outerNextBB);
    m_builder->CreateBr(outerLoopBB);

    m_builder->SetInsertPoint(foundBB);
    llvm::Value* foundIdx1 = m_builder->CreateAdd(iPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "foundidx1");
    llvm::Value* foundIdx32 = m_builder->CreateTrunc(foundIdx1, llvm::Type::getInt32Ty(*m_context), "foundidx32");
    m_builder->CreateRet(foundIdx32);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateStrVal() {
    llvm::Function* func = m_module->getFunction("__llbc_str_val");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getDoubleTy(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_str_val", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* skipWsBB = llvm::BasicBlock::Create(*m_context, "skip.ws", func);
    llvm::BasicBlock* skipWsBodyBB = llvm::BasicBlock::Create(*m_context, "skip.ws.body", func);
    llvm::BasicBlock* checkSignBB = llvm::BasicBlock::Create(*m_context, "check.sign", func);
    llvm::BasicBlock* intLoopBB = llvm::BasicBlock::Create(*m_context, "int.loop", func);
    llvm::BasicBlock* intBodyBB = llvm::BasicBlock::Create(*m_context, "int.body", func);
    llvm::BasicBlock* checkDotBB = llvm::BasicBlock::Create(*m_context, "check.dot", func);
    llvm::BasicBlock* fracLoopBB = llvm::BasicBlock::Create(*m_context, "frac.loop", func);
    llvm::BasicBlock* fracBodyBB = llvm::BasicBlock::Create(*m_context, "frac.body", func);
    llvm::BasicBlock* finishBB = llvm::BasicBlock::Create(*m_context, "finish", func);
    llvm::BasicBlock* retZeroBB = llvm::BasicBlock::Create(*m_context, "retzero", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Value* isNull = m_builder->CreateIsNull(sArg, "isnull");
    m_builder->CreateCondBr(isNull, retZeroBB, skipWsBB);

    m_builder->SetInsertPoint(retZeroBB);
    m_builder->CreateRet(llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.0));

    m_builder->SetInsertPoint(skipWsBB);
    llvm::PHINode* wsIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "wsidx");
    wsIdxPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), entryBB);

    llvm::Value* wsChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, wsIdxPhi, "wschptr");
    llvm::Value* wsCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), wsChPtr, "wsch");
    llvm::Value* isTerm = m_builder->CreateICmpEQ(wsCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "isterm");
    llvm::Value* isWs = m_builder->CreateICmpULE(wsCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 32), "isws");
    llvm::Value* continueWs = m_builder->CreateAnd(isWs, m_builder->CreateNot(isTerm), "contws");
    m_builder->CreateCondBr(continueWs, skipWsBodyBB, checkSignBB);

    m_builder->SetInsertPoint(skipWsBodyBB);
    llvm::Value* nextWsIdx = m_builder->CreateAdd(wsIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextwsidx");
    wsIdxPhi->addIncoming(nextWsIdx, skipWsBodyBB);
    m_builder->CreateBr(skipWsBB);

    m_builder->SetInsertPoint(checkSignBB);
    llvm::Value* signChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, wsIdxPhi, "signchptr");
    llvm::Value* signCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), signChPtr, "signch");
    llvm::Value* isMinus = m_builder->CreateICmpEQ(signCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '-'), "isminus");
    llvm::Value* isPlus = m_builder->CreateICmpEQ(signCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '+'), "isplus");
    llvm::Value* hasSign = m_builder->CreateOr(isMinus, isPlus, "hassign");
    llvm::Value* signInc = m_builder->CreateZExt(hasSign, llvm::Type::getInt64Ty(*m_context), "signinc");
    llvm::Value* startDigitsIdx = m_builder->CreateAdd(wsIdxPhi, signInc, "startdigitsidx");
    m_builder->CreateBr(intLoopBB);

    m_builder->SetInsertPoint(intLoopBB);
    llvm::PHINode* intIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "intidx");
    intIdxPhi->addIncoming(startDigitsIdx, checkSignBB);
    llvm::PHINode* intValPhi = m_builder->CreatePHI(llvm::Type::getDoubleTy(*m_context), 2, "intval");
    intValPhi->addIncoming(llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.0), checkSignBB);

    llvm::Value* digitChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, intIdxPhi, "digchptr");
    llvm::Value* digitCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), digitChPtr, "digch");
    llvm::Value* isGe0 = m_builder->CreateICmpUGE(digitCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), "ge0");
    llvm::Value* isLe9 = m_builder->CreateICmpULE(digitCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '9'), "le9");
    llvm::Value* isDigit = m_builder->CreateAnd(isGe0, isLe9, "isdigit");
    m_builder->CreateCondBr(isDigit, intBodyBB, checkDotBB);

    m_builder->SetInsertPoint(intBodyBB);
    llvm::Value* dDigit = m_builder->CreateSub(digitCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), "ddigit");
    llvm::Value* dDigitFp = m_builder->CreateUIToFP(dDigit, llvm::Type::getDoubleTy(*m_context), "ddigitfp");
    llvm::Value* intMul10 = m_builder->CreateFMul(intValPhi, llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 10.0), "mul10");
    llvm::Value* nextIntVal = m_builder->CreateFAdd(intMul10, dDigitFp, "nextintval");
    llvm::Value* nextIntIdx = m_builder->CreateAdd(intIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextintidx");
    intIdxPhi->addIncoming(nextIntIdx, intBodyBB);
    intValPhi->addIncoming(nextIntVal, intBodyBB);
    m_builder->CreateBr(intLoopBB);

    m_builder->SetInsertPoint(checkDotBB);
    llvm::Value* isDot = m_builder->CreateICmpEQ(digitCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '.'), "isdot");
    llvm::BasicBlock* dotSetupBB = llvm::BasicBlock::Create(*m_context, "dot.setup", func, finishBB);
    m_builder->CreateCondBr(isDot, dotSetupBB, finishBB);

    m_builder->SetInsertPoint(dotSetupBB);
    llvm::Value* fracStartIdx = m_builder->CreateAdd(intIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "fracstartidx");
    m_builder->CreateBr(fracLoopBB);

    m_builder->SetInsertPoint(fracLoopBB);
    llvm::PHINode* fracIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "fracidx");
    fracIdxPhi->addIncoming(fracStartIdx, dotSetupBB);
    llvm::PHINode* fracValPhi = m_builder->CreatePHI(llvm::Type::getDoubleTy(*m_context), 2, "fracval");
    fracValPhi->addIncoming(intValPhi, dotSetupBB);
    llvm::PHINode* factorPhi = m_builder->CreatePHI(llvm::Type::getDoubleTy(*m_context), 2, "factor");
    factorPhi->addIncoming(llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.1), dotSetupBB);

    llvm::Value* fracChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, fracIdxPhi, "fracchptr");
    llvm::Value* fracCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), fracChPtr, "fracch");
    llvm::Value* isFracGe0 = m_builder->CreateICmpUGE(fracCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), "fge0");
    llvm::Value* isFracLe9 = m_builder->CreateICmpULE(fracCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '9'), "fle9");
    llvm::Value* isFracDigit = m_builder->CreateAnd(isFracGe0, isFracLe9, "isfracdigit");
    m_builder->CreateCondBr(isFracDigit, fracBodyBB, finishBB);

    m_builder->SetInsertPoint(fracBodyBB);
    llvm::Value* fracDigit = m_builder->CreateSub(fracCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '0'), "fracdigit");
    llvm::Value* fracDigitFp = m_builder->CreateUIToFP(fracDigit, llvm::Type::getDoubleTy(*m_context), "fracdigitfp");
    llvm::Value* addTerm = m_builder->CreateFMul(fracDigitFp, factorPhi, "addterm");
    llvm::Value* nextFracVal = m_builder->CreateFAdd(fracValPhi, addTerm, "nextfracval");
    llvm::Value* nextFactor = m_builder->CreateFMul(factorPhi, llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.1), "nextfactor");
    llvm::Value* nextFracIdx = m_builder->CreateAdd(fracIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextfracidx");
    fracIdxPhi->addIncoming(nextFracIdx, fracBodyBB);
    fracValPhi->addIncoming(nextFracVal, fracBodyBB);
    factorPhi->addIncoming(nextFactor, fracBodyBB);
    m_builder->CreateBr(fracLoopBB);

    m_builder->SetInsertPoint(finishBB);
    llvm::PHINode* finalValPhi = m_builder->CreatePHI(llvm::Type::getDoubleTy(*m_context), 2, "finalval");
    finalValPhi->addIncoming(intValPhi, checkDotBB);
    finalValPhi->addIncoming(fracValPhi, fracLoopBB);

    llvm::Value* negFinalVal = m_builder->CreateFNeg(finalValPhi, "negfinalval");
    llvm::Value* retVal = m_builder->CreateSelect(isMinus, negFinalVal, finalValPhi, "retval");
    m_builder->CreateRet(retVal);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateLikeMatch() {
    llvm::Function* func = m_module->getFunction("__llbc_like_match");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt1Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_like_match", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* checkNullBB = llvm::BasicBlock::Create(*m_context, "check.null", func);
    llvm::BasicBlock* nullRetBB = llvm::BasicBlock::Create(*m_context, "null.ret", func);
    llvm::BasicBlock* loopBB = llvm::BasicBlock::Create(*m_context, "match.loop", func);
    llvm::BasicBlock* checkPatEndBB = llvm::BasicBlock::Create(*m_context, "check.patend", func);
    llvm::BasicBlock* checkStarBB = llvm::BasicBlock::Create(*m_context, "check.star", func);
    llvm::BasicBlock* handleStarBB = llvm::BasicBlock::Create(*m_context, "handle.star", func);
    llvm::BasicBlock* checkStrEndBB = llvm::BasicBlock::Create(*m_context, "check.strend", func);
    llvm::BasicBlock* checkCharBB = llvm::BasicBlock::Create(*m_context, "check.char", func);
    llvm::BasicBlock* matchCharBB = llvm::BasicBlock::Create(*m_context, "match.char", func);
    llvm::BasicBlock* checkBacktrackBB = llvm::BasicBlock::Create(*m_context, "check.backtrack", func);
    llvm::BasicBlock* doBacktrackBB = llvm::BasicBlock::Create(*m_context, "do.backtrack", func);
    llvm::BasicBlock* retTrueBB = llvm::BasicBlock::Create(*m_context, "ret.true", func);
    llvm::BasicBlock* retFalseBB = llvm::BasicBlock::Create(*m_context, "ret.false", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* sArg = func->getArg(0);
    llvm::Argument* pArg = func->getArg(1);

    llvm::Value* isSNull = m_builder->CreateIsNull(sArg, "issnull");
    llvm::Value* isPNull = m_builder->CreateIsNull(pArg, "ispnull");
    llvm::Value* isAnyNull = m_builder->CreateOr(isSNull, isPNull, "isanynull");
    m_builder->CreateCondBr(isAnyNull, nullRetBB, checkNullBB);

    m_builder->SetInsertPoint(nullRetBB);
    llvm::Value* bothNull = m_builder->CreateAnd(isSNull, isPNull, "bothnull");
    m_builder->CreateRet(bothNull);

    m_builder->SetInsertPoint(checkNullBB);
    // Variables for backtrack:
    // sIdx, pIdx, starIdx (-1), matchIdx (0)
    llvm::Value* negOne = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), -1, true);
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    m_builder->CreateBr(loopBB);

    m_builder->SetInsertPoint(loopBB);
    llvm::PHINode* sIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 4, "sidx");
    sIdxPhi->addIncoming(zero64, checkNullBB);
    llvm::PHINode* pIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 4, "pidx");
    pIdxPhi->addIncoming(zero64, checkNullBB);
    llvm::PHINode* starIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 4, "staridx");
    starIdxPhi->addIncoming(negOne, checkNullBB);
    llvm::PHINode* matchIdxPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 4, "matchidx");
    matchIdxPhi->addIncoming(zero64, checkNullBB);

    llvm::Value* pChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), pArg, pIdxPhi, "pchptr");
    llvm::Value* pCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), pChPtr, "pch");
    llvm::Value* isPatEnd = m_builder->CreateICmpEQ(pCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "ispatend");
    m_builder->CreateCondBr(isPatEnd, checkPatEndBB, checkStarBB);

    m_builder->SetInsertPoint(checkStarBB);
    llvm::Value* isStar = m_builder->CreateICmpEQ(pCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '*'), "isstar");
    m_builder->CreateCondBr(isStar, handleStarBB, checkStrEndBB);

    // Case '*': record starIdx = pIdx, matchIdx = sIdx, advance pIdx
    m_builder->SetInsertPoint(handleStarBB);
    llvm::Value* nextPStar = m_builder->CreateAdd(pIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextpstar");
    sIdxPhi->addIncoming(sIdxPhi, handleStarBB);
    pIdxPhi->addIncoming(nextPStar, handleStarBB);
    starIdxPhi->addIncoming(pIdxPhi, handleStarBB);
    matchIdxPhi->addIncoming(sIdxPhi, handleStarBB);
    m_builder->CreateBr(loopBB);

    // Check if string has reached end
    m_builder->SetInsertPoint(checkStrEndBB);
    llvm::Value* sChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, sIdxPhi, "schptr");
    llvm::Value* sCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), sChPtr, "sch");
    llvm::Value* isStrEnd = m_builder->CreateICmpEQ(sCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "isstrend");
    m_builder->CreateCondBr(isStrEnd, checkBacktrackBB, checkCharBB);

    // Check pattern character match: '?' or direct character match
    m_builder->SetInsertPoint(checkCharBB);
    llvm::Value* isQMark = m_builder->CreateICmpEQ(pCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '?'), "isqmark");
    llvm::Value* isExactMatch = m_builder->CreateICmpEQ(pCh, sCh, "isexact");
    llvm::Value* isMatch = m_builder->CreateOr(isQMark, isExactMatch, "ismatch");
    m_builder->CreateCondBr(isMatch, matchCharBB, checkBacktrackBB);

    // Advance both
    m_builder->SetInsertPoint(matchCharBB);
    llvm::Value* nextS = m_builder->CreateAdd(sIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nexts");
    llvm::Value* nextP = m_builder->CreateAdd(pIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextp");
    sIdxPhi->addIncoming(nextS, matchCharBB);
    pIdxPhi->addIncoming(nextP, matchCharBB);
    starIdxPhi->addIncoming(starIdxPhi, matchCharBB);
    matchIdxPhi->addIncoming(matchIdxPhi, matchCharBB);
    m_builder->CreateBr(loopBB);

    // Check if we can backtrack using star
    m_builder->SetInsertPoint(checkBacktrackBB);
    llvm::Value* hasStar = m_builder->CreateICmpNE(starIdxPhi, negOne, "hasstar");
    m_builder->CreateCondBr(hasStar, doBacktrackBB, retFalseBB);

    m_builder->SetInsertPoint(doBacktrackBB);
    // If matchIdx points to end of string, cannot advance match
    llvm::Value* matchChPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, matchIdxPhi, "mchptr");
    llvm::Value* matchCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), matchChPtr, "mch");
    llvm::Value* isMatchEnd = m_builder->CreateICmpEQ(matchCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "ismatchend");
    llvm::BasicBlock* advanceMatchBB = llvm::BasicBlock::Create(*m_context, "advance.match", func, retFalseBB);
    m_builder->CreateCondBr(isMatchEnd, retFalseBB, advanceMatchBB);

    m_builder->SetInsertPoint(advanceMatchBB);
    llvm::Value* nextMatch = m_builder->CreateAdd(matchIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "nextmatch");
    llvm::Value* pAfterStar = m_builder->CreateAdd(starIdxPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "pafterstar");
    sIdxPhi->addIncoming(nextMatch, advanceMatchBB);
    pIdxPhi->addIncoming(pAfterStar, advanceMatchBB);
    starIdxPhi->addIncoming(starIdxPhi, advanceMatchBB);
    matchIdxPhi->addIncoming(nextMatch, advanceMatchBB);
    m_builder->CreateBr(loopBB);

    // Pattern ended: check if string also ended, or if remaining star can be backtracked
    m_builder->SetInsertPoint(checkPatEndBB);
    llvm::Value* sEndPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), sArg, sIdxPhi, "sendptr");
    llvm::Value* sEndCh = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), sEndPtr, "sendch");
    llvm::Value* sEnded = m_builder->CreateICmpEQ(sEndCh, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), "sended");
    m_builder->CreateCondBr(sEnded, retTrueBB, checkBacktrackBB);

    m_builder->SetInsertPoint(retTrueBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1));

    m_builder->SetInsertPoint(retFalseBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::GlobalVariable* LlvmEmitter::getOrCreateFileTable() {
    // Global array of 256 FILE* pointers: [256 x ptr]
    llvm::GlobalVariable* table = m_module->getGlobalVariable("__llbc_file_table");
    if (!table) {
        llvm::ArrayType* arrTy = llvm::ArrayType::get(llvm::PointerType::get(*m_context, 0), 256);
        table = new llvm::GlobalVariable(
            *m_module,
            arrTy,
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantAggregateZero::get(arrTy),
            "__llbc_file_table"
        );
    }
    return table;
}

llvm::Function* LlvmEmitter::getOrCreateFileOpen() {
    // __llbc_file_open(filePath: ptr, mode: i32, fileNum: i32) -> i32 (0 on success, -1 on error)
    llvm::Function* func = m_module->getFunction("__llbc_file_open");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt32Ty(*m_context), llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_open", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* modeInputBB = llvm::BasicBlock::Create(*m_context, "mode.input", func);
    llvm::BasicBlock* modeOutputBB = llvm::BasicBlock::Create(*m_context, "mode.output", func);
    llvm::BasicBlock* modeAppendBB = llvm::BasicBlock::Create(*m_context, "mode.append", func);
    llvm::BasicBlock* modeBinaryBB = llvm::BasicBlock::Create(*m_context, "mode.binary", func);
    llvm::BasicBlock* doOpenBB = llvm::BasicBlock::Create(*m_context, "do.open", func);
    llvm::BasicBlock* storeBB = llvm::BasicBlock::Create(*m_context, "store.fp", func);
    llvm::BasicBlock* errBB = llvm::BasicBlock::Create(*m_context, "err.exit", func);

    llvm::Value* rStr = m_builder->CreateGlobalString("r", "mode.r");
    llvm::Value* wStr = m_builder->CreateGlobalString("w", "mode.w");
    llvm::Value* aStr = m_builder->CreateGlobalString("a", "mode.a");
    llvm::Value* binStr = m_builder->CreateGlobalString("a+b", "mode.bin");

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* pathArg = func->getArg(0);
    llvm::Argument* modeArg = func->getArg(1);
    llvm::Argument* numArg = func->getArg(2);

    // Validate file number (1 <= num <= 255)
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context), "fnum64");
    llvm::Value* numGe1 = m_builder->CreateICmpSGE(numArg, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1));
    llvm::Value* numLe255 = m_builder->CreateICmpSLE(numArg, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 255));
    llvm::Value* numValid = m_builder->CreateAnd(numGe1, numLe255);
    llvm::BasicBlock* checkModeBB = llvm::BasicBlock::Create(*m_context, "check.mode", func);
    m_builder->CreateCondBr(numValid, checkModeBB, errBB);

    m_builder->SetInsertPoint(checkModeBB);
    // Mode switch: 0=Input ("r"), 1=Output ("w"), 2=Append ("a"), 3=Binary ("w+b" or "rb")
    llvm::SwitchInst* sw = m_builder->CreateSwitch(modeArg, modeInputBB, 4);
    sw->addCase(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), modeInputBB);
    sw->addCase(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1), modeOutputBB);
    sw->addCase(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 2), modeAppendBB);
    sw->addCase(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 3), modeBinaryBB);

    m_builder->SetInsertPoint(modeInputBB);
    m_builder->CreateBr(doOpenBB);

    m_builder->SetInsertPoint(modeOutputBB);
    m_builder->CreateBr(doOpenBB);

    m_builder->SetInsertPoint(modeAppendBB);
    m_builder->CreateBr(doOpenBB);

    m_builder->SetInsertPoint(modeBinaryBB);
    m_builder->CreateBr(doOpenBB);

    m_builder->SetInsertPoint(doOpenBB);
    llvm::PHINode* modeStrPhi = m_builder->CreatePHI(llvm::PointerType::get(*m_context, 0), 4, "modestr");
    modeStrPhi->addIncoming(rStr, modeInputBB);
    modeStrPhi->addIncoming(wStr, modeOutputBB);
    modeStrPhi->addIncoming(aStr, modeAppendBB);
    modeStrPhi->addIncoming(binStr, modeBinaryBB);

    llvm::Function* fopenFn = m_module->getFunction("fopen");
    if (!fopenFn) {
        llvm::FunctionType* fopenTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        fopenFn = llvm::Function::Create(fopenTy, llvm::Function::ExternalLinkage, "fopen", m_module.get());
    }

    llvm::Value* fp = m_builder->CreateCall(fopenFn, {pathArg, modeStrPhi}, "newfp");
    llvm::Value* isFpNull = m_builder->CreateIsNull(fp, "fpnull");
    m_builder->CreateCondBr(isFpNull, errBB, storeBB);

    m_builder->SetInsertPoint(storeBB);
    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64}, "slotgep");
    m_builder->CreateStore(fp, slotGEP);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));

    m_builder->SetInsertPoint(errBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), -1));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateFileClose() {
    // __llbc_file_close(fileNum: i32) -> i32 (if fileNum == 0, close all 1..255)
    llvm::Function* func = m_module->getFunction("__llbc_file_close");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_close", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* closeOneBB = llvm::BasicBlock::Create(*m_context, "close.one", func);
    llvm::BasicBlock* closeAllBB = llvm::BasicBlock::Create(*m_context, "close.all", func);
    llvm::BasicBlock* allLoopBB = llvm::BasicBlock::Create(*m_context, "all.loop", func);
    llvm::BasicBlock* allBodyBB = llvm::BasicBlock::Create(*m_context, "all.body", func);
    llvm::BasicBlock* retBB = llvm::BasicBlock::Create(*m_context, "ret", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* numArg = func->getArg(0);
    llvm::Value* isZero = m_builder->CreateICmpEQ(numArg, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
    m_builder->CreateCondBr(isZero, closeAllBB, closeOneBB);

    llvm::Function* fcloseFn = m_module->getFunction("fclose");
    if (!fcloseFn) {
        llvm::FunctionType* fcloseTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        fcloseFn = llvm::Function::Create(fcloseTy, llvm::Function::ExternalLinkage, "fclose", m_module.get());
    }

    m_builder->SetInsertPoint(closeOneBB);
    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64});
    llvm::Value* fp = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), slotGEP, "curfp");
    llvm::Value* isNull = m_builder->CreateIsNull(fp);
    llvm::BasicBlock* doCloseBB = llvm::BasicBlock::Create(*m_context, "do.close", func, retBB);
    m_builder->CreateCondBr(isNull, retBB, doCloseBB);

    m_builder->SetInsertPoint(doCloseBB);
    m_builder->CreateCall(fcloseFn, {fp});
    m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), slotGEP);
    m_builder->CreateBr(retBB);

    m_builder->SetInsertPoint(closeAllBB);
    m_builder->CreateBr(allLoopBB);

    m_builder->SetInsertPoint(allLoopBB);
    llvm::PHINode* iPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "alli");
    iPhi->addIncoming(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), closeAllBB);
    llvm::Value* isEnd = m_builder->CreateICmpUGT(iPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 255));
    m_builder->CreateCondBr(isEnd, retBB, allBodyBB);

    m_builder->SetInsertPoint(allBodyBB);
    llvm::Value* aSlotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, iPhi});
    llvm::Value* aFp = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), aSlotGEP);
    llvm::Value* aIsNull = m_builder->CreateIsNull(aFp);
    llvm::BasicBlock* closeThisBB = llvm::BasicBlock::Create(*m_context, "close.this", func);
    llvm::BasicBlock* nextAllBB = llvm::BasicBlock::Create(*m_context, "next.all", func);
    m_builder->CreateCondBr(aIsNull, nextAllBB, closeThisBB);

    m_builder->SetInsertPoint(closeThisBB);
    m_builder->CreateCall(fcloseFn, {aFp});
    m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), aSlotGEP);
    m_builder->CreateBr(nextAllBB);

    m_builder->SetInsertPoint(nextAllBB);
    llvm::Value* nextI = m_builder->CreateAdd(iPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1));
    iPhi->addIncoming(nextI, nextAllBB);
    m_builder->CreateBr(allLoopBB);

    m_builder->SetInsertPoint(retBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateFilePrintStr() {
    // __llbc_file_print_str(fileNum: i32, str: ptr)
    llvm::Function* func = m_module->getFunction("__llbc_file_print_str");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getVoidTy(*m_context),
            {llvm::Type::getInt32Ty(*m_context), llvm::PointerType::get(*m_context, 0)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_print_str", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* writeBB = llvm::BasicBlock::Create(*m_context, "write", func);
    llvm::BasicBlock* exitBB = llvm::BasicBlock::Create(*m_context, "exit", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* numArg = func->getArg(0);
    llvm::Argument* strArg = func->getArg(1);

    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64});
    llvm::Value* fp = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), slotGEP, "fp");
    llvm::Value* isFpNull = m_builder->CreateIsNull(fp);
    llvm::Value* isStrNull = m_builder->CreateIsNull(strArg);
    llvm::Value* bad = m_builder->CreateOr(isFpNull, isStrNull);
    m_builder->CreateCondBr(bad, exitBB, writeBB);

    m_builder->SetInsertPoint(writeBB);
    llvm::Function* fputsFn = m_module->getFunction("fputs");
    if (!fputsFn) {
        llvm::FunctionType* fputsTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::PointerType::get(*m_context, 0)},
            false
        );
        fputsFn = llvm::Function::Create(fputsTy, llvm::Function::ExternalLinkage, "fputs", m_module.get());
    }
    m_builder->CreateCall(fputsFn, {strArg, fp});
    m_builder->CreateBr(exitBB);

    m_builder->SetInsertPoint(exitBB);
    m_builder->CreateRetVoid();

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateFileLineInput() {
    // __llbc_file_line_input(fileNum: i32) -> ptr (allocated string containing line without trailing \r\n)
    llvm::Function* func = m_module->getFunction("__llbc_file_line_input");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_line_input", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* readBB = llvm::BasicBlock::Create(*m_context, "read", func);
    llvm::BasicBlock* nullRetBB = llvm::BasicBlock::Create(*m_context, "ret.null", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* numArg = func->getArg(0);

    // If fileNum == 0, use standard stdin
    llvm::BasicBlock* checkZeroBB = llvm::BasicBlock::Create(*m_context, "check.zero", func);
    llvm::BasicBlock* tableLookupBB = llvm::BasicBlock::Create(*m_context, "table.lookup", func);

    llvm::Value* isZero = m_builder->CreateICmpEQ(numArg, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
    m_builder->CreateCondBr(isZero, checkZeroBB, tableLookupBB);

    m_builder->SetInsertPoint(checkZeroBB);
    llvm::GlobalVariable* stdinVar = m_module->getGlobalVariable("stdin");
    if (!stdinVar) {
        stdinVar = new llvm::GlobalVariable(
            *m_module,
            llvm::PointerType::get(*m_context, 0),
            false,
            llvm::GlobalValue::ExternalLinkage,
            nullptr,
            "stdin"
        );
    }
    llvm::Value* stdinVal = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), stdinVar, "stdin.load");
    m_builder->CreateCondBr(m_builder->CreateIsNull(stdinVal), nullRetBB, readBB);

    m_builder->SetInsertPoint(tableLookupBB);
    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64});
    llvm::Value* fpLoaded = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), slotGEP, "fp");
    m_builder->CreateCondBr(m_builder->CreateIsNull(fpLoaded), nullRetBB, readBB);

    m_builder->SetInsertPoint(readBB);
    llvm::PHINode* fp = m_builder->CreatePHI(llvm::PointerType::get(*m_context, 0), 2, "fp");
    fp->addIncoming(stdinVal, checkZeroBB);
    fp->addIncoming(fpLoaded, tableLookupBB);
    llvm::Function* mallocFn = getOrCreateMalloc();
    // Allocate a 4096-byte line buffer
    llvm::Value* bufSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 4096);
    llvm::Value* lineBuf = m_builder->CreateCall(mallocFn, {bufSize}, "linebuf");

    llvm::Function* fgetsFn = m_module->getFunction("fgets");
    if (!fgetsFn) {
        llvm::FunctionType* fgetsTy = llvm::FunctionType::get(
            llvm::PointerType::get(*m_context, 0),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt32Ty(*m_context), llvm::PointerType::get(*m_context, 0)},
            false
        );
        fgetsFn = llvm::Function::Create(fgetsTy, llvm::Function::ExternalLinkage, "fgets", m_module.get());
    }

    llvm::Value* res = m_builder->CreateCall(
        fgetsFn,
        {lineBuf, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 4096), fp},
        "fgets.res"
    );
    llvm::Value* isEof = m_builder->CreateIsNull(res);
    llvm::BasicBlock* trimBB = llvm::BasicBlock::Create(*m_context, "trim.nl", func);
    m_builder->CreateCondBr(isEof, nullRetBB, trimBB);

    m_builder->SetInsertPoint(trimBB);
    // Strip trailing \r and \n: while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r')) buf[--len] = 0;
    llvm::Function* strlenFn = getOrCreateStrlen();
    llvm::Value* rawLen = m_builder->CreateCall(strlenFn, {lineBuf}, "rawlen");
    llvm::BasicBlock* trimLoopBB = llvm::BasicBlock::Create(*m_context, "trim.loop", func);
    llvm::BasicBlock* trimDoneBB = llvm::BasicBlock::Create(*m_context, "trim.done", func);
    m_builder->CreateBr(trimLoopBB);

    m_builder->SetInsertPoint(trimLoopBB);
    llvm::PHINode* lenPhi = m_builder->CreatePHI(llvm::Type::getInt64Ty(*m_context), 2, "curlen");
    lenPhi->addIncoming(rawLen, trimBB);
    llvm::Value* hasChars = m_builder->CreateICmpUGT(lenPhi, zero64);
    llvm::BasicBlock* checkCharBB = llvm::BasicBlock::Create(*m_context, "check.ch", func);
    m_builder->CreateCondBr(hasChars, checkCharBB, trimDoneBB);

    m_builder->SetInsertPoint(checkCharBB);
    llvm::Value* lastIdx = m_builder->CreateSub(lenPhi, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1));
    llvm::Value* chPtr = m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), lineBuf, lastIdx);
    llvm::Value* chVal = m_builder->CreateLoad(llvm::Type::getInt8Ty(*m_context), chPtr);
    llvm::Value* isNl = m_builder->CreateICmpEQ(chVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '\n'));
    llvm::Value* isCr = m_builder->CreateICmpEQ(chVal, llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), '\r'));
    llvm::Value* isEndSpace = m_builder->CreateOr(isNl, isCr);
    llvm::BasicBlock* stripBB = llvm::BasicBlock::Create(*m_context, "strip", func);
    m_builder->CreateCondBr(isEndSpace, stripBB, trimDoneBB);

    m_builder->SetInsertPoint(stripBB);
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), chPtr);
    lenPhi->addIncoming(lastIdx, stripBB);
    m_builder->CreateBr(trimLoopBB);

    m_builder->SetInsertPoint(trimDoneBB);
    m_builder->CreateRet(lineBuf);

    m_builder->SetInsertPoint(nullRetBB);
    llvm::Value* emptyStr = m_builder->CreateCall(mallocFn, {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1)});
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0), emptyStr);
    m_builder->CreateRet(emptyStr);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateFileEof() {
    // __llbc_file_eof(fileNum: i32) -> i1 (Boolean)
    llvm::Function* func = m_module->getFunction("__llbc_file_eof");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt1Ty(*m_context),
            {llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_eof", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* checkBB = llvm::BasicBlock::Create(*m_context, "check", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* numArg = func->getArg(0);

    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64});
    llvm::Value* fp = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), slotGEP, "fp");
    llvm::Value* isFpNull = m_builder->CreateIsNull(fp);
    llvm::BasicBlock* retTrueBB = llvm::BasicBlock::Create(*m_context, "ret.true", func);
    m_builder->CreateCondBr(isFpNull, retTrueBB, checkBB);

    m_builder->SetInsertPoint(checkBB);
    llvm::Function* feofFn = m_module->getFunction("feof");
    if (!feofFn) {
        llvm::FunctionType* feofTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        feofFn = llvm::Function::Create(feofTy, llvm::Function::ExternalLinkage, "feof", m_module.get());
    }
    llvm::Value* eofCode = m_builder->CreateCall(feofFn, {fp}, "eofcode");
    llvm::Value* isEof = m_builder->CreateICmpNE(eofCode, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
    m_builder->CreateRet(isEof);

    m_builder->SetInsertPoint(retTrueBB);
    m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1));

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::Function* LlvmEmitter::getOrCreateFileLof() {
    // __llbc_file_lof(fileNum: i32) -> i64 (length of file in bytes)
    llvm::Function* func = m_module->getFunction("__llbc_file_lof");
    if (func && !func->isDeclaration()) return func;
    if (!func) {
        llvm::FunctionType* fnTy = llvm::FunctionType::get(
            llvm::Type::getInt64Ty(*m_context),
            {llvm::Type::getInt32Ty(*m_context)},
            false
        );
        func = llvm::Function::Create(fnTy, llvm::Function::LinkOnceODRLinkage, "__llbc_file_lof", m_module.get());
    } else {
        func->setLinkage(llvm::Function::LinkOnceODRLinkage);
    }

    auto prevBB = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();

    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    llvm::BasicBlock* calcBB = llvm::BasicBlock::Create(*m_context, "calc", func);
    llvm::BasicBlock* retZeroBB = llvm::BasicBlock::Create(*m_context, "ret.zero", func);

    m_builder->SetInsertPoint(entryBB);
    llvm::Argument* numArg = func->getArg(0);

    llvm::GlobalVariable* table = getOrCreateFileTable();
    llvm::Value* num64 = m_builder->CreateZExt(numArg, llvm::Type::getInt64Ty(*m_context));
    llvm::Value* zero64 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    llvm::Value* slotGEP = m_builder->CreateGEP(table->getValueType(), table, {zero64, num64});
    llvm::Value* fp = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), slotGEP, "fp");
    llvm::Value* isFpNull = m_builder->CreateIsNull(fp);
    m_builder->CreateCondBr(isFpNull, retZeroBB, calcBB);

    m_builder->SetInsertPoint(calcBB);
    // fseek(fp, offset, whence), ftell(fp)
    llvm::Function* ftellFn = m_module->getFunction("ftell");
    if (!ftellFn) {
        llvm::FunctionType* ftellTy = llvm::FunctionType::get(
            llvm::Type::getInt64Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0)},
            false
        );
        ftellFn = llvm::Function::Create(ftellTy, llvm::Function::ExternalLinkage, "ftell", m_module.get());
    }
    llvm::Function* fseekFn = m_module->getFunction("fseek");
    if (!fseekFn) {
        llvm::FunctionType* fseekTy = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::PointerType::get(*m_context, 0), llvm::Type::getInt64Ty(*m_context), llvm::Type::getInt32Ty(*m_context)},
            false
        );
        fseekFn = llvm::Function::Create(fseekTy, llvm::Function::ExternalLinkage, "fseek", m_module.get());
    }

    // Save current position
    llvm::Value* curPos = m_builder->CreateCall(ftellFn, {fp}, "curpos");
    // fseek(fp, 0, SEEK_END=2)
    m_builder->CreateCall(fseekFn, {fp, zero64, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 2)});
    // file size = ftell(fp)
    llvm::Value* sizeVal = m_builder->CreateCall(ftellFn, {fp}, "filesize");
    // restore original position: fseek(fp, curPos, SEEK_SET=0)
    m_builder->CreateCall(fseekFn, {fp, curPos, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0)});
    m_builder->CreateRet(sizeVal);

    m_builder->SetInsertPoint(retZeroBB);
    m_builder->CreateRet(zero64);

    if (prevBB) m_builder->SetInsertPoint(prevBB, prevPoint);
    return func;
}

llvm::GlobalVariable* LlvmEmitter::getOrCreateErrNumber() {
    llvm::GlobalVariable* g = m_module->getGlobalVariable("__llbc_err_number");
    if (!g) {
        g = new llvm::GlobalVariable(
            *m_module,
            llvm::Type::getInt32Ty(*m_context),
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0),
            "__llbc_err_number"
        );
    }
    return g;
}

llvm::GlobalVariable* LlvmEmitter::getOrCreateErrSource() {
    llvm::GlobalVariable* g = m_module->getGlobalVariable("__llbc_err_source");
    if (!g) {
        g = new llvm::GlobalVariable(
            *m_module,
            llvm::PointerType::get(*m_context, 0),
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)),
            "__llbc_err_source"
        );
    }
    return g;
}

llvm::GlobalVariable* LlvmEmitter::getOrCreateErrDescription() {
    llvm::GlobalVariable* g = m_module->getGlobalVariable("__llbc_err_description");
    if (!g) {
        g = new llvm::GlobalVariable(
            *m_module,
            llvm::PointerType::get(*m_context, 0),
            false,
            llvm::GlobalValue::LinkOnceODRLinkage,
            llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)),
            "__llbc_err_description"
        );
    }
    return g;
}

void LlvmEmitter::emitEnum(const EnumNode& enumNode) {
    for (const auto& member : enumNode.members) {
        m_enums[enumNode.name][member.name] = member.value;
        m_enums[toLower(enumNode.name)][toLower(member.name)] = member.value;
        m_enumConstants[member.name] = member.value;
        m_enumConstants[toLower(member.name)] = member.value;
    }
}

void LlvmEmitter::emitInterface(const InterfaceNode& iface) {
    std::vector<llvm::Type*> methodPtrTys;
    for (size_t mi = 0; mi < iface.methods.size(); ++mi) {
        methodPtrTys.push_back(llvm::PointerType::get(*m_context, 0));
    }
    if (methodPtrTys.empty()) {
        methodPtrTys.push_back(llvm::PointerType::get(*m_context, 0));
    }
    llvm::StructType* ifaceSt = llvm::StructType::create(*m_context, iface.name);
    ifaceSt->setBody(methodPtrTys, false);
    m_structTypes[iface.name] = ifaceSt;
    m_structTypes[toLower(iface.name)] = ifaceSt;
    for (size_t mi = 0; mi < iface.methods.size(); ++mi) {
        m_structFieldIndices[iface.name][toLower(iface.methods[mi].name)] = mi;
        m_structFieldIndices[toLower(iface.name)][toLower(iface.methods[mi].name)] = mi;
    }
    m_interfaces[iface.name] = &iface;
    m_interfaces[toLower(iface.name)] = &iface;
}

void LlvmEmitter::emitDelegate(const DelegateNode& del) {
    m_delegates.insert(del.name);
    m_delegates.insert(toLower(del.name));
}

void LlvmEmitter::emitWithStatement(const WithStmtNode& withNode) {
    if (!withNode.target) return;
    llvm::Value* basePtr = getPointerToExpr(withNode.target.get());
    if (!basePtr) return;
    TypeSpec baseType;
    if (auto var = dynamic_cast<VariableExprASTNode*>(withNode.target.get())) {
        auto it = m_variableTypes.find(var->name);
        if (it != m_variableTypes.end()) baseType = it->second;
    }
    m_withStack.push_back({basePtr, baseType});
    for (const auto& stmt : withNode.body) {
        emitStatement(stmt.get());
    }
    m_withStack.pop_back();
}

TypeSpec LlvmEmitter::substituteTypeSpec(const TypeSpec& spec, const std::unordered_map<std::string, TypeSpec>& typeMap) {
    TypeSpec res = spec;
    auto it = typeMap.find(spec.name);
    if (it != typeMap.end()) {
        res.name = it->second.name;
        res.pointerDepth += it->second.pointerDepth;
        if (it->second.isVolatile) res.isVolatile = true;
        if (it->second.isArray) {
            res.isArray = true;
            res.arraySize = it->second.arraySize;
            res.dimensions = it->second.dimensions;
        }
        res.typeArgs = it->second.typeArgs;
    } else {
        std::string lower = toLower(spec.name);
        for (const auto& pair : typeMap) {
            if (toLower(pair.first) == lower) {
                res.name = pair.second.name;
                res.pointerDepth += pair.second.pointerDepth;
                if (pair.second.isVolatile) res.isVolatile = true;
                if (pair.second.isArray) {
                    res.isArray = true;
                    res.arraySize = pair.second.arraySize;
                    res.dimensions = pair.second.dimensions;
                }
                res.typeArgs = pair.second.typeArgs;
                break;
            }
        }
    }
    for (auto& ta : res.typeArgs) {
        ta = substituteTypeSpec(ta, typeMap);
    }
    return res;
}

std::string LlvmEmitter::instantiateGenericStruct(const TypeSpec& typeSpec) {
    if (typeSpec.typeArgs.empty()) return typeSpec.name;

    std::string mangledName = typeSpec.name;
    for (const auto& ta : typeSpec.typeArgs) {
        mangledName += "_" + ta.name;
    }

    if (m_structTypes.find(mangledName) != m_structTypes.end()) {
        return mangledName;
    }

    auto tmplIt = m_genericStructTemplates.find(typeSpec.name);
    if (tmplIt == m_genericStructTemplates.end()) {
        tmplIt = m_genericStructTemplates.find(toLower(typeSpec.name));
    }
    if (tmplIt == m_genericStructTemplates.end()) {
        return typeSpec.name;
    }

    const StructureNode& tmpl = *tmplIt->second;
    std::unordered_map<std::string, TypeSpec> typeMap;
    for (size_t i = 0; i < tmpl.genericParams.size() && i < typeSpec.typeArgs.size(); ++i) {
        typeMap[tmpl.genericParams[i]] = typeSpec.typeArgs[i];
        typeMap[toLower(tmpl.genericParams[i])] = typeSpec.typeArgs[i];
    }

    StructureNode concrete;
    concrete.name = mangledName;
    concrete.isPacked = tmpl.isPacked;
    concrete.isUnion = tmpl.isUnion;
    concrete.alignment = tmpl.alignment;

    for (const auto& field : tmpl.fields) {
        StructureField concreteField;
        concreteField.name = field.name;
        concreteField.isPublic = field.isPublic;
        concreteField.type = substituteTypeSpec(field.type, typeMap);
        concrete.fields.push_back(concreteField);
    }

    emitStructure(concrete);
    return mangledName;
}

std::string LlvmEmitter::instantiateGenericProcedure(const std::string& baseName, const std::vector<TypeSpec>& typeArgs) {
    if (typeArgs.empty()) return baseName;

    std::string mangledName = baseName;
    for (const auto& ta : typeArgs) {
        mangledName += "_" + ta.name;
    }

    if (m_module->getFunction(mangledName) || m_module->getFunction(toLower(mangledName))) {
        return mangledName;
    }

    auto tmplIt = m_genericProcTemplates.find(baseName);
    if (tmplIt == m_genericProcTemplates.end()) {
        tmplIt = m_genericProcTemplates.find(toLower(baseName));
    }
    if (tmplIt == m_genericProcTemplates.end()) {
        return baseName;
    }

    const ProcedureNode& tmpl = *tmplIt->second;
    std::unordered_map<std::string, TypeSpec> typeMap;
    for (size_t i = 0; i < tmpl.genericParams.size() && i < typeArgs.size(); ++i) {
        typeMap[tmpl.genericParams[i]] = typeArgs[i];
        typeMap[toLower(tmpl.genericParams[i])] = typeArgs[i];
    }

    ProcedureNode concrete;
    concrete.name = mangledName;
    concrete.isPublic = tmpl.isPublic;
    concrete.isUnsafe = tmpl.isUnsafe;
    concrete.isFunction = tmpl.isFunction;
    concrete.isDeclare = tmpl.isDeclare;
    concrete.isInline = tmpl.isInline;
    concrete.isNoReturn = tmpl.isNoReturn;
    concrete.isExport = tmpl.isExport;
    concrete.propertyKind = tmpl.propertyKind;
    concrete.returnType = substituteTypeSpec(tmpl.returnType, typeMap);

    for (const auto& p : tmpl.parameters) {
        ParameterNode concreteParam;
        concreteParam.name = p.name;
        concreteParam.isByRef = p.isByRef;
        concreteParam.isOptional = p.isOptional;
        concreteParam.isParamArray = p.isParamArray;
        concreteParam.type = substituteTypeSpec(p.type, typeMap);
        concrete.parameters.push_back(std::move(concreteParam));
    }

    // Reference the template body statements
    const std::vector<std::unique_ptr<ASTNode>>* bodyPtr = &tmpl.body;


    // Map template procedure name to concrete return alloca during body emission
    // Register return type
    m_procReturnTypes[mangledName] = concrete.returnType;
    m_procReturnTypes[toLower(mangledName)] = concrete.returnType;

    // Save full emitter state before nested procedure emission
    auto prevBlock = m_builder->GetInsertBlock();
    auto prevPoint = m_builder->GetInsertPoint();
    auto savedNamedValues = m_namedValues;
    auto savedVariableTypes = m_variableTypes;
    auto savedExitBlock = m_exitBlock;
    auto savedRetAlloca = m_retAlloca;
    auto savedBreakStack = m_breakStack;
    auto savedContinueStack = m_continueStack;
    auto savedLabels = m_labels;
    auto savedCatchStack = m_catchStack;
    auto savedTryErrAllocaStack = m_tryErrAllocaStack;
    auto savedDiScopes = m_diScopes;
    bool savedUnsafe = m_currentProcIsUnsafe;
    std::string savedProcName = m_currentProcName;
    std::string savedScopeClass = m_currentScopeClass;
    bool savedReturnAssigned = m_returnAssigned;

    llvm::DebugLoc savedDebugLoc;
    if (m_enableDebugInfo) {
        savedDebugLoc = m_builder->getCurrentDebugLocation();
    }

    emitProcedure(concrete, "", bodyPtr);

    // Restore full emitter state
    m_namedValues = savedNamedValues;
    m_variableTypes = savedVariableTypes;
    m_exitBlock = savedExitBlock;
    m_retAlloca = savedRetAlloca;
    m_breakStack = savedBreakStack;
    m_continueStack = savedContinueStack;
    m_labels = savedLabels;
    m_catchStack = savedCatchStack;
    m_tryErrAllocaStack = savedTryErrAllocaStack;
    m_diScopes = savedDiScopes;
    m_currentProcIsUnsafe = savedUnsafe;
    m_currentProcName = savedProcName;
    m_currentScopeClass = savedScopeClass;
    m_returnAssigned = savedReturnAssigned;

    if (m_enableDebugInfo) {
        m_builder->SetCurrentDebugLocation(savedDebugLoc);
    }
    if (prevBlock) {
        if (prevPoint != prevBlock->end()) {
            m_builder->SetInsertPoint(prevBlock, prevPoint);
        } else {
            m_builder->SetInsertPoint(prevBlock);
        }
    }

    return mangledName;
}



void LlvmEmitter::emitStructure(const StructureNode& structNode) {
    if (!structNode.genericParams.empty()) {
        // Register generic structure template for on-demand monomorphization
        m_genericStructTemplates[structNode.name] = &structNode;
        m_genericStructTemplates[toLower(structNode.name)] = &structNode;
        return;
    }


    std::vector<llvm::Type*> fieldTypes;
    std::unordered_map<std::string, unsigned> fieldIndices;
    std::unordered_map<std::string, BitfieldInfo> bitfieldMap;

    if (structNode.isUnion) {
        m_unionTypes.insert(structNode.name);
        m_unionTypes.insert(toLower(structNode.name));

        const llvm::DataLayout& dl = m_module->getDataLayout();
        uint64_t maxFieldSize = 0;
        unsigned idx = 0;
        for (const auto& field : structNode.fields) {
            llvm::Type* fTy = getLlvmType(field.type);
            uint64_t sz = dl.getTypeAllocSize(fTy);
            if (sz > maxFieldSize) maxFieldSize = sz;

            fieldIndices[field.name] = 0;
            fieldIndices[toLower(field.name)] = 0;
            m_structFieldTypes[structNode.name][field.name] = field.type;
            m_structFieldTypes[structNode.name][toLower(field.name)] = field.type;
            m_structFieldTypes[toLower(structNode.name)][field.name] = field.type;
            m_structFieldTypes[toLower(structNode.name)][toLower(field.name)] = field.type;

            if (field.bitfieldWidth > 0) {
                uint32_t containerBits = static_cast<uint32_t>(sz * 8);
                if (containerBits == 0) containerBits = 8;
                BitfieldInfo binfo{0, 0, field.bitfieldWidth, containerBits};
                bitfieldMap[field.name] = binfo;
                bitfieldMap[toLower(field.name)] = binfo;
            }
            idx++;
        }
        if (maxFieldSize == 0) maxFieldSize = 1;

        llvm::Type* byteArrTy = llvm::ArrayType::get(llvm::Type::getInt8Ty(*m_context), maxFieldSize);
        llvm::StructType* st = llvm::StructType::create(*m_context, {byteArrTy}, structNode.name, structNode.isPacked);
        m_structTypes[structNode.name] = st;
        m_structTypes[toLower(structNode.name)] = st;
        m_structFieldIndices[structNode.name] = fieldIndices;
        m_structFieldIndices[toLower(structNode.name)] = std::move(fieldIndices);
        if (!bitfieldMap.empty()) {
            m_structBitfields[structNode.name] = bitfieldMap;
            m_structBitfields[toLower(structNode.name)] = std::move(bitfieldMap);
        }
        return;
    }

    // Packing consecutive bitfield members for standard Structure
    const llvm::DataLayout& dl = m_module->getDataLayout();
    size_t fCount = structNode.fields.size();
    size_t i = 0;
    unsigned containerIndex = 0;

    while (i < fCount) {
        const auto& firstField = structNode.fields[i];
        if (firstField.bitfieldWidth == 0) {
            // Standard non-bitfield member
            llvm::Type* fTy = getLlvmType(firstField.type);
            fieldTypes.push_back(fTy);
            fieldIndices[firstField.name] = containerIndex;
            fieldIndices[toLower(firstField.name)] = containerIndex;
            m_structFieldTypes[structNode.name][firstField.name] = firstField.type;
            m_structFieldTypes[structNode.name][toLower(firstField.name)] = firstField.type;
            m_structFieldTypes[toLower(structNode.name)][firstField.name] = firstField.type;
            m_structFieldTypes[toLower(structNode.name)][toLower(firstField.name)] = firstField.type;
            containerIndex++;
            i++;
        } else {
            // Consecutive bitfields: determine container capacity from declared types
            size_t j = i;
            uint32_t totalBitsNeeded = 0;
            uint32_t maxDeclBits = 8;
            while (j < fCount && structNode.fields[j].bitfieldWidth > 0) {
                totalBitsNeeded += structNode.fields[j].bitfieldWidth;
                llvm::Type* declTy = getLlvmType(structNode.fields[j].type);
                uint32_t bits = static_cast<uint32_t>(dl.getTypeAllocSize(declTy) * 8);
                if (bits > maxDeclBits) maxDeclBits = bits;
                j++;
            }

            // Target backing container bits: 8, 16, 32, or 64
            uint32_t containerBits = maxDeclBits;
            if (totalBitsNeeded > containerBits) {
                if (totalBitsNeeded <= 16) containerBits = 16;
                else if (totalBitsNeeded <= 32) containerBits = 32;
                else containerBits = 64;
            }

            // Pack fields that fit within containerBits
            uint32_t currentBitOffset = 0;
            while (i < fCount && structNode.fields[i].bitfieldWidth > 0) {
                const auto& curField = structNode.fields[i];
                if (currentBitOffset + curField.bitfieldWidth > containerBits && currentBitOffset > 0) {
                    // Start next container
                    break;
                }
                BitfieldInfo binfo{containerIndex, currentBitOffset, curField.bitfieldWidth, containerBits};
                bitfieldMap[curField.name] = binfo;
                bitfieldMap[toLower(curField.name)] = binfo;
                fieldIndices[curField.name] = containerIndex;
                fieldIndices[toLower(curField.name)] = containerIndex;
                m_structFieldTypes[structNode.name][curField.name] = curField.type;
                m_structFieldTypes[structNode.name][toLower(curField.name)] = curField.type;
                m_structFieldTypes[toLower(structNode.name)][curField.name] = curField.type;
                m_structFieldTypes[toLower(structNode.name)][toLower(curField.name)] = curField.type;

                currentBitOffset += curField.bitfieldWidth;
                i++;
            }

            fieldTypes.push_back(llvm::Type::getIntNTy(*m_context, containerBits));
            containerIndex++;
        }
    }

    llvm::StructType* st = llvm::StructType::create(*m_context, fieldTypes, structNode.name, structNode.isPacked);
    m_structTypes[structNode.name] = st;
    m_structTypes[toLower(structNode.name)] = st;
    m_structFieldIndices[structNode.name] = fieldIndices;
    m_structFieldIndices[toLower(structNode.name)] = std::move(fieldIndices);
    if (!bitfieldMap.empty()) {
        m_structBitfields[structNode.name] = bitfieldMap;
        m_structBitfields[toLower(structNode.name)] = std::move(bitfieldMap);
    }
}

void LlvmEmitter::registerClassInstancing(const std::string& className, InstancingKind instancing) {
    m_classInstancing[className] = instancing;
    m_classInstancing[toLower(className)] = instancing;
}

void LlvmEmitter::registerPrivateField(const std::string& className, const std::string& fieldName) {
    std::string key = className + "." + fieldName;
    m_privateFields.insert(key);
    m_privateFields.insert(toLower(key));
}

void LlvmEmitter::emitDimStatement(const DimStmtNode& dimNode) {
    // Check if the type is a Class
    auto instIt = m_classInstancing.find(dimNode.type.name);
    if (instIt == m_classInstancing.end()) {
        instIt = m_classInstancing.find(toLower(dimNode.type.name));
    }
    if (instIt != m_classInstancing.end()) {
        if (instIt->second == InstancingKind::SingleUse) {
            std::string clsLower = toLower(dimNode.type.name);
            if (m_singleUseInstantiated.count(clsLower)) {
                throw std::runtime_error("Class '" + dimNode.type.name + "' is marked <Instancing(SingleUse)> and cannot be instantiated multiple times.");
            }
            m_singleUseInstantiated.insert(clsLower);
        }
        // Class instances start as UNINITIALIZED unless initialized by an explicit constructor
        // We track instances so any method call prior to .Initialize throws a compile error
    }

    if (m_namedValues.find(dimNode.varName) != m_namedValues.end() ||
        m_namedValues.find(toLower(dimNode.varName)) != m_namedValues.end()) {
        Diagnostic::report(m_sourceFilePath, dimNode.line > 0 ? dimNode.line : m_currentLine,
                           dimNode.column > 0 ? dimNode.column : m_currentCol,
                           true, "Duplicate variable declaration '" + dimNode.varName + "' in the same scope.", m_sourceText);
        m_hadError = true;
        return;
    }

    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Type* varType = getLlvmType(dimNode.type);

    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* alloca = tmpBuilder.CreateAlloca(varType, nullptr, dimNode.varName);

    m_namedValues[dimNode.varName] = alloca;
    m_namedValues[toLower(dimNode.varName)] = alloca;
    m_variableTypes[dimNode.varName] = dimNode.type;
    m_variableTypes[toLower(dimNode.varName)] = dimNode.type;

    // Optional initial value or default zero-initialization for scalar/struct types
    if (dimNode.initValue) {
        checkConstantOverflow(dimNode.type, dimNode.initValue.get(), dimNode.line, dimNode.column);
        llvm::Value* initVal = emitExpression(dimNode.initValue.get());
        if (initVal) {
            initVal = coerceType(initVal, varType);
            m_builder->CreateStore(initVal, alloca);
        }
    } else if (!dimNode.type.isArray) {
        if (varType->isSingleValueType()) {
            m_builder->CreateStore(llvm::Constant::getNullValue(varType), alloca);
        } else if (varType->isStructTy()) {
            // Zero-initialize struct/class value instance
            const llvm::DataLayout& dl = m_module->getDataLayout();
            uint64_t structSize = dl.getTypeAllocSize(varType);
            m_builder->CreateMemSet(
                alloca,
                llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0),
                llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), structSize),
                alloca->getAlign()
            );
        }
    }
}

void LlvmEmitter::declareConstant(const ConstStmtNode& constNode, const std::string& prefix) {
    std::string baseName = constNode.name;
    std::string fullName = !prefix.empty() ? (prefix + "." + baseName) : baseName;
    std::string mangledName = !prefix.empty() ? (prefix + "_" + baseName) : baseName;
    for (auto& ch : mangledName) {
        if (ch == '.') ch = '_';
    }

    if (constNode.value) {
        if (auto num = dynamic_cast<const NumberExprASTNode*>(constNode.value.get())) {
            m_enumConstants[baseName] = num->val;
            m_enumConstants[toLower(baseName)] = num->val;
            m_enumConstants[fullName] = num->val;
            m_enumConstants[toLower(fullName)] = num->val;
            m_enumConstants[mangledName] = num->val;
            m_enumConstants[toLower(mangledName)] = num->val;
        }
    }

    llvm::Type* constType = getLlvmType(constNode.type);
    if (!findGlobalCaseInsensitive(m_module.get(), baseName)) {
        new llvm::GlobalVariable(
            *m_module,
            constType,
            true, // isConstant
            llvm::GlobalValue::ExternalLinkage,
            nullptr, // external declaration
            baseName
        );
    }
    if (!prefix.empty() && !findGlobalCaseInsensitive(m_module.get(), mangledName)) {
        new llvm::GlobalVariable(
            *m_module,
            constType,
            true,
            llvm::GlobalValue::ExternalLinkage,
            nullptr,
            mangledName
        );
    }
}

void LlvmEmitter::emitConstStatement(const ConstStmtNode& constNode) {
    if (!m_builder->GetInsertBlock()) return;
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Type* constType = getLlvmType(constNode.type);

    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* alloca = tmpBuilder.CreateAlloca(constType, nullptr, constNode.name);

    m_namedValues[constNode.name] = alloca;
    m_namedValues[toLower(constNode.name)] = alloca;
    m_variableTypes[constNode.name] = constNode.type;
    m_variableTypes[toLower(constNode.name)] = constNode.type;
    m_constants.insert(constNode.name);
    m_constants.insert(toLower(constNode.name));

    if (constNode.value) {
        checkConstantOverflow(constNode.type, constNode.value.get(), constNode.line, constNode.column);
        llvm::Value* val = emitExpression(constNode.value.get());
        if (val) {
            val = coerceType(val, constType);
            m_builder->CreateStore(val, alloca);
        }
    }
}

void LlvmEmitter::emitAssignStatement(const AssignStmtNode& assignNode) {
    if (!assignNode.target || !assignNode.value) return;

    // Case 1: Variable assignment (var = val) or Module Property Let (Prop = val)
    if (auto var = dynamic_cast<VariableExprASTNode*>(assignNode.target.get())) {
        if (m_constants.count(var->name) || m_constants.count(toLower(var->name))) {
            Diagnostic::report(m_sourceFilePath, assignNode.line > 0 ? assignNode.line : m_currentLine,
                               assignNode.column > 0 ? assignNode.column : m_currentCol,
                               true, "Cannot assign to constant '" + var->name + "'.", m_sourceText);
            m_hadError = true;
            return;
        }

        auto tItCheck = m_variableTypes.find(var->name);
        if (tItCheck == m_variableTypes.end()) tItCheck = m_variableTypes.find(toLower(var->name));
        if (tItCheck != m_variableTypes.end()) {
            checkConstantOverflow(tItCheck->second, assignNode.value.get(), assignNode.line, assignNode.column);
        }

        llvm::AllocaInst* targetAlloca = nullptr;
        auto it = m_namedValues.find(var->name);
        if (it == m_namedValues.end()) {
            it = m_namedValues.find(toLower(var->name));
        }
        if (it != m_namedValues.end()) {
            targetAlloca = it->second;
        }

        if (targetAlloca) {
            if (toLower(var->name) == toLower(m_currentProcName) ||
                (targetAlloca == m_retAlloca && m_retAlloca != nullptr)) {
                m_returnAssigned = true;
            }
            llvm::Value* val = emitExpression(assignNode.value.get());
            // Re-check m_namedValues in case a nested generic instantiation restored the map
            auto itRestored = m_namedValues.find(var->name);
            if (itRestored == m_namedValues.end()) {
                itRestored = m_namedValues.find(toLower(var->name));
            }
            if (itRestored != m_namedValues.end()) {
                targetAlloca = itRestored->second;
            }
            if (val && targetAlloca) {
                if (m_byRefParams.count(var->name) || m_byRefParams.count(toLower(var->name))) {
                    auto tIt = m_variableTypes.find(var->name);
                    if (tIt == m_variableTypes.end()) {
                        tIt = m_variableTypes.find(toLower(var->name));
                    }
                    if (tIt != m_variableTypes.end() && tIt->second.pointerDepth == 0) {
                        llvm::Value* ptrVal = m_builder->CreateLoad(targetAlloca->getAllocatedType(), targetAlloca, var->name + ".ptr");
                        llvm::Type* valTy = getLlvmType(tIt->second);
                        val = coerceType(val, valTy);
                        m_builder->CreateStore(val, ptrVal);
                        return;
                    }
                }
                val = coerceType(val, targetAlloca->getAllocatedType());
                m_builder->CreateStore(val, targetAlloca);
            }
            return;
        }

        // Check module-level global variable
        llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), var->name);
        if (gVar) {
            llvm::Value* val = emitExpression(assignNode.value.get());
            if (val) {
                val = coerceType(val, gVar->getValueType());
                m_builder->CreateStore(val, gVar);
            }
            return;
        }

        // Check module-level Property Let/Set function (e.g., set_Prop)
        std::string setFnName = "set_" + var->name;
        llvm::Function* setFn = findFunctionCaseInsensitive(m_module.get(), setFnName);
        if (!setFn) {
            for (const auto& pair : m_structTypes) {
                std::string cand = pair.first + "_set_" + var->name;
                setFn = findFunctionCaseInsensitive(m_module.get(), cand);
                if (setFn) break;
            }
        }
        if (setFn && setFn->getFunctionType()->getNumParams() == 1) {
            llvm::Value* val = emitExpression(assignNode.value.get());
            if (val) {
                val = coerceType(val, setFn->getFunctionType()->getParamType(0));
                m_builder->CreateCall(setFn, {val});
            }
            return;
        }

        // Undeclared variable assignment guard
        Diagnostic::report(m_sourceFilePath, var->line > 0 ? var->line : m_currentLine,
                           var->column > 0 ? var->column : m_currentCol,
                           true, "Cannot assign to undeclared variable or identifier '" + var->name + "'.", m_sourceText);
        m_hadError = true;
        return;
    }

    // Case 2: Index assignment (base(idx) = val)
    if (auto idx = dynamic_cast<IndexExprASTNode*>(assignNode.target.get())) {
        TypeSpec baseType = deduceExprType(idx->base.get());
        if (auto var = dynamic_cast<VariableExprASTNode*>(idx->base.get())) {
            auto it = m_variableTypes.find(var->name);
            if (it != m_variableTypes.end()) baseType = it->second;
        }

        llvm::Value* baseVal = nullptr;
        if (auto var = dynamic_cast<VariableExprASTNode*>(idx->base.get())) {
            auto it = m_namedValues.find(var->name);
            if (it != m_namedValues.end()) {
                if (baseType.isArray) {
                    baseVal = it->second;
                } else {
                    baseVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, var->name);
                }
            } else {
                llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), var->name);
                if (gVar) {
                    baseVal = gVar;
                }
            }
        }
        if (!baseVal) {
            baseVal = emitExpression(idx->base.get());
        }
        llvm::Value* flatIdx = nullptr;
        if (!idx->indices.empty() && baseType.dimensions.size() > 1 && idx->indices.size() == baseType.dimensions.size()) {
            flatIdx = emitExpression(idx->indices[0].get());
            flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));
            for (size_t d = 1; d < baseType.dimensions.size(); ++d) {
                llvm::Value* dimSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), baseType.dimensions[d]);
                flatIdx = m_builder->CreateMul(flatIdx, dimSize, "matrowmul");
                llvm::Value* nextIdx = emitExpression(idx->indices[d].get());
                nextIdx = coerceType(nextIdx, llvm::Type::getInt64Ty(*m_context));
                flatIdx = m_builder->CreateAdd(flatIdx, nextIdx, "matcoladd");
            }
        } else if (idx->index) {
            flatIdx = emitExpression(idx->index.get());
        }

        ExprASTNode* keyExpr = !idx->indices.empty() ? idx->indices[0].get() : idx->index.get();
        if (keyExpr && (toLower(baseType.name) == "map" || toLower(baseType.name) == "dictionary" || isStringExpr(keyExpr))) {
            llvm::Value* mapPtr = baseVal;
            if (mapPtr->getType()->isPointerTy()) {
                // If map variable is null/unallocated, auto-create map
                llvm::Value* loadedMap = mapPtr;
                auto var = dynamic_cast<VariableExprASTNode*>(idx->base.get());
                if (var && m_namedValues.find(var->name) != m_namedValues.end()) {
                    loadedMap = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), m_namedValues[var->name], "curmap");
                    llvm::Value* isMapNull = m_builder->CreateIsNull(loadedMap, "mapisnull");
                    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
                    llvm::BasicBlock* initBB = llvm::BasicBlock::Create(*m_context, "map.init", currentFunc);
                    llvm::BasicBlock* contBB = llvm::BasicBlock::Create(*m_context, "map.cont", currentFunc);
                    m_builder->CreateCondBr(isMapNull, initBB, contBB);

                    m_builder->SetInsertPoint(initBB);
                    llvm::Function* createFn = getOrCreateMapCreate();
                    llvm::Value* newMap = m_builder->CreateCall(createFn, {}, "newmap");
                    m_builder->CreateStore(newMap, m_namedValues[var->name]);
                    m_builder->CreateBr(contBB);

                    m_builder->SetInsertPoint(contBB);
                    loadedMap = m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), m_namedValues[var->name], "ready.map");
                }
                llvm::Value* keyVal = emitExpression(keyExpr);
                keyVal = coerceType(keyVal, llvm::PointerType::get(*m_context, 0));
                llvm::Value* valVal = emitExpression(assignNode.value.get());
                valVal = coerceType(valVal, llvm::Type::getInt64Ty(*m_context));

                llvm::Function* mapSetFn = getOrCreateMapSet();
                m_builder->CreateCall(mapSetFn, {loadedMap, keyVal, valVal});
                return;
            }
        }

        llvm::Value* val = emitExpression(assignNode.value.get());

        if (baseVal && flatIdx && val) {
            if (baseType.isArray && baseType.arraySize > 0) {
                ExprASTNode* rawIdxExpr = !idx->indices.empty() ? idx->indices[0].get() : idx->index.get();
                if (auto numIdx = dynamic_cast<NumberExprASTNode*>(rawIdxExpr)) {
                    if (!numIdx->isFloat && (numIdx->val < 0 || static_cast<uint64_t>(numIdx->val) >= baseType.arraySize)) {
                        Diagnostic::report(m_sourceFilePath, idx->line > 0 ? idx->line : m_currentLine,
                                           idx->column > 0 ? idx->column : m_currentCol,
                                           true, "Array index " + std::to_string(numIdx->val) + " is out of bounds for array of size " + std::to_string(baseType.arraySize) + " [0.." + std::to_string(baseType.arraySize - 1) + "].", m_sourceText);
                        m_hadError = true;
                        return;
                    }
                }
                emitBoundsCheck(flatIdx, baseType.arraySize, "array_write");
            }

            llvm::Type* elemType = nullptr;
            if (baseType.pointerDepth > 0 || baseType.isArray) {
                elemType = getElementType(baseType);
            } else if (baseVal->getType()->isPointerTy()) {
                elemType = val->getType();
            } else {
                elemType = llvm::Type::getInt8Ty(*m_context);
            }

            val = coerceType(val, elemType);
            flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));

            llvm::Value* gep = m_builder->CreateGEP(elemType, baseVal, flatIdx, "idxgep");
            auto* storeInst = m_builder->CreateStore(val, gep);
            if (baseType.isVolatile) {
                storeInst->setVolatile(true);
            }
        }
        return;
    }

    // Case 3: Member access assignment (obj.field = val, Me.field = val, or .field = val inside With)
    if (auto member = dynamic_cast<MemberAccessExprASTNode*>(assignNode.target.get())) {
        if (member->base) {
            if (auto varBase = dynamic_cast<VariableExprASTNode*>(member->base.get())) {
                if (toLower(varBase->name) == "err") {
                    std::string prop = toLower(member->memberName);
                    llvm::Value* val = emitExpression(assignNode.value.get());
                    if (val) {
                        if (prop == "number") {
                            val = coerceType(val, llvm::Type::getInt32Ty(*m_context));
                            m_builder->CreateStore(val, getOrCreateErrNumber());
                        } else if (prop == "source") {
                            val = convertToString(val);
                            m_builder->CreateStore(val, getOrCreateErrSource());
                        } else if (prop == "description") {
                            val = convertToString(val);
                            m_builder->CreateStore(val, getOrCreateErrDescription());
                        }
                    }
                    return;
                }
            }
        }

        llvm::Value* basePtr = member->base ? getPointerToExpr(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().first : nullptr);
        llvm::Value* val = emitExpression(assignNode.value.get());
        if (basePtr && val) {
            std::string memberLower = toLower(member->memberName);
            TypeSpec baseType = member->base ? deduceExprType(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().second : TypeSpec());
            std::string explicitStructName = !baseType.name.empty() ? (!baseType.typeArgs.empty() ? toLower(instantiateGenericStruct(baseType)) : toLower(baseType.name)) : "";

            for (const auto& pair : m_structFieldIndices) {
                if (!explicitStructName.empty() && toLower(pair.first) != explicitStructName) {
                    continue;
                }
                auto fIt = pair.second.find(memberLower);
                if (fIt != pair.second.end()) {
                    unsigned fieldIdx = fIt->second;
                    std::string privKey = pair.first + "." + member->memberName;
                    if (m_privateFields.count(privKey) || m_privateFields.count(toLower(privKey))) {
                        if (toLower(m_currentScopeClass) != toLower(pair.first)) {
                            Diagnostic::report(m_sourceFilePath, member->line > 0 ? member->line : m_currentLine,
                                               member->column > 0 ? member->column : m_currentCol,
                                               true, "Cannot access private member '" + member->memberName + "' of class '" + pair.first + "'.", m_sourceText);
                            m_hadError = true;
                            return;
                        }
                    }
                    auto stIt = m_structTypes.find(pair.first);
                    if (stIt != m_structTypes.end()) {
                        if (m_unionTypes.count(pair.first)) {
                            llvm::Type* fieldType = llvm::Type::getInt8Ty(*m_context);
                            auto ftIt = m_structFieldTypes.find(pair.first);
                            if (ftIt == m_structFieldTypes.end()) {
                                ftIt = m_structFieldTypes.find(toLower(pair.first));
                            }
                            if (ftIt != m_structFieldTypes.end()) {
                                auto tIt = ftIt->second.find(memberLower);
                                if (tIt != ftIt->second.end()) {
                                    fieldType = getLlvmType(tIt->second);
                                }
                            }
                            val = coerceType(val, fieldType);

                            auto bIt = m_structBitfields.find(pair.first);
                            if (bIt != m_structBitfields.end()) {
                                auto bfIt = bIt->second.find(memberLower);
                                if (bfIt != bIt->second.end()) {
                                    const auto& binfo = bfIt->second;
                                    llvm::Value* curVal = m_builder->CreateLoad(fieldType, basePtr, "bf.cur");
                                    uint64_t mask = (binfo.bitWidth >= 64) ? ~0ULL : ((1ULL << binfo.bitWidth) - 1ULL);
                                    llvm::Value* truncVal = m_builder->CreateAnd(val, llvm::ConstantInt::get(fieldType, mask), "bf.trunc");
                                    llvm::Value* cleared = m_builder->CreateAnd(curVal, llvm::ConstantInt::get(fieldType, ~mask), "bf.clear");
                                    llvm::Value* updated = m_builder->CreateOr(cleared, truncVal, "bf.store");
                                    m_builder->CreateStore(updated, basePtr);
                                    return;
                                }
                            }

                            m_builder->CreateStore(val, basePtr);
                            return;
                        }

                        auto bIt = m_structBitfields.find(pair.first);
                        if (bIt != m_structBitfields.end()) {
                            auto bfIt = bIt->second.find(memberLower);
                            if (bfIt != bIt->second.end()) {
                                const auto& binfo = bfIt->second;
                                llvm::Type* contTy = stIt->second->getElementType(fieldIdx);
                                llvm::Value* gep = m_builder->CreateStructGEP(stIt->second, basePtr, fieldIdx, "membergep");
                                llvm::Value* curVal = m_builder->CreateLoad(contTy, gep, "bf.cur");

                                // Coerce incoming value to container type
                                llvm::Value* coercedVal = coerceType(val, contTy);
                                uint64_t mask = (binfo.bitWidth >= 64) ? ~0ULL : ((1ULL << binfo.bitWidth) - 1ULL);
                                llvm::Value* truncVal = m_builder->CreateAnd(coercedVal, llvm::ConstantInt::get(contTy, mask), "bf.trunc");
                                if (binfo.bitOffset > 0) {
                                    llvm::Value* shiftVal = llvm::ConstantInt::get(contTy, binfo.bitOffset);
                                    truncVal = m_builder->CreateShl(truncVal, shiftVal, "bf.shl");
                                }

                                uint64_t shiftedMask = mask << binfo.bitOffset;
                                llvm::Value* clearMask = llvm::ConstantInt::get(contTy, ~shiftedMask);
                                llvm::Value* cleared = m_builder->CreateAnd(curVal, clearMask, "bf.clear");
                                llvm::Value* updated = m_builder->CreateOr(cleared, truncVal, "bf.store");
                                m_builder->CreateStore(updated, gep);
                                return;
                            }
                        }

                        llvm::Type* fieldType = stIt->second->getElementType(fieldIdx);
                        val = coerceType(val, fieldType);
                        llvm::Value* gep = m_builder->CreateStructGEP(stIt->second, basePtr, fieldIdx, "membergep");
                        m_builder->CreateStore(val, gep);
                        return;
                    }
                }
            }
            // Check if Property Let/Set exists (e.g. set_Prop, Class_set_Prop)
            std::string setFuncName = "set_" + member->memberName;
            llvm::Function* setFn = m_module->getFunction(setFuncName);
            if (!setFn) {
                for (const auto& pair : m_structTypes) {
                    std::string cand = pair.first + "_set_" + member->memberName;
                    setFn = m_module->getFunction(cand);
                    if (setFn) break;
                }
            }
            if (setFn) {
                if (setFn->getFunctionType()->getNumParams() == 2) {
                    llvm::Value* coercedVal = coerceType(val, setFn->getFunctionType()->getParamType(1));
                    m_builder->CreateCall(setFn, {basePtr, coercedVal});
                    return;
                } else if (setFn->getFunctionType()->getNumParams() == 1) {
                    llvm::Value* coercedVal = coerceType(val, setFn->getFunctionType()->getParamType(0));
                    m_builder->CreateCall(setFn, {coercedVal});
                    return;
                }
            }

            Diagnostic::report(m_sourceFilePath, member->line > 0 ? member->line : m_currentLine,
                               member->column > 0 ? member->column : m_currentCol,
                               true, "Type has no member named '" + member->memberName + "'.", m_sourceText);
            m_hadError = true;
            return;
        }
        return;
    }
}

void LlvmEmitter::emitCallStatement(const CallExprASTNode& callNode) {
    emitExpression(const_cast<CallExprASTNode*>(&callNode));
}

void LlvmEmitter::emitIfStatement(const IfStmtNode& ifNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::BasicBlock* mergeBB = llvm::BasicBlock::Create(*m_context, "if.end");

    for (size_t i = 0; i < ifNode.branches.size(); ++i) {
        const auto& branch = ifNode.branches[i];
        llvm::Value* condVal = emitExpression(branch.condition.get());
        if (!condVal) continue;

        // Coerce condition to boolean (i1)
        if (condVal->getType()->isIntegerTy() && condVal->getType()->getIntegerBitWidth() != 1) {
            condVal = m_builder->CreateICmpNE(condVal, llvm::ConstantInt::get(condVal->getType(), 0), "ifcond");
        }

        llvm::BasicBlock* thenBB = llvm::BasicBlock::Create(*m_context, "if.then", currentFunc);
        llvm::BasicBlock* nextBB = nullptr;

        bool isLastBranch = (i == ifNode.branches.size() - 1);
        if (!isLastBranch || !ifNode.elseBody.empty()) {
            nextBB = llvm::BasicBlock::Create(*m_context, "if.else", currentFunc);
        } else {
            nextBB = mergeBB;
        }

        m_builder->CreateCondBr(condVal, thenBB, nextBB);

        // Emit then block
        m_builder->SetInsertPoint(thenBB);
        for (const auto& stmt : branch.body) {
            emitStatement(stmt.get());
        }
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(mergeBB);
        }

        if (nextBB != mergeBB) {
            m_builder->SetInsertPoint(nextBB);
        }
    }

    // Emit optional else block
    if (!ifNode.elseBody.empty()) {
        for (const auto& stmt : ifNode.elseBody) {
            emitStatement(stmt.get());
        }
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(mergeBB);
        }
    }

    if (mergeBB->hasNPredecessorsOrMore(1)) {
        currentFunc->insert(currentFunc->end(), mergeBB);
        m_builder->SetInsertPoint(mergeBB);
    } else {
        delete mergeBB;
    }
}

void LlvmEmitter::emitForStatement(const ForStmtNode& forNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    // Loop variable alloca
    auto it = m_namedValues.find(forNode.varName);
    llvm::AllocaInst* loopVarAlloca = nullptr;
    if (it != m_namedValues.end()) {
        loopVarAlloca = it->second;
    } else {
        llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
        loopVarAlloca = tmpBuilder.CreateAlloca(llvm::Type::getInt32Ty(*m_context), nullptr, forNode.varName);
        m_namedValues[forNode.varName] = loopVarAlloca;
    }

    llvm::Value* startVal = emitExpression(forNode.startExpr.get());
    if (startVal) {
        startVal = coerceType(startVal, loopVarAlloca->getAllocatedType());
        m_builder->CreateStore(startVal, loopVarAlloca);
    }

    llvm::BasicBlock* condBB = llvm::BasicBlock::Create(*m_context, "for.cond", currentFunc);
    llvm::BasicBlock* bodyBB = llvm::BasicBlock::Create(*m_context, "for.body", currentFunc);
    llvm::BasicBlock* incBB  = llvm::BasicBlock::Create(*m_context, "for.inc", currentFunc);
    llvm::BasicBlock* afterBB = llvm::BasicBlock::Create(*m_context, "for.after");

    m_builder->CreateBr(condBB);

    // Condition BB
    m_builder->SetInsertPoint(condBB);
    llvm::Value* curVal = m_builder->CreateLoad(loopVarAlloca->getAllocatedType(), loopVarAlloca, forNode.varName);
    llvm::Value* endVal = emitExpression(forNode.endExpr.get());
    endVal = coerceType(endVal, loopVarAlloca->getAllocatedType());

    llvm::Value* stepVal = nullptr;
    bool isNegativeStep = false;
    if (forNode.stepExpr) {
        stepVal = emitExpression(forNode.stepExpr.get());
        stepVal = coerceType(stepVal, loopVarAlloca->getAllocatedType());
        if (auto num = dynamic_cast<NumberExprASTNode*>(forNode.stepExpr.get())) {
            if (num->val < 0) isNegativeStep = true;
        } else if (auto un = dynamic_cast<UnaryExprASTNode*>(forNode.stepExpr.get())) {
            if (un->op == "-") isNegativeStep = true;
        }
    } else {
        stepVal = llvm::ConstantInt::get(loopVarAlloca->getAllocatedType(), 1);
    }

    llvm::Value* cond = isNegativeStep 
        ? m_builder->CreateICmpSGE(curVal, endVal, "for.cmp")
        : m_builder->CreateICmpSLE(curVal, endVal, "for.cmp");
    m_builder->CreateCondBr(cond, bodyBB, afterBB);

    // Body BB
    m_builder->SetInsertPoint(bodyBB);
    m_breakStack.push_back(afterBB);
    m_continueStack.push_back(incBB);

    for (const auto& stmt : forNode.body) {
        emitStatement(stmt.get());
    }

    m_breakStack.pop_back();
    m_continueStack.pop_back();

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(incBB);
    }

    // Inc BB
    m_builder->SetInsertPoint(incBB);
    llvm::Value* curValInc = m_builder->CreateLoad(loopVarAlloca->getAllocatedType(), loopVarAlloca, forNode.varName);
    llvm::Value* nextVal = m_builder->CreateAdd(curValInc, stepVal, "for.nextval");
    m_builder->CreateStore(nextVal, loopVarAlloca);
    m_builder->CreateBr(condBB);

    // After BB
    currentFunc->insert(currentFunc->end(), afterBB);
    m_builder->SetInsertPoint(afterBB);
}

void LlvmEmitter::emitForEachStatement(const ForEachStmtNode& forEachNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    // 1. Determine element variable and alloca
    auto elemIt = m_namedValues.find(forEachNode.varName);
    llvm::AllocaInst* elemAlloca = nullptr;
    llvm::Type* elemAllocType = nullptr;
    if (elemIt != m_namedValues.end()) {
        elemAlloca = elemIt->second;
        elemAllocType = elemAlloca->getAllocatedType();
    }

    // 2. Evaluate collection expression
    llvm::Value* collVal = nullptr;
    TypeSpec collType;
    if (auto varExpr = dynamic_cast<VariableExprASTNode*>(forEachNode.collectionExpr.get())) {
        auto varIt = m_namedValues.find(varExpr->name);
        if (varIt != m_namedValues.end()) {
            collType = m_variableTypes[varExpr->name];
            if (collType.isArray) {
                collVal = varIt->second;
            } else {
                collVal = m_builder->CreateLoad(varIt->second->getAllocatedType(), varIt->second, varExpr->name);
            }
        }
    }
    if (!collVal) {
        collVal = emitExpression(forEachNode.collectionExpr.get());
    }

    // 3. Determine collection count/bounds and data pointer
    llvm::Value* countVal = nullptr;
    llvm::Value* dataPtr = nullptr;
    llvm::Type* itemType = nullptr;

    if (collType.isArray && collType.arraySize > 0) {
        countVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), collType.arraySize);
        itemType = getElementType(collType);
        dataPtr = collVal;
    } else {
        // Check if collection is an object/struct with .Count and .Data
        llvm::Value* objPtr = getPointerToExpr(forEachNode.collectionExpr.get());
        if (objPtr) {
            std::string typeName = toLower(collType.name);
            for (const auto& pair : m_structFieldIndices) {
                if (toLower(pair.first) == typeName || typeName.empty()) {
                    auto cIt = pair.second.find("count");
                    auto dIt = pair.second.find("data");
                    if (cIt != pair.second.end() && dIt != pair.second.end()) {
                        auto stIt = m_structTypes.find(pair.first);
                        if (stIt != m_structTypes.end()) {
                            llvm::Value* cGep = m_builder->CreateStructGEP(stIt->second, objPtr, cIt->second, "coll.countgep");
                            llvm::Value* cLoaded = m_builder->CreateLoad(stIt->second->getElementType(cIt->second), cGep, "coll.count");
                            countVal = coerceType(cLoaded, llvm::Type::getInt64Ty(*m_context));

                            llvm::Value* dGep = m_builder->CreateStructGEP(stIt->second, objPtr, dIt->second, "coll.datagep");
                            dataPtr = m_builder->CreateLoad(stIt->second->getElementType(dIt->second), dGep, "coll.data");
                            itemType = llvm::Type::getInt32Ty(*m_context);
                            break;
                        }
                    }
                }
            }
        }
    }

    if (!countVal) {
        // Fallback default: 0 elements
        countVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
    }
    if (!itemType) {
        itemType = elemAllocType ? elemAllocType : llvm::Type::getInt32Ty(*m_context);
    }

    if (!elemAlloca) {
        llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
        elemAlloca = tmpBuilder.CreateAlloca(itemType, nullptr, forEachNode.varName);
        m_namedValues[forEachNode.varName] = elemAlloca;
    }

    // 4. Create loop index alloca
    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* idxAlloca = tmpBuilder.CreateAlloca(llvm::Type::getInt64Ty(*m_context), nullptr, "foreach.idx");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), idxAlloca);

    llvm::BasicBlock* condBB = llvm::BasicBlock::Create(*m_context, "foreach.cond", currentFunc);
    llvm::BasicBlock* bodyBB = llvm::BasicBlock::Create(*m_context, "foreach.body", currentFunc);
    llvm::BasicBlock* incBB  = llvm::BasicBlock::Create(*m_context, "foreach.inc", currentFunc);
    llvm::BasicBlock* afterBB = llvm::BasicBlock::Create(*m_context, "foreach.after");

    m_builder->CreateBr(condBB);

    // Condition BB
    m_builder->SetInsertPoint(condBB);
    llvm::Value* curIdx = m_builder->CreateLoad(llvm::Type::getInt64Ty(*m_context), idxAlloca, "cur.idx");
    llvm::Value* loopCond = m_builder->CreateICmpSLT(curIdx, countVal, "foreach.cmp");
    m_builder->CreateCondBr(loopCond, bodyBB, afterBB);

    // Body BB
    m_builder->SetInsertPoint(bodyBB);
    if (dataPtr) {
        llvm::Value* itemGep = m_builder->CreateGEP(itemType, dataPtr, curIdx, "item.gep");
        llvm::Value* loadedItem = m_builder->CreateLoad(itemType, itemGep, "loaded.item");
        loadedItem = coerceType(loadedItem, elemAlloca->getAllocatedType());
        m_builder->CreateStore(loadedItem, elemAlloca);
    }

    m_breakStack.push_back(afterBB);
    m_continueStack.push_back(incBB);

    for (const auto& stmt : forEachNode.body) {
        emitStatement(stmt.get());
    }

    m_breakStack.pop_back();
    m_continueStack.pop_back();

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(incBB);
    }

    // Inc BB
    m_builder->SetInsertPoint(incBB);
    llvm::Value* nextIdx = m_builder->CreateAdd(curIdx, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1), "next.idx");
    m_builder->CreateStore(nextIdx, idxAlloca);
    m_builder->CreateBr(condBB);

    // After BB
    currentFunc->insert(currentFunc->end(), afterBB);
    m_builder->SetInsertPoint(afterBB);
}

void LlvmEmitter::emitDoLoopStatement(const DoLoopStmtNode& doNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    llvm::BasicBlock* bodyBB = llvm::BasicBlock::Create(*m_context, "do.body", currentFunc);
    llvm::BasicBlock* afterBB = llvm::BasicBlock::Create(*m_context, "do.after");

    m_breakStack.push_back(afterBB);
    m_continueStack.push_back(bodyBB);

    if (doNode.loopType == DoLoopStmtNode::LoopType::PreWhile || 
        doNode.loopType == DoLoopStmtNode::LoopType::PreUntil) {
        
        llvm::BasicBlock* condBB = llvm::BasicBlock::Create(*m_context, "do.cond", currentFunc);
        m_builder->CreateBr(condBB);

        m_builder->SetInsertPoint(condBB);
        llvm::Value* condVal = emitExpression(doNode.condition.get());
        if (!condVal) {
            condVal = llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
        } else if (condVal->getType()->isIntegerTy() && condVal->getType()->getIntegerBitWidth() != 1) {
            condVal = m_builder->CreateICmpNE(condVal, llvm::ConstantInt::get(condVal->getType(), 0), "docond");
        }
        if (doNode.loopType == DoLoopStmtNode::LoopType::PreUntil) {
            condVal = m_builder->CreateNot(condVal, "dountil");
        }
        m_builder->CreateCondBr(condVal, bodyBB, afterBB);

        m_builder->SetInsertPoint(bodyBB);
        for (const auto& stmt : doNode.body) {
            emitStatement(stmt.get());
        }
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(condBB);
        }
    } else {
        // Post-tested or infinite
        m_builder->CreateBr(bodyBB);
        m_builder->SetInsertPoint(bodyBB);

        for (const auto& stmt : doNode.body) {
            emitStatement(stmt.get());
        }

        if (!m_builder->GetInsertBlock()->getTerminator()) {
            if (doNode.loopType == DoLoopStmtNode::LoopType::PostWhile ||
                doNode.loopType == DoLoopStmtNode::LoopType::PostUntil) {
                llvm::Value* condVal = emitExpression(doNode.condition.get());
                if (!condVal) {
                    condVal = llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
                } else if (condVal->getType()->isIntegerTy() && condVal->getType()->getIntegerBitWidth() != 1) {
                    condVal = m_builder->CreateICmpNE(condVal, llvm::ConstantInt::get(condVal->getType(), 0), "docond");
                }
                if (doNode.loopType == DoLoopStmtNode::LoopType::PostUntil) {
                    condVal = m_builder->CreateNot(condVal, "dountil");
                }
                m_builder->CreateCondBr(condVal, bodyBB, afterBB);
            } else {
                m_builder->CreateBr(bodyBB); // Infinite loop
            }
        }
    }

    m_breakStack.pop_back();
    m_continueStack.pop_back();

    currentFunc->insert(currentFunc->end(), afterBB);
    m_builder->SetInsertPoint(afterBB);
}

void LlvmEmitter::emitWhileStatement(const WhileStmtNode& whileNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    llvm::BasicBlock* condBB = llvm::BasicBlock::Create(*m_context, "while.cond", currentFunc);
    llvm::BasicBlock* bodyBB = llvm::BasicBlock::Create(*m_context, "while.body", currentFunc);
    llvm::BasicBlock* afterBB = llvm::BasicBlock::Create(*m_context, "while.after");

    m_builder->CreateBr(condBB);

    m_builder->SetInsertPoint(condBB);
    llvm::Value* condVal = emitExpression(whileNode.condition.get());
    if (!condVal) {
        condVal = llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
    } else if (condVal->getType()->isIntegerTy() && condVal->getType()->getIntegerBitWidth() != 1) {
        condVal = m_builder->CreateICmpNE(condVal, llvm::ConstantInt::get(condVal->getType(), 0), "whilecond");
    }
    m_builder->CreateCondBr(condVal, bodyBB, afterBB);

    m_builder->SetInsertPoint(bodyBB);
    m_breakStack.push_back(afterBB);
    m_continueStack.push_back(condBB);

    for (const auto& stmt : whileNode.body) {
        emitStatement(stmt.get());
    }

    m_breakStack.pop_back();
    m_continueStack.pop_back();

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(condBB);
    }

    currentFunc->insert(currentFunc->end(), afterBB);
    m_builder->SetInsertPoint(afterBB);
}

void LlvmEmitter::emitExitStatement(const ExitStmtNode& exitNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    if (exitNode.kind == ExitStmtNode::ExitKind::Sub || exitNode.kind == ExitStmtNode::ExitKind::Function) {
        if (m_exitBlock) {
            m_builder->CreateBr(m_exitBlock);
            llvm::BasicBlock* deadBB = llvm::BasicBlock::Create(*m_context, "dead.exit", currentFunc);
            m_builder->SetInsertPoint(deadBB);
        }
        return;
    }

    if (!m_breakStack.empty()) {
        m_builder->CreateBr(m_breakStack.back());
        llvm::BasicBlock* deadBB = llvm::BasicBlock::Create(*m_context, "dead.loop", currentFunc);
        m_builder->SetInsertPoint(deadBB);
    }
}

void LlvmEmitter::emitSelectStatement(const SelectStmtNode& selectNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Value* selectVal = emitExpression(selectNode.expr.get());
    if (!selectVal) return;

    llvm::BasicBlock* mergeBB = llvm::BasicBlock::Create(*m_context, "select.end");

    for (size_t i = 0; i < selectNode.branches.size(); ++i) {
        const auto& branch = selectNode.branches[i];
        if (branch.isElse) {
            for (const auto& stmt : branch.body) {
                emitStatement(stmt.get());
            }
            if (!m_builder->GetInsertBlock()->getTerminator()) {
                m_builder->CreateBr(mergeBB);
            }
            break;
        }

        llvm::Value* caseCond = nullptr;
        for (const auto& valExpr : branch.values) {
            llvm::Value* testVal = emitExpression(valExpr.get());
            if (testVal) {
                testVal = coerceType(testVal, selectVal->getType());
                llvm::Value* eq = m_builder->CreateICmpEQ(selectVal, testVal, "case.cmp");
                if (!caseCond) {
                    caseCond = eq;
                } else {
                    caseCond = m_builder->CreateOr(caseCond, eq, "case.or");
                }
            }
        }

        if (!caseCond) continue;

        llvm::BasicBlock* caseBB = llvm::BasicBlock::Create(*m_context, "case.body", currentFunc);
        llvm::BasicBlock* nextCaseBB = llvm::BasicBlock::Create(*m_context, "case.next", currentFunc);

        m_builder->CreateCondBr(caseCond, caseBB, nextCaseBB);

        m_builder->SetInsertPoint(caseBB);
        for (const auto& stmt : branch.body) {
            emitStatement(stmt.get());
        }
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(mergeBB);
        }

        m_builder->SetInsertPoint(nextCaseBB);
    }

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(mergeBB);
    }

    if (mergeBB->hasNPredecessorsOrMore(1)) {
        currentFunc->insert(currentFunc->end(), mergeBB);
        m_builder->SetInsertPoint(mergeBB);
    } else {
        delete mergeBB;
    }
}

void LlvmEmitter::emitMatchStatement(const MatchStmtNode& matchNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    llvm::Value* matchVal = emitExpression(matchNode.expr.get());
    if (!matchVal) return;

    // Allocate storage for matchVal so pattern conditions can load/inspect it safely
    llvm::Type* valTy = matchVal->getType();
    llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* subjectAlloca = tmpBuilder.CreateAlloca(valTy, nullptr, "match.subj");
    m_builder->CreateStore(matchVal, subjectAlloca);

    TypeSpec subjType = deduceExprType(matchNode.expr.get());

    llvm::BasicBlock* mergeBB = llvm::BasicBlock::Create(*m_context, "match.end");

    for (size_t i = 0; i < matchNode.branches.size(); ++i) {
        const auto& branch = matchNode.branches[i];

        llvm::BasicBlock* caseBB = llvm::BasicBlock::Create(*m_context, "match.case", currentFunc);
        llvm::BasicBlock* nextCaseBB = llvm::BasicBlock::Create(*m_context, "match.next", currentFunc);

        if (branch.isElse) {
            m_builder->CreateBr(caseBB);
            m_builder->SetInsertPoint(caseBB);
            for (const auto& stmt : branch.body) {
                emitStatement(stmt.get());
            }
            if (!m_builder->GetInsertBlock()->getTerminator()) {
                m_builder->CreateBr(mergeBB);
            }
            m_builder->SetInsertPoint(nextCaseBB);
            break;
        }

        llvm::Value* branchCond = nullptr;
        std::string boundVarName = "";
        llvm::Value* boundVarVal = nullptr;

        for (const auto& pat : branch.patterns) {
            llvm::Value* patCond = nullptr;

            if (pat.kind == MatchPattern::Kind::Wildcard) {
                patCond = llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
            } else if (pat.kind == MatchPattern::Kind::OkPattern) {
                // If subject is Result: is_ok == 1, boundVar = value
                llvm::Value* curSubj = m_builder->CreateLoad(valTy, subjectAlloca, "subj.val");
                llvm::Value* isOk = nullptr;
                if (curSubj->getType()->isStructTy()) {
                    isOk = m_builder->CreateExtractValue(curSubj, 0, "res.isok");
                    if (!pat.boundVar.empty()) {
                        boundVarName = pat.boundVar;
                        boundVarVal = m_builder->CreateExtractValue(curSubj, 2, "res.okval");
                    }
                } else if (curSubj->getType()->isPointerTy()) {
                    llvm::Value* okGep = m_builder->CreateStructGEP(getLlvmType(TypeSpec{"Result"}), curSubj, 0, "res.okgep");
                    isOk = m_builder->CreateLoad(llvm::Type::getInt1Ty(*m_context), okGep, "res.isok");
                    if (!pat.boundVar.empty()) {
                        boundVarName = pat.boundVar;
                        llvm::Value* valGep = m_builder->CreateStructGEP(getLlvmType(TypeSpec{"Result"}), curSubj, 2, "res.valgep");
                        boundVarVal = m_builder->CreateLoad(llvm::Type::getInt64Ty(*m_context), valGep, "res.okval");
                    }
                }
                if (isOk) {
                    patCond = m_builder->CreateICmpEQ(isOk, llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1), "is.ok.match");
                }
            } else if (pat.kind == MatchPattern::Kind::ErrPattern) {
                llvm::Value* curSubj = m_builder->CreateLoad(valTy, subjectAlloca, "subj.val");
                llvm::Value* isOk = nullptr;
                if (curSubj->getType()->isStructTy()) {
                    isOk = m_builder->CreateExtractValue(curSubj, 0, "res.isok");
                    if (!pat.boundVar.empty()) {
                        boundVarName = pat.boundVar;
                        boundVarVal = m_builder->CreateExtractValue(curSubj, 1, "res.errval");
                    }
                } else if (curSubj->getType()->isPointerTy()) {
                    llvm::Value* okGep = m_builder->CreateStructGEP(getLlvmType(TypeSpec{"Result"}), curSubj, 0, "res.okgep");
                    isOk = m_builder->CreateLoad(llvm::Type::getInt1Ty(*m_context), okGep, "res.isok");
                    if (!pat.boundVar.empty()) {
                        boundVarName = pat.boundVar;
                        llvm::Value* errGep = m_builder->CreateStructGEP(getLlvmType(TypeSpec{"Result"}), curSubj, 1, "res.errgep");
                        boundVarVal = m_builder->CreateLoad(llvm::Type::getInt32Ty(*m_context), errGep, "res.errval");
                    }
                }
                if (isOk) {
                    patCond = m_builder->CreateICmpEQ(isOk, llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0), "is.err.match");
                }
            } else if (pat.kind == MatchPattern::Kind::Range) {
                llvm::Value* curSubj = m_builder->CreateLoad(valTy, subjectAlloca, "subj.val");
                llvm::Value* minVal = emitExpression(pat.expr.get());
                llvm::Value* maxVal = emitExpression(pat.rangeEnd.get());
                if (minVal && maxVal) {
                    minVal = coerceType(minVal, curSubj->getType());
                    maxVal = coerceType(maxVal, curSubj->getType());
                    llvm::Value* ge = m_builder->CreateICmpSGE(curSubj, minVal, "range.ge");
                    llvm::Value* le = m_builder->CreateICmpSLE(curSubj, maxVal, "range.le");
                    patCond = m_builder->CreateAnd(ge, le, "range.match");
                }
            } else if (pat.kind == MatchPattern::Kind::Value) {
                llvm::Value* curSubj = m_builder->CreateLoad(valTy, subjectAlloca, "subj.val");
                llvm::Value* testVal = emitExpression(pat.expr.get());
                if (testVal) {
                    if (isStringExpr(pat.expr.get()) || (curSubj->getType()->isPointerTy() && testVal->getType()->isPointerTy())) {
                        llvm::Function* strcmpFn = getOrCreateStrcmp();
                        llvm::Value* diff = m_builder->CreateCall(strcmpFn, {curSubj, testVal}, "strdiff");
                        patCond = m_builder->CreateICmpEQ(diff, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "strmatch");
                    } else {
                        testVal = coerceType(testVal, curSubj->getType());
                        patCond = m_builder->CreateICmpEQ(curSubj, testVal, "case.cmp");
                    }
                }
            }

            if (patCond) {
                if (!branchCond) {
                    branchCond = patCond;
                } else {
                    branchCond = m_builder->CreateOr(branchCond, patCond, "branch.or");
                }
            }
        }

        if (!branchCond) {
            branchCond = llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0);
        }

        m_builder->CreateCondBr(branchCond, caseBB, nextCaseBB);

        m_builder->SetInsertPoint(caseBB);

        bool boundAllocated = false;
        if (!boundVarName.empty() && boundVarVal) {
            llvm::AllocaInst* bAlloca = tmpBuilder.CreateAlloca(boundVarVal->getType(), nullptr, boundVarName);
            m_builder->CreateStore(boundVarVal, bAlloca);
            m_namedValues[boundVarName] = bAlloca;
            TypeSpec bSpec;
            bSpec.name = (boundVarVal->getType()->isIntegerTy(32)) ? "Int32" : "Int64";
            m_variableTypes[boundVarName] = bSpec;
            boundAllocated = true;
        }

        for (const auto& stmt : branch.body) {
            emitStatement(stmt.get());
        }

        if (boundAllocated) {
            m_namedValues.erase(boundVarName);
            m_variableTypes.erase(boundVarName);
        }

        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(mergeBB);
        }

        m_builder->SetInsertPoint(nextCaseBB);
    }

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(mergeBB);
    }

    if (mergeBB->hasNPredecessorsOrMore(1)) {
        currentFunc->insert(currentFunc->end(), mergeBB);
        m_builder->SetInsertPoint(mergeBB);
    } else {
        delete mergeBB;
    }
}

void LlvmEmitter::emitAsmStatement(const AsmStmtNode& asmNode) {
    if (!m_currentProcIsUnsafe) {
        Diagnostic::report(m_sourceFilePath, asmNode.line > 0 ? asmNode.line : m_currentLine,
                           asmNode.column > 0 ? asmNode.column : m_currentCol,
                           true, "Use of 'Asm' requires procedure to be marked 'Unsafe'.", m_sourceText);
        m_hadError = true;
        return;
    }

    std::vector<llvm::Type*> paramTypes;
    std::vector<llvm::Value*> args;

    for (const auto& op : asmNode.inputOperands) {
        llvm::Value* val = emitExpression(op.get());
        if (val) {
            paramTypes.push_back(val->getType());
            args.push_back(val);
        }
    }

    // Convert GCC inline assembly operand placeholders (%0, %1, etc.) to LLVM format ($0, $1, etc.)
    std::string llvmAsmCode;
    const std::string& rawAsm = asmNode.assemblyCode;
    for (size_t i = 0; i < rawAsm.size(); ++i) {
        if (rawAsm[i] == '%' && i + 1 < rawAsm.size() && std::isdigit(static_cast<unsigned char>(rawAsm[i + 1]))) {
            llvmAsmCode += '$';
        } else {
            llvmAsmCode += rawAsm[i];
        }
    }

    llvm::FunctionType* asmTy = llvm::FunctionType::get(llvm::Type::getVoidTy(*m_context), paramTypes, false);
    llvm::InlineAsm* inlineAsm = llvm::InlineAsm::get(asmTy, llvmAsmCode, asmNode.constraints, true);
    m_builder->CreateCall(inlineAsm, args);
}

void LlvmEmitter::emitStatement(ASTNode* stmt) {
    if (!stmt) return;

    if (stmt->line > 0) {
        m_currentLine = stmt->line;
        m_currentCol = stmt->column > 0 ? stmt->column : 1;
        emitDebugLocation(stmt->line, stmt->column > 0 ? stmt->column : 1);
    }

    if (auto dimStmt = dynamic_cast<DimStmtNode*>(stmt)) {
        emitDimStatement(*dimStmt);
    } else if (auto constStmt = dynamic_cast<ConstStmtNode*>(stmt)) {
        emitConstStatement(*constStmt);
    } else if (auto assignStmt = dynamic_cast<AssignStmtNode*>(stmt)) {
        emitAssignStatement(*assignStmt);
    } else if (auto callStmt = dynamic_cast<CallStmtNode*>(stmt)) {
        emitCallStatement(*callStmt->call);
    } else if (auto callExpr = dynamic_cast<CallExprASTNode*>(stmt)) {
        emitCallStatement(*callExpr);
    } else if (auto ifStmt = dynamic_cast<IfStmtNode*>(stmt)) {
        emitIfStatement(*ifStmt);
    } else if (auto forStmt = dynamic_cast<ForStmtNode*>(stmt)) {
        emitForStatement(*forStmt);
    } else if (auto forEachStmt = dynamic_cast<ForEachStmtNode*>(stmt)) {
        emitForEachStatement(*forEachStmt);
    } else if (auto doStmt = dynamic_cast<DoLoopStmtNode*>(stmt)) {
        emitDoLoopStatement(*doStmt);
    } else if (auto whileStmt = dynamic_cast<WhileStmtNode*>(stmt)) {
        emitWhileStatement(*whileStmt);
    } else if (auto selectStmt = dynamic_cast<SelectStmtNode*>(stmt)) {
        emitSelectStatement(*selectStmt);
    } else if (auto matchStmt = dynamic_cast<MatchStmtNode*>(stmt)) {
        emitMatchStatement(*matchStmt);
    } else if (auto exitStmt = dynamic_cast<ExitStmtNode*>(stmt)) {
        emitExitStatement(*exitStmt);
    } else if (auto asmStmt = dynamic_cast<AsmStmtNode*>(stmt)) {
        emitAsmStatement(*asmStmt);
    } else if (auto withStmt = dynamic_cast<WithStmtNode*>(stmt)) {
        emitWithStatement(*withStmt);
    } else if (auto printStmt = dynamic_cast<PrintStmtNode*>(stmt)) {
        emitPrintStatement(*printStmt);
    } else if (auto printFileStmt = dynamic_cast<PrintFileStmtNode*>(stmt)) {
        emitPrintFileStatement(*printFileStmt);
    } else if (auto openStmt = dynamic_cast<OpenStmtNode*>(stmt)) {
        emitOpenStatement(*openStmt);
    } else if (auto closeStmt = dynamic_cast<CloseStmtNode*>(stmt)) {
        emitCloseStatement(*closeStmt);
    } else if (auto lineInputStmt = dynamic_cast<LineInputStmtNode*>(stmt)) {
        emitLineInputStatement(*lineInputStmt);
    } else if (auto inputFileStmt = dynamic_cast<InputFileStmtNode*>(stmt)) {
        emitInputFileStatement(*inputFileStmt);
    } else if (auto inputStmt = dynamic_cast<InputStmtNode*>(stmt)) {
        emitInputStatement(*inputStmt);
    } else if (auto delStmt = dynamic_cast<DeleteStmtNode*>(stmt)) {
        emitDeleteStatement(*delStmt);
    } else if (auto redimStmt = dynamic_cast<ReDimStmtNode*>(stmt)) {
        emitReDimStatement(*redimStmt);
    } else if (auto eraseStmt = dynamic_cast<EraseStmtNode*>(stmt)) {
        emitEraseStatement(*eraseStmt);
    } else if (auto labelStmt = dynamic_cast<LabelStmtNode*>(stmt)) {
        emitLabelStatement(*labelStmt);
    } else if (auto gotoStmt = dynamic_cast<GoToStmtNode*>(stmt)) {
        emitGoToStatement(*gotoStmt);
    } else if (auto tryStmt = dynamic_cast<TryStmtNode*>(stmt)) {
        emitTryStatement(*tryStmt);
    } else if (auto usingStmt = dynamic_cast<UsingStmtNode*>(stmt)) {
        emitUsingStatement(*usingStmt);
    } else if (auto assertStmt = dynamic_cast<StaticAssertStmtNode*>(stmt)) {
        emitStaticAssert(*assertStmt);
    }
}

void LlvmEmitter::emitStaticAssert(const StaticAssertStmtNode& assertNode) {
    if (!assertNode.condition) return;
    llvm::Value* condVal = emitExpression(assertNode.condition.get());
    if (!condVal) {
        Diagnostic::report(m_sourceFilePath, assertNode.line > 0 ? assertNode.line : 1,
                           assertNode.column > 0 ? assertNode.column : 1, true,
                           "Failed to evaluate expression in #Assert.", m_sourceText);
        m_hadError = true;
        return;
    }

    if (auto cInt = llvm::dyn_cast<llvm::ConstantInt>(condVal)) {
        if (cInt->isZero()) {
            std::string msg = assertNode.message.empty() 
                ? "Static assertion failed." 
                : ("Static assertion failed: " + assertNode.message);
            Diagnostic::report(m_sourceFilePath, assertNode.line > 0 ? assertNode.line : 1,
                               assertNode.column > 0 ? assertNode.column : 1, true,
                               msg, m_sourceText);
            m_hadError = true;
        }
    } else {
        Diagnostic::report(m_sourceFilePath, assertNode.line > 0 ? assertNode.line : 1,
                           assertNode.column > 0 ? assertNode.column : 1, true,
                           "Condition in #Assert must be a compile-time constant expression.", m_sourceText);
        m_hadError = true;
    }
}

void LlvmEmitter::emitLabelStatement(const LabelStmtNode& labelNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    std::string lowerName = toLower(labelNode.labelName);
    m_definedLabels.insert(lowerName);

    llvm::BasicBlock* labelBB = nullptr;
    auto it = m_labels.find(lowerName);
    if (it != m_labels.end()) {
        labelBB = it->second;
    } else {
        labelBB = llvm::BasicBlock::Create(*m_context, "lbl." + lowerName, currentFunc);
        m_labels[lowerName] = labelBB;
    }

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(labelBB);
    }

    m_builder->SetInsertPoint(labelBB);
}

void LlvmEmitter::emitGoToStatement(const GoToStmtNode& gotoNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
    std::string lowerName = toLower(gotoNode.labelName);
    m_referencedLabels.push_back({gotoNode.labelName, gotoNode.line, gotoNode.column});

    llvm::BasicBlock* targetBB = nullptr;
    auto it = m_labels.find(lowerName);
    if (it != m_labels.end()) {
        targetBB = it->second;
    } else {
        targetBB = llvm::BasicBlock::Create(*m_context, "lbl." + lowerName, currentFunc);
        m_labels[lowerName] = targetBB;
    }

    m_builder->CreateBr(targetBB);

    // Create an unreachable continuation block for subsequent instructions until next label/statement
    llvm::BasicBlock* deadBB = llvm::BasicBlock::Create(*m_context, "goto.cont", currentFunc);
    m_builder->SetInsertPoint(deadBB);
}

void LlvmEmitter::emitTryStatement(const TryStmtNode& tryNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    // Allocate an error flag: 0 = no error, >0 = error code
    llvm::IRBuilder<> entryBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
    llvm::AllocaInst* errCodeAlloca = entryBuilder.CreateAlloca(llvm::Type::getInt32Ty(*m_context), nullptr, "err.code");
    m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), errCodeAlloca);

    bool hasCatch = !tryNode.catchBody.empty() || !tryNode.catchVarName.empty();
    llvm::BasicBlock* catchBB = hasCatch ? llvm::BasicBlock::Create(*m_context, "try.catch", currentFunc) : nullptr;
    llvm::BasicBlock* finallyBB = !tryNode.finallyBody.empty() ? llvm::BasicBlock::Create(*m_context, "try.finally", currentFunc) : nullptr;
    llvm::BasicBlock* contBB = llvm::BasicBlock::Create(*m_context, "try.cont");

    llvm::BasicBlock* postTryTarget = finallyBB ? finallyBB : contBB;
    llvm::BasicBlock* postCatchTarget = finallyBB ? finallyBB : contBB;

    if (catchBB) {
        m_catchStack.push_back(catchBB);
        m_tryErrAllocaStack.push_back(errCodeAlloca);
    }

    // 1. Emit Try Body
    for (const auto& stmt : tryNode.tryBody) {
        emitStatement(stmt.get());
    }

    if (catchBB) {
        m_catchStack.pop_back();
        m_tryErrAllocaStack.pop_back();
    }

    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(postTryTarget);
    }

    // 2. Emit Catch Block (if present)
    if (catchBB) {
        m_builder->SetInsertPoint(catchBB);
        llvm::Value* curErr = m_builder->CreateLoad(llvm::Type::getInt32Ty(*m_context), getOrCreateErrNumber(), "err.val");
        llvm::Value* isErrZero = m_builder->CreateICmpEQ(curErr, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
        llvm::Value* localErr = m_builder->CreateLoad(llvm::Type::getInt32Ty(*m_context), errCodeAlloca, "local.err");
        curErr = m_builder->CreateSelect(isErrZero, localErr, curErr, "final.err");
        m_builder->CreateStore(curErr, getOrCreateErrNumber());

        if (!tryNode.catchVarName.empty()) {
            // Allocate or store into catch variable
            auto it = m_namedValues.find(tryNode.catchVarName);
            if (it == m_namedValues.end()) {
                it = m_namedValues.find(toLower(tryNode.catchVarName));
            }
            llvm::AllocaInst* catchVarAlloca = nullptr;
            if (it != m_namedValues.end()) {
                catchVarAlloca = it->second;
            } else {
                llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
                catchVarAlloca = tmpBuilder.CreateAlloca(llvm::Type::getInt32Ty(*m_context), nullptr, tryNode.catchVarName);
                m_namedValues[tryNode.catchVarName] = catchVarAlloca;
                m_namedValues[toLower(tryNode.catchVarName)] = catchVarAlloca;
                TypeSpec intType;
                intType.name = "Int32";
                m_variableTypes[tryNode.catchVarName] = intType;
                m_variableTypes[toLower(tryNode.catchVarName)] = intType;
            }
            m_builder->CreateStore(curErr, catchVarAlloca);
        }

        for (const auto& stmt : tryNode.catchBody) {
            emitStatement(stmt.get());
        }

        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(postCatchTarget);
        }
    }

    // 3. Emit Finally Block (if present)
    if (finallyBB) {
        m_builder->SetInsertPoint(finallyBB);
        for (const auto& stmt : tryNode.finallyBody) {
            emitStatement(stmt.get());
        }
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            m_builder->CreateBr(contBB);
        }
    }

    // 4. Continue Block
    if (contBB->hasNPredecessorsOrMore(1)) {
        currentFunc->insert(currentFunc->end(), contBB);
        m_builder->SetInsertPoint(contBB);
    } else {
        delete contBB;
    }
}

void LlvmEmitter::emitUsingStatement(const UsingStmtNode& usingNode) {
    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();

    // 1. Initialize scoped resource variable if provided
    llvm::AllocaInst* resAlloca = nullptr;
    TypeSpec resType = usingNode.type;
    bool isNewVar = false;

    if (!usingNode.varName.empty()) {
        llvm::Value* initVal = nullptr;
        if (usingNode.initExpr) {
            initVal = emitExpression(usingNode.initExpr.get());
            if (resType.name.empty()) {
                resType = deduceExprType(usingNode.initExpr.get());
            }
        }

        auto it = m_namedValues.find(usingNode.varName);
        if (it != m_namedValues.end()) {
            resAlloca = it->second;
            resType = m_variableTypes[usingNode.varName];
        } else {
            llvm::IRBuilder<> tmpBuilder(&currentFunc->getEntryBlock(), currentFunc->getEntryBlock().begin());
            llvm::Type* llvmType = getLlvmType(resType);
            resAlloca = tmpBuilder.CreateAlloca(llvmType, nullptr, usingNode.varName);
            m_namedValues[usingNode.varName] = resAlloca;
            m_variableTypes[usingNode.varName] = resType;
            isNewVar = true;
        }

        if (initVal) {
            llvm::Type* expectedTy = resAlloca->getAllocatedType();
            initVal = coerceType(initVal, expectedTy);
            m_builder->CreateStore(initVal, resAlloca);
        }
    } else if (usingNode.initExpr) {
        emitExpression(usingNode.initExpr.get());
    }

    // 2. Execute body statements
    for (const auto& stmt : usingNode.body) {
        emitStatement(stmt.get());
    }

    // 3. Emit Deterministic Cleanup / Dispose
    if (!usingNode.varName.empty() && resAlloca) {
        if (!m_builder->GetInsertBlock()->getTerminator()) {
            llvm::Value* resVal = m_builder->CreateLoad(resAlloca->getAllocatedType(), resAlloca, usingNode.varName + ".res");

            // Look for matching Dispose function: TypeName_Dispose or Dispose(res) or res.Dispose()
            std::string typeDispose = resType.name + "_Dispose";
            llvm::Function* dispFn = findFunctionCaseInsensitive(m_module.get(), typeDispose);
            if (!dispFn) {
                dispFn = findFunctionCaseInsensitive(m_module.get(), "Dispose");
            }
            if (dispFn) {
                std::vector<llvm::Value*> dArgs;
                if (dispFn->getFunctionType()->getNumParams() > 0) {
                    llvm::Type* p0Ty = dispFn->getFunctionType()->getParamType(0);
                    llvm::Value* argVal = resVal;
                    if (p0Ty->isPointerTy() && !argVal->getType()->isPointerTy()) {
                        argVal = resAlloca;
                    } else {
                        argVal = coerceType(argVal, p0Ty);
                    }
                    dArgs.push_back(argVal);
                }
                m_builder->CreateCall(dispFn, dArgs);
            } else {
                for (const auto& pair : m_structTypes) {
                    std::string cand = pair.first + "_Dispose";
                    dispFn = findFunctionCaseInsensitive(m_module.get(), cand);
                    if (dispFn) {
                        llvm::Value* argVal = resAlloca;
                        if (dispFn->getFunctionType()->getNumParams() > 0) {
                            argVal = coerceType(argVal, dispFn->getFunctionType()->getParamType(0));
                        }
                        m_builder->CreateCall(dispFn, {argVal});
                        break;
                    }
                }
            }
        }
    }

    if (isNewVar) {
        m_namedValues.erase(usingNode.varName);
        m_variableTypes.erase(usingNode.varName);
    }
}

void LlvmEmitter::emitEraseStatement(const EraseStmtNode& eraseNode) {
    std::string name = eraseNode.varName;
    if (name.empty() && eraseNode.targetExpr) {
        if (auto var = dynamic_cast<VariableExprASTNode*>(eraseNode.targetExpr.get())) {
            name = var->name;
        }
    }
    if (name.empty()) return;

    auto vIt = m_namedValues.find(name);
    if (vIt == m_namedValues.end()) return;
    auto tIt = m_variableTypes.find(name);
    if (tIt == m_variableTypes.end()) return;

    TypeSpec& varType = tIt->second;
    llvm::AllocaInst* alloca = vIt->second;

    if (varType.isArray) {
        // Fixed stack-allocated array: zero-initialize all elements
        llvm::Type* arrTy = alloca->getAllocatedType();
        m_builder->CreateStore(llvm::ConstantAggregateZero::get(arrTy), alloca);
    } else if (varType.pointerDepth > 0) {
        // Dynamic array or object pointer: set to null
        m_builder->CreateStore(
            llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)),
            alloca
        );
        varType.arraySize = 0;
    }
}

void LlvmEmitter::emitDeleteStatement(const DeleteStmtNode& delNode) {
    if (!delNode.target) return;
    llvm::Value* objPtr = emitExpression(delNode.target.get());
    if (!objPtr) return;

    // Call destructor if available (e.g. ClassName_Class_Terminate)
    // Then clear/null out pointer if target is a variable
    if (auto var = dynamic_cast<VariableExprASTNode*>(delNode.target.get())) {
        auto tIt = m_variableTypes.find(var->name);
        if (tIt != m_variableTypes.end()) {
            std::string termName = tIt->second.name + "_Class_Terminate";
            llvm::Function* termFn = findFunctionCaseInsensitive(m_module.get(), termName);
            if (termFn && termFn->getFunctionType()->getNumParams() == 1) {
                m_builder->CreateCall(termFn, {objPtr});
            }
        }
        auto vIt = m_namedValues.find(var->name);
        if (vIt != m_namedValues.end()) {
            m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), vIt->second);
        }
    }
}

void LlvmEmitter::emitReDimStatement(const ReDimStmtNode& redimNode) {
    if (redimNode.dimensions.empty()) return;
    auto vIt = m_namedValues.find(redimNode.varName);
    if (vIt == m_namedValues.end()) return;

    auto tIt = m_variableTypes.find(redimNode.varName);
    if (tIt == m_variableTypes.end()) return;
    TypeSpec& varType = tIt->second;

    llvm::Type* elemType = getElementType(varType);
    const llvm::DataLayout& dl = m_module->getDataLayout();
    uint64_t elemSize = dl.getTypeAllocSize(elemType);
    if (elemSize == 0) elemSize = 1;

    // Calculate new total element count
    llvm::Value* totalCount = emitExpression(redimNode.dimensions[0].get());
    totalCount = coerceType(totalCount, llvm::Type::getInt64Ty(*m_context));
    for (size_t i = 1; i < redimNode.dimensions.size(); ++i) {
        llvm::Value* dVal = emitExpression(redimNode.dimensions[i].get());
        dVal = coerceType(dVal, llvm::Type::getInt64Ty(*m_context));
        totalCount = m_builder->CreateMul(totalCount, dVal, "dimmul");
    }

    // New byte size = totalCount * elemSize
    llvm::Value* newByteSize = m_builder->CreateMul(
        totalCount,
        llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), elemSize),
        "newbytesize"
    );

    llvm::Function* mallocFn = getOrCreateMalloc();
    llvm::Value* newBuf = m_builder->CreateCall(mallocFn, {newByteSize}, "redim.newbuf");

    // If preserve and previous pointer is non-null, copy existing elements
    llvm::Value* oldBuf = m_builder->CreateLoad(vIt->second->getAllocatedType(), vIt->second, "redim.oldbuf");
    if (redimNode.isPreserve) {
        llvm::Value* isOldNotNull = m_builder->CreateICmpNE(
            oldBuf,
            llvm::Constant::getNullValue(oldBuf->getType()),
            "isoldnotnull"
        );

        llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
        llvm::BasicBlock* copyBB = llvm::BasicBlock::Create(*m_context, "redim.copy", currentFunc);
        llvm::BasicBlock* contBB = llvm::BasicBlock::Create(*m_context, "redim.cont", currentFunc);
        m_builder->CreateCondBr(isOldNotNull, copyBB, contBB);

        m_builder->SetInsertPoint(copyBB);
        uint64_t oldElements = varType.arraySize > 0 ? varType.arraySize : 0;
        uint64_t oldBytes = oldElements * elemSize;
        if (oldBytes > 0) {
            llvm::Value* oldByteSizeVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), oldBytes);
            llvm::Value* copyBytes = m_builder->CreateSelect(
                m_builder->CreateICmpULT(newByteSize, oldByteSizeVal),
                newByteSize,
                oldByteSizeVal,
                "copybytes"
            );
            m_builder->CreateMemCpy(
                newBuf,
                llvm::MaybeAlign(1),
                oldBuf,
                llvm::MaybeAlign(1),
                copyBytes
            );
        }
        m_builder->CreateBr(contBB);
        m_builder->SetInsertPoint(contBB);
    }

    // Cast newBuf to variable type and store
    llvm::Value* typedBuf = coerceType(newBuf, vIt->second->getAllocatedType());
    m_builder->CreateStore(typedBuf, vIt->second);

    // Update variable type info
    varType.pointerDepth = (varType.pointerDepth == 0 ? 1 : varType.pointerDepth);
    varType.isArray = false;
    // If first dimension was a constant number, track arraySize
    if (auto num = dynamic_cast<NumberExprASTNode*>(redimNode.dimensions[0].get())) {
        varType.arraySize = num->val;
    }
}

void LlvmEmitter::emitPrintStatement(const PrintStmtNode& printNode) {
    llvm::Function* printStrFn = getOrCreatePrintStr();
    llvm::Value* tabStr = m_builder->CreateGlobalString("\t", "tab.s");
    llvm::Value* nlStr = m_builder->CreateGlobalString("\n", "nl.s");

    for (const auto& item : printNode.items) {
        if (item.expr) {
            llvm::Value* val = emitExpression(item.expr.get());
            if (val) {
                llvm::Value* strVal = convertToString(val);
                if (strVal) {
                    m_builder->CreateCall(printStrFn, {strVal});
                }
            }
        }
        if (item.separator == ',') {
            m_builder->CreateCall(printStrFn, {tabStr});
        }
    }

    if (!printNode.hasTrailingSeparator) {
        m_builder->CreateCall(printStrFn, {nlStr});
    }
}

void LlvmEmitter::emitPrintFileStatement(const PrintFileStmtNode& printFileNode) {
    if (!printFileNode.fileNumber) return;
    llvm::Value* numVal = emitExpression(printFileNode.fileNumber.get());
    if (!numVal) return;
    numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));

    llvm::Function* filePrintStrFn = getOrCreateFilePrintStr();
    llvm::Value* tabStr = m_builder->CreateGlobalString("\t", "tab.s");
    llvm::Value* nlStr = m_builder->CreateGlobalString("\n", "nl.s");

    for (const auto& item : printFileNode.items) {
        if (item.expr) {
            llvm::Value* val = emitExpression(item.expr.get());
            if (val) {
                llvm::Value* strVal = convertToString(val);
                if (strVal) {
                    m_builder->CreateCall(filePrintStrFn, {numVal, strVal});
                }
            }
        }
        if (item.separator == ',') {
            m_builder->CreateCall(filePrintStrFn, {numVal, tabStr});
        }
    }

    if (!printFileNode.hasTrailingSeparator) {
        m_builder->CreateCall(filePrintStrFn, {numVal, nlStr});
    }
}

void LlvmEmitter::emitOpenStatement(const OpenStmtNode& openNode) {
    if (!openNode.filePath || !openNode.fileNumber) return;
    llvm::Value* pathVal = emitExpression(openNode.filePath.get());
    llvm::Value* numVal = emitExpression(openNode.fileNumber.get());
    if (!pathVal || !numVal) return;

    pathVal = coerceType(pathVal, llvm::PointerType::get(*m_context, 0));
    numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));
    llvm::Value* modeVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<int>(openNode.mode));

    llvm::Function* openFn = getOrCreateFileOpen();
    m_builder->CreateCall(openFn, {pathVal, modeVal, numVal});
}

void LlvmEmitter::emitCloseStatement(const CloseStmtNode& closeNode) {
    llvm::Function* closeFn = getOrCreateFileClose();
    if (closeNode.fileNumbers.empty()) {
        // Close all
        m_builder->CreateCall(closeFn, {llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0)});
        return;
    }

    for (const auto& numExpr : closeNode.fileNumbers) {
        llvm::Value* numVal = emitExpression(numExpr.get());
        if (numVal) {
            numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));
            m_builder->CreateCall(closeFn, {numVal});
        }
    }
}

void LlvmEmitter::emitLineInputStatement(const LineInputStmtNode& lineInputNode) {
    if (!lineInputNode.fileNumber || !lineInputNode.targetVar) return;
    llvm::Value* numVal = emitExpression(lineInputNode.fileNumber.get());
    if (!numVal) return;
    numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));

    llvm::Function* lineFn = getOrCreateFileLineInput();
    llvm::Value* lineStr = m_builder->CreateCall(lineFn, {numVal}, "lineinput");

    // Assign to targetVar
    if (auto var = dynamic_cast<VariableExprASTNode*>(lineInputNode.targetVar.get())) {
        auto it = m_namedValues.find(var->name);
        if (it != m_namedValues.end()) {
            lineStr = coerceType(lineStr, it->second->getAllocatedType());
            m_builder->CreateStore(lineStr, it->second);
        }
    }
}

void LlvmEmitter::emitInputFileStatement(const InputFileStmtNode& inputFileNode) {
    if (!inputFileNode.fileNumber) return;
    llvm::Value* numVal = emitExpression(inputFileNode.fileNumber.get());
    if (!numVal) return;
    numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));

    llvm::Function* lineFn = getOrCreateFileLineInput();
    for (const auto& target : inputFileNode.targets) {
        llvm::Value* lineStr = m_builder->CreateCall(lineFn, {numVal}, "fileinput");
        if (auto var = dynamic_cast<VariableExprASTNode*>(target.get())) {
            auto it = m_namedValues.find(var->name);
            if (it != m_namedValues.end()) {
                lineStr = coerceType(lineStr, it->second->getAllocatedType());
                m_builder->CreateStore(lineStr, it->second);
            }
        }
    }
}

void LlvmEmitter::emitInputStatement(const InputStmtNode& inputNode) {
    if (!inputNode.prompt.empty()) {
        llvm::Function* printStrFn = getOrCreatePrintStr();
        llvm::Value* pStr = m_builder->CreateGlobalString(inputNode.prompt, "prompt.s");
        m_builder->CreateCall(printStrFn, {pStr});
    }
}

llvm::Value* LlvmEmitter::emitExpression(ExprASTNode* expr) {
    if (!expr) return nullptr;

    // Numbers
    if (auto num = dynamic_cast<NumberExprASTNode*>(expr)) {
        if (num->isFloat) {
            if (num->typeHint == "single") {
                return llvm::ConstantFP::get(llvm::Type::getFloatTy(*m_context), static_cast<float>(num->floatVal));
            } else {
                return llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), num->floatVal);
            }
        }
        if (num->typeHint == "Boolean") {
            return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), num->val != 0);
        }
        if (num->val < std::numeric_limits<int32_t>::min() || num->val > std::numeric_limits<int32_t>::max()) {
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), num->val);
        }
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), static_cast<int32_t>(num->val));
    }

    // Strings
    if (auto str = dynamic_cast<StringExprASTNode*>(expr)) {
        return m_builder->CreateGlobalString(str->val, "str");
    }

    // Variables & Enums
    if (auto var = dynamic_cast<VariableExprASTNode*>(expr)) {
        auto it = m_namedValues.find(var->name);
        if (it == m_namedValues.end()) {
            it = m_namedValues.find(toLower(var->name));
        }
        if (it != m_namedValues.end()) {
            auto tIt = m_variableTypes.find(var->name);
            if (tIt == m_variableTypes.end()) {
                tIt = m_variableTypes.find(toLower(var->name));
            }
            if (tIt != m_variableTypes.end() && tIt->second.isArray) {
                return it->second;
            }
            llvm::Value* val = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, var->name);
            if (m_byRefParams.count(var->name) || m_byRefParams.count(toLower(var->name))) {
                if (tIt != m_variableTypes.end() && tIt->second.pointerDepth == 0) {
                    llvm::Type* valTy = getLlvmType(tIt->second);
                    val = m_builder->CreateLoad(valTy, val, var->name + ".deref");
                }
            }
            return val;
        }

        // Check module-level global variable (including typed Const globals)
        llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), var->name);
        if (gVar) {
            auto tIt = m_variableTypes.find(var->name);
            if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(var->name));
            if (gVar->getValueType()->isArrayTy() || (tIt != m_variableTypes.end() && tIt->second.isArray)) {
                return gVar;
            }
            return m_builder->CreateLoad(gVar->getValueType(), gVar, var->name);
        }

        auto enumIt = m_enumConstants.find(var->name);
        if (enumIt == m_enumConstants.end()) {
            enumIt = m_enumConstants.find(toLower(var->name));
        }
        if (enumIt != m_enumConstants.end()) {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), enumIt->second);
        }
        auto enumLowerIt = m_enumConstants.find(toLower(var->name));
        if (enumLowerIt != m_enumConstants.end()) {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), enumLowerIt->second);
        }

        // Check module-level Property Get function (e.g. get_Prop)
        std::string getFnName = "get_" + var->name;
        llvm::Function* getFn = findFunctionCaseInsensitive(m_module.get(), getFnName);
        if (!getFn) {
            for (const auto& pair : m_structTypes) {
                std::string cand = pair.first + "_get_" + var->name;
                getFn = findFunctionCaseInsensitive(m_module.get(), cand);
                if (getFn) break;
            }
        }
        if (getFn && getFn->getFunctionType()->getNumParams() == 0) {
            return m_builder->CreateCall(getFn, {}, "propget");
        }

        // Undeclared variable guard
        Diagnostic::report(m_sourceFilePath, var->line > 0 ? var->line : m_currentLine,
                           var->column > 0 ? var->column : m_currentCol,
                           true, "Undeclared variable or identifier '" + var->name + "'.", m_sourceText);
        m_hadError = true;
        return nullptr;
    }

    // Casts: CPtr and CType
    if (auto cast = dynamic_cast<CastExprASTNode*>(expr)) {
        llvm::Value* innerVal = emitExpression(cast->expr.get());
        llvm::Type* targetTy = getLlvmType(cast->targetType);
        return coerceType(innerVal, targetTy);
    }

    // AddressOf targetName (Function pointer / procedure address)
    if (auto addrOf = dynamic_cast<AddressOfExprASTNode*>(expr)) {
        if (addrOf->targetExpr) {
            llvm::Value* ptr = getPointerToExpr(addrOf->targetExpr.get());
            if (ptr) return ptr;
            return emitExpression(addrOf->targetExpr.get());
        }
        std::string targetName = addrOf->targetName;
        auto aliasIt = m_funcAliases.find(targetName);
        if (aliasIt != m_funcAliases.end()) {
            targetName = aliasIt->second;
        }
        llvm::Function* callee = findFunctionCaseInsensitive(m_module.get(), targetName);
        if (!callee && m_module && m_module->getName().str().find('.') != std::string::npos) {
            std::string modPref = m_module->getName().str();
            for (auto& ch : modPref) {
                if (ch == '.') ch = '_';
            }
            callee = findFunctionCaseInsensitive(m_module.get(), modPref + "_" + targetName);
        }
        if (callee) {
            return callee;
        }
        // Try looking up in named local values
        auto localIt = m_namedValues.find(addrOf->targetName);
        if (localIt != m_namedValues.end()) {
            return localIt->second;
        }
        // Try looking up in global variables
        llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), addrOf->targetName);
        if (gVar) {
            return gVar;
        }
        return nullptr;
    }

    // Member Access: base.member
    if (auto member = dynamic_cast<MemberAccessExprASTNode*>(expr)) {
        // 1. Check if base is Err object (VB6 Err runtime singleton)
        if (member->base) {
            if (auto varBase = dynamic_cast<VariableExprASTNode*>(member->base.get())) {
                if (toLower(varBase->name) == "err") {
                    std::string prop = toLower(member->memberName);
                    if (prop == "number") {
                        return m_builder->CreateLoad(llvm::Type::getInt32Ty(*m_context), getOrCreateErrNumber(), "err.number");
                    }
                    if (prop == "source") {
                        return m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), getOrCreateErrSource(), "err.source");
                    }
                    if (prop == "description") {
                        return m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), getOrCreateErrDescription(), "err.description");
                    }
                }
            }
        }

        // 2. Check if base is an Enum identifier: e.g. Color.Red
        if (member->base) {
            if (auto varBase = dynamic_cast<VariableExprASTNode*>(member->base.get())) {
                auto eIt = m_enums.find(varBase->name);
                if (eIt == m_enums.end()) eIt = m_enums.find(toLower(varBase->name));
                if (eIt != m_enums.end()) {
                    auto mIt = eIt->second.find(member->memberName);
                    if (mIt == eIt->second.end()) mIt = eIt->second.find(toLower(member->memberName));
                    if (mIt != eIt->second.end()) {
                        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), mIt->second);
                    }
                }
            }
        }

        // 3. Check if base.member is a qualified global constant or variable (e.g. Drivers.Terminal.COLOR_WHITE)
        {
            std::function<std::string(ExprASTNode*)> getDottedName = [&](ExprASTNode* e) -> std::string {
                if (auto v = dynamic_cast<VariableExprASTNode*>(e)) return v->name;
                if (auto m = dynamic_cast<MemberAccessExprASTNode*>(e)) {
                    std::string p = getDottedName(m->base.get());
                    return p.empty() ? m->memberName : (p + "." + m->memberName);
                }
                return "";
            };
            std::string dotted = getDottedName(member->base.get());
            if (!dotted.empty() && 
                m_namedValues.find(dotted) == m_namedValues.end() && 
                m_namedValues.find(toLower(dotted)) == m_namedValues.end()) {
                std::string fullQual = dotted + "." + member->memberName;
                std::string mangled = fullQual;
                for (auto& c : mangled) {
                    if (c == '.') c = '_';
                }
                auto enumIt = m_enumConstants.find(fullQual);
                if (enumIt == m_enumConstants.end()) enumIt = m_enumConstants.find(toLower(fullQual));
                if (enumIt != m_enumConstants.end()) {
                    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), enumIt->second);
                }

                llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), fullQual);
                if (!gVar) gVar = findGlobalCaseInsensitive(m_module.get(), mangled);
                if (gVar) {
                    return m_builder->CreateLoad(gVar->getValueType(), gVar, member->memberName);
                }
            }
        }

        llvm::Value* basePtr = member->base ? getPointerToExpr(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().first : nullptr);
        if (basePtr) {
            std::string memberLower = toLower(member->memberName);
            TypeSpec baseType = member->base ? deduceExprType(member->base.get()) : (!m_withStack.empty() ? m_withStack.back().second : TypeSpec());
            std::string explicitStructName = !baseType.name.empty() ? (!baseType.typeArgs.empty() ? toLower(instantiateGenericStruct(baseType)) : toLower(baseType.name)) : "";

            for (const auto& pair : m_structFieldIndices) {
                if (!explicitStructName.empty() && toLower(pair.first) != explicitStructName) {
                    continue;
                }
                auto fIt = pair.second.find(memberLower);
                if (fIt != pair.second.end()) {
                    unsigned fieldIdx = fIt->second;
                    std::string privKey = pair.first + "." + member->memberName;
                    if (m_privateFields.count(privKey) || m_privateFields.count(toLower(privKey))) {
                        if (toLower(m_currentScopeClass) != toLower(pair.first)) {
                            Diagnostic::report(m_sourceFilePath, member->line > 0 ? member->line : m_currentLine,
                                               member->column > 0 ? member->column : m_currentCol,
                                               true, "Cannot access private member '" + member->memberName + "' of class '" + pair.first + "'.", m_sourceText);
                            m_hadError = true;
                            return nullptr;
                        }
                    }
                    auto stIt = m_structTypes.find(pair.first);
                    if (stIt != m_structTypes.end()) {
                        if (m_unionTypes.count(pair.first)) {
                            llvm::Type* fieldTy = llvm::Type::getInt8Ty(*m_context);
                            auto ftIt = m_structFieldTypes.find(pair.first);
                            if (ftIt == m_structFieldTypes.end()) {
                                ftIt = m_structFieldTypes.find(toLower(pair.first));
                            }
                            if (ftIt != m_structFieldTypes.end()) {
                                auto tIt = ftIt->second.find(memberLower);
                                if (tIt != ftIt->second.end()) {
                                    fieldTy = getLlvmType(tIt->second);
                                }
                            }
                            llvm::Value* rawVal = m_builder->CreateLoad(fieldTy, basePtr, member->memberName);
                            auto bIt = m_structBitfields.find(pair.first);
                            if (bIt != m_structBitfields.end()) {
                                auto bfIt = bIt->second.find(memberLower);
                                if (bfIt != bIt->second.end()) {
                                    const auto& binfo = bfIt->second;
                                    uint64_t mask = (binfo.bitWidth >= 64) ? ~0ULL : ((1ULL << binfo.bitWidth) - 1ULL);
                                    llvm::Value* maskVal = llvm::ConstantInt::get(rawVal->getType(), mask);
                                    return m_builder->CreateAnd(rawVal, maskVal, "bf.read");
                                }
                            }
                            return rawVal;
                        }
                        llvm::Value* gep = m_builder->CreateStructGEP(stIt->second, basePtr, fieldIdx, "membergep");
                        llvm::Value* rawVal = m_builder->CreateLoad(stIt->second->getElementType(fieldIdx), gep, member->memberName);

                        auto bIt = m_structBitfields.find(pair.first);
                        if (bIt != m_structBitfields.end()) {
                            auto bfIt = bIt->second.find(memberLower);
                            if (bfIt != bIt->second.end()) {
                                const auto& binfo = bfIt->second;
                                llvm::Type* contTy = rawVal->getType();
                                if (binfo.bitOffset > 0) {
                                    llvm::Value* shiftVal = llvm::ConstantInt::get(contTy, binfo.bitOffset);
                                    rawVal = m_builder->CreateLShr(rawVal, shiftVal, "bf.shr");
                                }
                                uint64_t mask = (binfo.bitWidth >= 64) ? ~0ULL : ((1ULL << binfo.bitWidth) - 1ULL);
                                llvm::Value* maskVal = llvm::ConstantInt::get(contTy, mask);
                                llvm::Value* extracted = m_builder->CreateAnd(rawVal, maskVal, "bf.and");

                                // Coerce to declared field type (e.g. Byte, UInt16, UInt32)
                                auto ftIt = m_structFieldTypes.find(pair.first);
                                if (ftIt != m_structFieldTypes.end()) {
                                    auto tIt = ftIt->second.find(memberLower);
                                    if (tIt != ftIt->second.end()) {
                                        llvm::Type* declTy = getLlvmType(tIt->second);
                                        return coerceType(extracted, declTy);
                                    }
                                }
                                return extracted;
                            }
                        }
                        return rawVal;
                    }
                }
            }
            // Check if Property Get exists (e.g. get_Prop, Class_get_Prop)
            std::string getFuncName = "get_" + member->memberName;
            llvm::Function* getFn = findFunctionCaseInsensitive(m_module.get(), getFuncName);
            if (!getFn) {
                // Check class prefixed get function
                for (const auto& pair : m_structTypes) {
                    std::string cand = pair.first + "_get_" + member->memberName;
                    getFn = findFunctionCaseInsensitive(m_module.get(), cand);
                    if (getFn) break;
                }
            }
            if (getFn) {
                if (getFn->getFunctionType()->getNumParams() == 1) {
                    return m_builder->CreateCall(getFn, {basePtr}, "propget");
                } else if (getFn->getFunctionType()->getNumParams() == 0) {
                    return m_builder->CreateCall(getFn, {}, "propget");
                }
            }

            Diagnostic::report(m_sourceFilePath, member->line > 0 ? member->line : m_currentLine,
                               member->column > 0 ? member->column : m_currentCol,
                               true, "Type has no member named '" + member->memberName + "'.", m_sourceText);
            m_hadError = true;
            return nullptr;
        }
        return nullptr;
    }

    // New ClassName[(args...)]
    if (auto newExpr = dynamic_cast<NewExprASTNode*>(expr)) {
        // Find struct type
        std::string clsName = newExpr->className;
        auto aIt = m_funcAliases.find(clsName);
        if (aIt != m_funcAliases.end()) clsName = aIt->second;
        else {
            auto aItLower = m_funcAliases.find(toLower(clsName));
            if (aItLower != m_funcAliases.end()) clsName = aItLower->second;
        }

        llvm::StructType* st = nullptr;
        auto stIt = m_structTypes.find(clsName);
        if (stIt != m_structTypes.end()) {
            st = stIt->second;
        } else {
            auto stLowerIt = m_structTypes.find(toLower(clsName));
            if (stLowerIt != m_structTypes.end()) {
                st = stLowerIt->second;
            }
        }

        if (!st) {
            Diagnostic::report(m_sourceFilePath, newExpr->line > 0 ? newExpr->line : m_currentLine,
                               newExpr->column > 0 ? newExpr->column : m_currentCol,
                               true, "Cannot find class or structure '" + newExpr->className + "' in this scope.", m_sourceText);
            m_hadError = true;
            return nullptr;
        }

        const llvm::DataLayout& dl = m_module->getDataLayout();
        uint64_t allocSize = dl.getTypeAllocSize(st);
        if (allocSize == 0) allocSize = 64;

        llvm::Function* mallocFn = getOrCreateMalloc();
        llvm::Value* rawPtr = m_builder->CreateCall(
            mallocFn,
            {llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), allocSize)},
            "new.obj"
        );

        // Zero-initialize allocated memory
        m_builder->CreateMemSet(
            rawPtr,
            llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0),
            llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), allocSize),
            llvm::MaybeAlign(1)
        );

        // Check if constructor / initializer exists: ClassName_Class_Initialize(Me)
        std::string initFnName = newExpr->className + "_Class_Initialize";
        llvm::Function* initFn = findFunctionCaseInsensitive(m_module.get(), initFnName);
        if (initFn) {
            if (initFn->getFunctionType()->getNumParams() == 1) {
                m_builder->CreateCall(initFn, {rawPtr});
            }
        }

        return rawPtr;
    }

    // Index Expression: base(index)
    if (auto idx = dynamic_cast<IndexExprASTNode*>(expr)) {
        llvm::Value* baseVal = nullptr;
        TypeSpec baseType;
        if (auto var = dynamic_cast<VariableExprASTNode*>(idx->base.get())) {
            auto it = m_namedValues.find(var->name);
            auto tIt = m_variableTypes.find(var->name);
            if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(var->name));
            if (tIt != m_variableTypes.end()) baseType = tIt->second;
            if (it != m_namedValues.end()) {
                if (baseType.isArray) {
                    baseVal = it->second;
                } else {
                    baseVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, var->name);
                }
            } else {
                llvm::GlobalVariable* gVar = findGlobalCaseInsensitive(m_module.get(), var->name);
                if (gVar) {
                    baseVal = gVar;
                }
            }
        }
        if (!baseVal) {
            baseVal = emitExpression(idx->base.get());
        }

        llvm::Value* flatIdx = nullptr;
        if (!idx->indices.empty()) {
            flatIdx = emitExpression(idx->indices[0].get());
        } else if (idx->index) {
            flatIdx = emitExpression(idx->index.get());
        }

        if (baseVal && flatIdx) {
            if (baseType.isArray && baseType.arraySize > 0) {
                ExprASTNode* rawIdxExpr = !idx->indices.empty() ? idx->indices[0].get() : idx->index.get();
                if (auto numIdx = dynamic_cast<NumberExprASTNode*>(rawIdxExpr)) {
                    if (!numIdx->isFloat && (numIdx->val < 0 || static_cast<uint64_t>(numIdx->val) >= baseType.arraySize)) {
                        Diagnostic::report(m_sourceFilePath, idx->line > 0 ? idx->line : m_currentLine,
                                           idx->column > 0 ? idx->column : m_currentCol,
                                           true, "Array index " + std::to_string(numIdx->val) + " is out of bounds for array of size " + std::to_string(baseType.arraySize) + " [0.." + std::to_string(baseType.arraySize - 1) + "].", m_sourceText);
                        m_hadError = true;
                        return nullptr;
                    }
                }
                emitBoundsCheck(flatIdx, baseType.arraySize, "array_read");
            }

            llvm::Type* elemType = nullptr;
            if (baseType.pointerDepth > 0 || baseType.isArray) {
                elemType = getElementType(baseType);
            } else if (baseVal->getType()->isPointerTy()) {
                elemType = llvm::Type::getInt32Ty(*m_context); // sensible default primitive
            } else {
                elemType = llvm::Type::getInt8Ty(*m_context);
            }

            flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));
            llvm::Value* gep = m_builder->CreateGEP(elemType, baseVal, flatIdx, "idxgep");
            auto* loadInst = m_builder->CreateLoad(elemType, gep, "idxload");
            if (baseType.isVolatile) {
                loadInst->setVolatile(true);
            }
            return loadInst;
        }
        return nullptr;
    }

    // Function Calls and Indexing Fallback
    if (auto call = dynamic_cast<CallExprASTNode*>(expr)) {
        // Check if funcName is actually a local variable/parameter in m_namedValues or global array (e.g. arr(i) or matrix(r, c))
        if (!call->calleeExpr && !call->args.empty()) {
            auto it = m_namedValues.find(call->funcName);
            auto tIt = m_variableTypes.find(call->funcName);
            if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(call->funcName));
            llvm::GlobalVariable* gVar = nullptr;
            if (it == m_namedValues.end() && tIt != m_variableTypes.end()) {
                gVar = findGlobalCaseInsensitive(m_module.get(), call->funcName);
            }
            if (it != m_namedValues.end() || gVar) {
                TypeSpec baseType = (tIt != m_variableTypes.end()) ? tIt->second : TypeSpec();
                if (gVar && baseType.name.empty() && gVar->getValueType()->isArrayTy()) {
                    baseType.isArray = true;
                }
                if (baseType.pointerDepth > 0 || baseType.isArray || toLower(baseType.name) == "string") {
                    llvm::Value* baseVal = nullptr;
                    if (it != m_namedValues.end()) {
                        if (baseType.isArray) {
                            baseVal = it->second;
                        } else {
                            baseVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, call->funcName);
                        }
                    } else if (gVar) {
                        baseVal = gVar;
                    }

                    // Compute flat index: for 2D matrix(rows, cols), idx = r * cols + c
                    llvm::Value* flatIdx = nullptr;
                    if (baseType.dimensions.size() > 1 && call->args.size() == baseType.dimensions.size()) {
                        flatIdx = emitExpression(call->args[0].get());
                        flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));
                        for (size_t d = 1; d < baseType.dimensions.size(); ++d) {
                            llvm::Value* dimSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), baseType.dimensions[d]);
                            flatIdx = m_builder->CreateMul(flatIdx, dimSize, "matrowmul");
                            llvm::Value* nextIdx = emitExpression(call->args[d].get());
                            nextIdx = coerceType(nextIdx, llvm::Type::getInt64Ty(*m_context));
                            flatIdx = m_builder->CreateAdd(flatIdx, nextIdx, "matcoladd");
                        }
                    } else {
                        flatIdx = emitExpression(call->args[0].get());
                    }

                    // Check if map or string subscript lookup
                    ExprASTNode* keyExpr = call->args[0].get();
                    if (toLower(baseType.name) == "map" || toLower(baseType.name) == "dictionary" || isStringExpr(keyExpr)) {
                        llvm::Value* keyVal = emitExpression(keyExpr);
                        keyVal = coerceType(keyVal, llvm::PointerType::get(*m_context, 0));
                        llvm::Function* mapGetFn = getOrCreateMapGet();
                        llvm::Value* resI64 = m_builder->CreateCall(mapGetFn, {baseVal, keyVal}, "mapget");
                        return coerceType(resI64, llvm::Type::getInt64Ty(*m_context));
                    }

                    llvm::Type* elemType = getElementType(baseType);
                    if (!flatIdx || !baseVal) return nullptr;
                    flatIdx = coerceType(flatIdx, llvm::Type::getInt64Ty(*m_context));
                    llvm::Value* gep = m_builder->CreateGEP(elemType, baseVal, flatIdx, "arridx");
                    auto* loadInst = m_builder->CreateLoad(elemType, gep, "arrload");
                    if (baseType.isVolatile) {
                        loadInst->setVolatile(true);
                    }
                    return loadInst;
                }
            }
        }

        // Support member indexing: obj.member(idx) (e.g. map.EntriesBuffer(slot1))
        if (call->calleeExpr && !call->args.empty()) {
            auto memberAccess = std::make_unique<MemberAccessExprASTNode>(nullptr, call->funcName);
            llvm::Value* baseVal = nullptr;
            llvm::Value* basePtr = getPointerToExpr(call->calleeExpr.get());
            TypeSpec fieldType;
            if (basePtr) {
                std::string memberLower = toLower(call->funcName);
                TypeSpec objType = deduceExprType(call->calleeExpr.get());
                for (const auto& pair : m_structFieldIndices) {
                    if (!objType.name.empty() && toLower(pair.first) != toLower(objType.name)) {
                        continue;
                    }
                    auto fIt = pair.second.find(memberLower);
                    if (fIt != pair.second.end()) {
                        unsigned fieldIdx = fIt->second;
                        auto stIt = m_structTypes.find(pair.first);
                        if (stIt != m_structTypes.end()) {
                            if (m_unionTypes.count(pair.first)) {
                                auto ftIt = m_structFieldTypes.find(pair.first);
                                if (ftIt != m_structFieldTypes.end()) {
                                    auto tIt = ftIt->second.find(memberLower);
                                    if (tIt != ftIt->second.end()) {
                                        fieldType = tIt->second;
                                        baseVal = basePtr;
                                        break;
                                    }
                                }
                            }
                            llvm::Value* gep = m_builder->CreateStructGEP(stIt->second, basePtr, fieldIdx, "membergep");
                            baseVal = m_builder->CreateLoad(stIt->second->getElementType(fieldIdx), gep, call->funcName);
                            // Set fieldType name from struct type definition
                            fieldType.name = pair.first;
                            fieldType.pointerDepth = 1;
                            break;
                        }
                    }
                }
            }
            if (baseVal) {
                llvm::Value* idxVal = emitExpression(call->args[0].get());
                if (idxVal) {
                    idxVal = coerceType(idxVal, llvm::Type::getInt64Ty(*m_context));
                    // Get element type: if baseVal is pointer to T, element type is T
                    llvm::Type* elemType = baseVal->getType()->isPointerTy() ? llvm::Type::getInt8Ty(*m_context) : baseVal->getType();
                    // Check if struct type matches any registered struct
                    for (const auto& stPair : m_structTypes) {
                        if (toLower(stPair.first) == toLower(fieldType.name) || baseVal->getType()->isPointerTy()) {
                            // Find element type for entries
                            auto entryStIt = m_structTypes.find("HashMapEntry");
                            if (entryStIt != m_structTypes.end()) {
                                elemType = entryStIt->second;
                            }
                            break;
                        }
                    }
                    llvm::Value* gep = m_builder->CreateGEP(elemType, baseVal, idxVal, "memberidxgep");
                    return m_builder->CreateLoad(elemType, gep, "memberidxload");
                }
            }
        }

        std::string lowerFn = toLower(call->funcName);

        // --- Array Bounds Intrinsics (UBound / LBound) ---
        if (lowerFn == "ubound") {
            if (!call->args.empty()) {
                if (auto var = dynamic_cast<VariableExprASTNode*>(call->args[0].get())) {
                    auto it = m_variableTypes.find(var->name);
                    if (it != m_variableTypes.end() && it->second.isArray) {
                        int64_t dimIdx = 1;
                        if (call->args.size() >= 2) {
                            if (auto num = dynamic_cast<NumberExprASTNode*>(call->args[1].get())) {
                                dimIdx = num->val;
                            }
                        }
                        if (!it->second.dimensions.empty()) {
                            if (dimIdx >= 1 && static_cast<size_t>(dimIdx) <= it->second.dimensions.size()) {
                                return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), it->second.dimensions[dimIdx - 1] - 1);
                            }
                        }
                        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), it->second.arraySize > 0 ? it->second.arraySize - 1 : 0);
                    }
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "lbound") {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        // --- Map / Dictionary Intrinsics ---
        if (lowerFn == "mapcreate" || lowerFn == "dictcreate") {
            llvm::Function* createFn = getOrCreateMapCreate();
            return m_builder->CreateCall(createFn, {}, "mapnew");
        }

        if (lowerFn == "maphas" || lowerFn == "dicthas") {
            if (call->args.size() >= 2) {
                llvm::Value* mapVal = emitExpression(call->args[0].get());
                llvm::Value* keyVal = emitExpression(call->args[1].get());
                if (mapVal && keyVal) {
                    mapVal = coerceType(mapVal, llvm::PointerType::get(*m_context, 0));
                    keyVal = coerceType(keyVal, llvm::PointerType::get(*m_context, 0));
                    llvm::Function* hasFn = getOrCreateMapHas();
                    return m_builder->CreateCall(hasFn, {mapVal, keyVal}, "hasres");
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0);
        }

        if (lowerFn == "mapget" || lowerFn == "dictget") {
            if (call->args.size() >= 2) {
                llvm::Value* mapVal = emitExpression(call->args[0].get());
                llvm::Value* keyVal = emitExpression(call->args[1].get());
                if (mapVal && keyVal) {
                    mapVal = coerceType(mapVal, llvm::PointerType::get(*m_context, 0));
                    keyVal = coerceType(keyVal, llvm::PointerType::get(*m_context, 0));
                    llvm::Function* getFn = getOrCreateMapGet();
                    return m_builder->CreateCall(getFn, {mapVal, keyVal}, "getres");
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
        }

        // Standard String & Conversion Intrinsics (VB6 / LLB Phase 2)
        if (lowerFn == "len") {
            if (!call->args.empty()) {
                llvm::Value* argVal = emitExpression(call->args[0].get());
                if (argVal && argVal->getType()->isPointerTy()) {
                    llvm::Function* strlenFn = getOrCreateStrlen();
                    llvm::Value* lenVal = m_builder->CreateCall(strlenFn, {argVal}, "len");
                    return m_builder->CreateTrunc(lenVal, llvm::Type::getInt32Ty(*m_context), "len32");
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "mid" || lowerFn == "mid$") {
            if (call->args.size() >= 2) {
                if (!isStringExpr(call->args[0].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in '" + call->funcName + "': string argument expected. Use 'CStr()' or 'Str()' for explicit conversion.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
                llvm::Value* sVal = emitExpression(call->args[0].get());
                llvm::Value* startVal = emitExpression(call->args[1].get());
                if (!sVal || !startVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                startVal = coerceType(startVal, llvm::Type::getInt64Ty(*m_context));

                llvm::Value* lenVal = nullptr;
                if (call->args.size() >= 3) {
                    lenVal = emitExpression(call->args[2].get());
                    lenVal = coerceType(lenVal, llvm::Type::getInt64Ty(*m_context));
                } else {
                    lenVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), -1ULL, true);
                }
                llvm::Function* midFn = getOrCreateStrMid();
                return m_builder->CreateCall(midFn, {sVal, startVal, lenVal}, "midres");
            }
            return nullptr;
        }

        if (lowerFn == "left" || lowerFn == "left$") {
            if (call->args.size() >= 2) {
                if (!isStringExpr(call->args[0].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in '" + call->funcName + "': string argument expected. Use 'CStr()' or 'Str()' for explicit conversion.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
                llvm::Value* sVal = emitExpression(call->args[0].get());
                llvm::Value* nVal = emitExpression(call->args[1].get());
                if (!sVal || !nVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                nVal = coerceType(nVal, llvm::Type::getInt64Ty(*m_context));

                llvm::Value* start1 = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1);
                llvm::Function* midFn = getOrCreateStrMid();
                return m_builder->CreateCall(midFn, {sVal, start1, nVal}, "leftres");
            }
            return nullptr;
        }

        if (lowerFn == "right" || lowerFn == "right$") {
            if (call->args.size() >= 2) {
                if (!isStringExpr(call->args[0].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in '" + call->funcName + "': string argument expected. Use 'CStr()' or 'Str()' for explicit conversion.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
                llvm::Value* sVal = emitExpression(call->args[0].get());
                llvm::Value* nVal = emitExpression(call->args[1].get());
                if (!sVal || !nVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                nVal = coerceType(nVal, llvm::Type::getInt64Ty(*m_context));

                llvm::Function* rightFn = getOrCreateStrRight();
                return m_builder->CreateCall(rightFn, {sVal, nVal}, "rightres");
            }
            return nullptr;
        }

        if (lowerFn == "instr") {
            if (call->args.size() >= 2) {
                ExprASTNode* sExpr = (call->args.size() >= 3) ? call->args[1].get() : call->args[0].get();
                ExprASTNode* subExpr = (call->args.size() >= 3) ? call->args[2].get() : call->args[1].get();
                if (!isStringExpr(sExpr) || !isStringExpr(subExpr)) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in 'InStr': search string arguments must be of String type. Use 'CStr()' or 'Str()' for explicit conversion.", m_sourceText);
                    m_hadError = true;
                    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                }

                llvm::Value* sVal = nullptr;
                llvm::Value* subVal = nullptr;
                llvm::Value* startVal = nullptr;

                if (call->args.size() >= 3) {
                    startVal = emitExpression(call->args[0].get());
                    sVal = emitExpression(call->args[1].get());
                    subVal = emitExpression(call->args[2].get());
                    startVal = coerceType(startVal, llvm::Type::getInt64Ty(*m_context));
                } else {
                    sVal = emitExpression(call->args[0].get());
                    subVal = emitExpression(call->args[1].get());
                    startVal = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 1);
                }
                if (!sVal || !subVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                subVal = coerceType(subVal, llvm::PointerType::get(*m_context, 0));

                llvm::Function* instrFn = getOrCreateStrInStr();
                return m_builder->CreateCall(instrFn, {sVal, subVal, startVal}, "instrres");
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "trim" || lowerFn == "trim$" ||
            lowerFn == "ltrim" || lowerFn == "ltrim$" ||
            lowerFn == "rtrim" || lowerFn == "rtrim$") {
            if (!call->args.empty()) {
                if (!isStringExpr(call->args[0].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in '" + call->funcName + "': expected String, got numeric or incompatible type. Use 'CStr()' or 'Str()' for explicit conversion.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
                llvm::Value* sVal = emitExpression(call->args[0].get());
                if (!sVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                llvm::Function* trimFn = nullptr;
                if (lowerFn == "ltrim" || lowerFn == "ltrim$") {
                    trimFn = getOrCreateStrLTrim();
                } else if (lowerFn == "rtrim" || lowerFn == "rtrim$") {
                    trimFn = getOrCreateStrRTrim();
                } else {
                    trimFn = getOrCreateStrTrim();
                }
                return m_builder->CreateCall(trimFn, {sVal}, "trimres");
            }
            return nullptr;
        }

        if (lowerFn == "strcomp") {
            if (call->args.size() >= 2) {
                if (!isStringExpr(call->args[0].get()) || !isStringExpr(call->args[1].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in 'StrComp': arguments must be of String type.", m_sourceText);
                    m_hadError = true;
                    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                }
                llvm::Value* s1Val = emitExpression(call->args[0].get());
                llvm::Value* s2Val = emitExpression(call->args[1].get());
                if (!s1Val || !s2Val) return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                s1Val = coerceType(s1Val, llvm::PointerType::get(*m_context, 0));
                s2Val = coerceType(s2Val, llvm::PointerType::get(*m_context, 0));
                llvm::Function* strcmpFn = getOrCreateStrcmp();
                llvm::Value* diff = m_builder->CreateCall(strcmpFn, {s1Val, s2Val}, "strcompdiff");
                // Convert diff into -1, 0, or 1 (classic VB6 StrComp return convention)
                llvm::Value* isLT = m_builder->CreateICmpSLT(diff, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
                llvm::Value* isGT = m_builder->CreateICmpSGT(diff, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
                llvm::Value* minusOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), -1);
                llvm::Value* plusOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1);
                llvm::Value* zeroVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                llvm::Value* res = m_builder->CreateSelect(isLT, minusOne, m_builder->CreateSelect(isGT, plusOne, zeroVal), "strcompres");
                return res;
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "asc") {
            if (!call->args.empty()) {
                if (!isStringExpr(call->args[0].get())) {
                    Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                       call->column > 0 ? call->column : m_currentCol,
                                       true, "Type mismatch in 'Asc': argument must be of String type.", m_sourceText);
                    m_hadError = true;
                    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                }
                llvm::Value* sVal = emitExpression(call->args[0].get());
                if (!sVal) return nullptr;
                sVal = coerceType(sVal, llvm::PointerType::get(*m_context, 0));
                llvm::Function* ascFn = getOrCreateAsc();
                return m_builder->CreateCall(ascFn, {sVal}, "ascres");
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "chr" || lowerFn == "chr$") {
            if (!call->args.empty()) {
                llvm::Value* codeVal = emitExpression(call->args[0].get());
                if (!codeVal) return nullptr;
                codeVal = coerceType(codeVal, llvm::Type::getInt32Ty(*m_context));
                llvm::Function* chrFn = getOrCreateChr();
                return m_builder->CreateCall(chrFn, {codeVal}, "chrres");
            }
            return nullptr;
        }

        if (lowerFn == "val") {
            if (!call->args.empty()) {
                llvm::Value* sVal = emitExpression(call->args[0].get());
                if (!sVal) return nullptr;
                // If already a numeric type, return it directly (avoids inttoptr)
                if (sVal->getType()->isIntegerTy()) {
                    return m_builder->CreateSIToFP(sVal, llvm::Type::getDoubleTy(*m_context), "val.i2d");
                }
                if (sVal->getType()->isFloatingPointTy()) {
                    return coerceType(sVal, llvm::Type::getDoubleTy(*m_context));
                }
                llvm::Function* valFn = getOrCreateStrVal();
                return m_builder->CreateCall(valFn, {sVal}, "valres");
            }
            return llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.0);
        }

        if (lowerFn == "cstr" || lowerFn == "str" || lowerFn == "str$") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                return convertToString(val);
            }
            return nullptr;
        }

        if (lowerFn == "cint") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isPointerTy()) {
                    llvm::Function* valFn = getOrCreateStrVal();
                    llvm::Value* dval = m_builder->CreateCall(valFn, {val}, "cintval");
                    return m_builder->CreateFPToSI(dval, llvm::Type::getInt32Ty(*m_context), "cint");
                }
                return coerceType(val, llvm::Type::getInt32Ty(*m_context));
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "clng") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isPointerTy()) {
                    llvm::Function* valFn = getOrCreateStrVal();
                    llvm::Value* dval = m_builder->CreateCall(valFn, {val}, "clngval");
                    return m_builder->CreateFPToSI(dval, llvm::Type::getInt64Ty(*m_context), "clng");
                }
                return coerceType(val, llvm::Type::getInt64Ty(*m_context));
            }
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
        }

        if (lowerFn == "cdbl") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isPointerTy()) {
                    llvm::Function* valFn = getOrCreateStrVal();
                    return m_builder->CreateCall(valFn, {val}, "cdbl");
                }
                return coerceType(val, llvm::Type::getDoubleTy(*m_context));
            }
            return llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.0);
        }

        // --- Memory Runtime Intrinsics (CopyMemory, ZeroMemory, FillMemory) ---
        if (lowerFn == "copymemory") {
            std::vector<ExprASTNode*> allArgExprs;
            for (const auto& a : call->args) allArgExprs.push_back(a.get());
            for (const auto& na : call->namedArgs) allArgExprs.push_back(na.expr.get());

            if (allArgExprs.size() >= 3) {
                llvm::Value* dest = emitExpression(allArgExprs[0]);
                if (!dest || !dest->getType()->isPointerTy()) {
                    dest = getPointerToExpr(allArgExprs[0]);
                }
                llvm::Value* src = emitExpression(allArgExprs[1]);
                if (!src || !src->getType()->isPointerTy()) {
                    src = getPointerToExpr(allArgExprs[1]);
                }
                llvm::Value* len = emitExpression(allArgExprs[2]);
                if (dest && src && len) {
                    dest = coerceType(dest, llvm::PointerType::get(*m_context, 0));
                    src = coerceType(src, llvm::PointerType::get(*m_context, 0));
                    len = coerceType(len, llvm::Type::getInt64Ty(*m_context));
                    m_builder->CreateMemCpy(dest, llvm::MaybeAlign(1), src, llvm::MaybeAlign(1), len);
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "zeromemory") {
            std::vector<ExprASTNode*> allArgExprs;
            for (const auto& a : call->args) allArgExprs.push_back(a.get());
            for (const auto& na : call->namedArgs) allArgExprs.push_back(na.expr.get());

            if (allArgExprs.size() >= 2) {
                llvm::Value* dest = emitExpression(allArgExprs[0]);
                if (!dest || !dest->getType()->isPointerTy()) {
                    dest = getPointerToExpr(allArgExprs[0]);
                }
                llvm::Value* len = emitExpression(allArgExprs[1]);
                if (dest && len) {
                    dest = coerceType(dest, llvm::PointerType::get(*m_context, 0));
                    len = coerceType(len, llvm::Type::getInt64Ty(*m_context));
                    llvm::Value* zeroByte = llvm::ConstantInt::get(llvm::Type::getInt8Ty(*m_context), 0);
                    m_builder->CreateMemSet(dest, zeroByte, len, llvm::MaybeAlign(1));
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "fillmemory") {
            std::vector<ExprASTNode*> allArgExprs;
            for (const auto& a : call->args) allArgExprs.push_back(a.get());
            for (const auto& na : call->namedArgs) allArgExprs.push_back(na.expr.get());

            if (allArgExprs.size() >= 3) {
                llvm::Value* dest = emitExpression(allArgExprs[0]);
                if (!dest || !dest->getType()->isPointerTy()) {
                    dest = getPointerToExpr(allArgExprs[0]);
                }
                llvm::Value* len = emitExpression(allArgExprs[1]);
                llvm::Value* fillByte = emitExpression(allArgExprs[2]);
                if (dest && len && fillByte) {
                    dest = coerceType(dest, llvm::PointerType::get(*m_context, 0));
                    len = coerceType(len, llvm::Type::getInt64Ty(*m_context));
                    fillByte = coerceType(fillByte, llvm::Type::getInt8Ty(*m_context));
                    m_builder->CreateMemSet(dest, fillByte, len, llvm::MaybeAlign(1));
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        // --- Standard Math Library Intrinsics ---
        if (lowerFn == "abs") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isFloatingPointTy()) {
                    llvm::Function* fabsFn = llvm::Intrinsic::getOrInsertDeclaration(m_module.get(), llvm::Intrinsic::fabs, {val->getType()});
                    return m_builder->CreateCall(fabsFn, {val}, "abstmp");
                } else if (val->getType()->isIntegerTy()) {
                    llvm::Value* zero = llvm::ConstantInt::get(val->getType(), 0);
                    llvm::Value* isNeg = m_builder->CreateICmpSLT(val, zero, "isneg");
                    llvm::Value* neg = m_builder->CreateNeg(val, "negval");
                    return m_builder->CreateSelect(isNeg, neg, val, "abstmp");
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "sgn") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isFloatingPointTy()) {
                    llvm::Value* zero = llvm::ConstantFP::get(val->getType(), 0.0);
                    llvm::Value* isGt = m_builder->CreateFCmpOGT(val, zero, "sgngt");
                    llvm::Value* isLt = m_builder->CreateFCmpOLT(val, zero, "sgnlt");
                    llvm::Value* posOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1);
                    llvm::Value* negOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), -1, true);
                    llvm::Value* zeroInt = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                    llvm::Value* sel = m_builder->CreateSelect(isGt, posOne, zeroInt);
                    return m_builder->CreateSelect(isLt, negOne, sel, "sgntmp");
                } else if (val->getType()->isIntegerTy()) {
                    llvm::Value* zero = llvm::ConstantInt::get(val->getType(), 0);
                    llvm::Value* isGt = m_builder->CreateICmpSGT(val, zero, "sgngt");
                    llvm::Value* isLt = m_builder->CreateICmpSLT(val, zero, "sgnlt");
                    llvm::Value* posOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1);
                    llvm::Value* negOne = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), -1, true);
                    llvm::Value* zeroInt = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
                    llvm::Value* sel = m_builder->CreateSelect(isGt, posOne, zeroInt);
                    return m_builder->CreateSelect(isLt, negOne, sel, "sgntmp");
                }
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        if (lowerFn == "sqrt") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                val = coerceType(val, llvm::Type::getDoubleTy(*m_context));
                llvm::Function* sqrtFn = llvm::Intrinsic::getOrInsertDeclaration(m_module.get(), llvm::Intrinsic::sqrt, {llvm::Type::getDoubleTy(*m_context)});
                return m_builder->CreateCall(sqrtFn, {val}, "sqrttmp");
            }
            return llvm::ConstantFP::get(llvm::Type::getDoubleTy(*m_context), 0.0);
        }

        if (lowerFn == "int" || lowerFn == "floor") {
            if (!call->args.empty()) {
                llvm::Value* val = emitExpression(call->args[0].get());
                if (!val) return nullptr;
                if (val->getType()->isFloatingPointTy()) {
                    llvm::Function* floorFn = llvm::Intrinsic::getOrInsertDeclaration(m_module.get(), llvm::Intrinsic::floor, {val->getType()});
                    return m_builder->CreateCall(floorFn, {val}, "floortmp");
                }
                return val;
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        // Built-in Result Type Intrinsics: Ok(val), Err(code), IsOk(result)
        if (lowerFn == "ok" || lowerFn == "err" || lowerFn == "isok") {
            TypeSpec resSpec{"Result"};
            llvm::Type* resTy = getLlvmType(resSpec);
            if (lowerFn == "ok") {
                llvm::Value* val = nullptr;
                if (!call->args.empty()) {
                    val = emitExpression(call->args[0].get());
                    val = coerceType(val, llvm::Type::getInt64Ty(*m_context));
                } else {
                    val = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
                }
                llvm::Value* resVal = llvm::ConstantAggregateZero::get(resTy);
                resVal = m_builder->CreateInsertValue(resVal, llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1), 0, "res.ok.is_ok");
                resVal = m_builder->CreateInsertValue(resVal, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), 1, "res.ok.err");
                resVal = m_builder->CreateInsertValue(resVal, val, 2, "res.ok.val");
                return resVal;
            }
            if (lowerFn == "err") {
                llvm::Value* codeVal = nullptr;
                if (!call->args.empty()) {
                    codeVal = emitExpression(call->args[0].get());
                    codeVal = coerceType(codeVal, llvm::Type::getInt32Ty(*m_context));
                } else {
                    codeVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1);
                }
                llvm::Value* resVal = llvm::ConstantAggregateZero::get(resTy);
                resVal = m_builder->CreateInsertValue(resVal, llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0), 0, "res.err.is_ok");
                resVal = m_builder->CreateInsertValue(resVal, codeVal, 1, "res.err.err");
                resVal = m_builder->CreateInsertValue(resVal, llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0), 2, "res.err.val");
                return resVal;
            }
            if (lowerFn == "isok") {
                if (!call->args.empty()) {
                    llvm::Value* rVal = emitExpression(call->args[0].get());
                    if (rVal && rVal->getType() == resTy) {
                        return m_builder->CreateExtractValue(rVal, 0, "isok.val");
                    }
                    if (rVal && rVal->getType()->isPointerTy()) {
                        llvm::Value* okGep = m_builder->CreateStructGEP(resTy, rVal, 0, "isok.gep");
                        return m_builder->CreateLoad(llvm::Type::getInt1Ty(*m_context), okGep, "isok.load");
                    }
                }
                return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 0);
            }
        }

        // Built-in VB6 Err Object Method Calls: Err.Clear() & Err.Raise(...)
        bool isErrObj = false;
        std::string errMethod = "";
        if (call->calleeExpr) {
            if (auto baseVar = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                if (toLower(baseVar->name) == "err") {
                    isErrObj = true;
                    errMethod = toLower(call->funcName);
                }
            }
        } else if (lowerFn.rfind("err.", 0) == 0) {
            isErrObj = true;
            errMethod = lowerFn.substr(4);
        }

        if (isErrObj) {
            if (errMethod == "number") {
                return m_builder->CreateLoad(llvm::Type::getInt32Ty(*m_context), getOrCreateErrNumber(), "err.number");
            }
            if (errMethod == "source") {
                return m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), getOrCreateErrSource(), "err.source");
            }
            if (errMethod == "description") {
                return m_builder->CreateLoad(llvm::PointerType::get(*m_context, 0), getOrCreateErrDescription(), "err.description");
            }
            if (errMethod == "clear") {
                m_builder->CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), getOrCreateErrNumber());
                m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), getOrCreateErrSource());
                m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), getOrCreateErrDescription());
                return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
            }
            if (errMethod == "raise") {
                llvm::Value* numVal = nullptr;
                if (!call->args.empty()) {
                    numVal = emitExpression(call->args[0].get());
                    numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));
                } else {
                    numVal = llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 1);
                }
                m_builder->CreateStore(numVal, getOrCreateErrNumber());

                if (call->args.size() > 1) {
                    llvm::Value* srcVal = emitExpression(call->args[1].get());
                    srcVal = convertToString(srcVal);
                    m_builder->CreateStore(srcVal, getOrCreateErrSource());
                } else {
                    m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), getOrCreateErrSource());
                }

                if (call->args.size() > 2) {
                    llvm::Value* descVal = emitExpression(call->args[2].get());
                    descVal = convertToString(descVal);
                    m_builder->CreateStore(descVal, getOrCreateErrDescription());
                } else {
                    m_builder->CreateStore(llvm::ConstantPointerNull::get(llvm::PointerType::get(*m_context, 0)), getOrCreateErrDescription());
                }

                if (!m_tryErrAllocaStack.empty() && m_tryErrAllocaStack.back()) {
                    m_builder->CreateStore(numVal, m_tryErrAllocaStack.back());
                }

                if (!m_catchStack.empty()) {
                    m_builder->CreateBr(m_catchStack.back());
                    llvm::Function* currentFunc = m_builder->GetInsertBlock()->getParent();
                    llvm::BasicBlock* deadBB = llvm::BasicBlock::Create(*m_context, "after.raise", currentFunc);
                    m_builder->SetInsertPoint(deadBB);
                }
                return numVal;
            }
        }

        // Built-in LLB Print(msg) / PrintLine(msg) intrinsics
        if (lowerFn == "print" || lowerFn == "println" || lowerFn == "printline") {
            llvm::Function* printStrFn = getOrCreatePrintStr();
            std::vector<ExprASTNode*> allArgExprs;
            for (const auto& a : call->args) allArgExprs.push_back(a.get());
            for (const auto& na : call->namedArgs) allArgExprs.push_back(na.expr.get());

            for (size_t i = 0; i < allArgExprs.size(); ++i) {
                llvm::Value* val = emitExpression(allArgExprs[i]);
                if (val) {
                    llvm::Value* sVal = convertToString(val);
                    if (sVal) m_builder->CreateCall(printStrFn, {sVal});
                }
            }
            if (lowerFn != "print" || allArgExprs.empty()) {
                llvm::Value* nlStr = m_builder->CreateGlobalString("\n", "nl.s");
                m_builder->CreateCall(printStrFn, {nlStr});
            }
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0);
        }

        // Built-in LLB PrintF / PrintFormat (printf wrapper)
        if (lowerFn == "printf" || lowerFn == "printformat") {
            llvm::FunctionType* printfTy = llvm::FunctionType::get(
                llvm::Type::getInt32Ty(*m_context),
                {llvm::PointerType::get(*m_context, 0)},
                true // varargs
            );
            llvm::Function* callee = m_module->getFunction("printf");
            if (!callee) {
                callee = llvm::Function::Create(printfTy, llvm::Function::ExternalLinkage, "printf", m_module.get());
            }

            std::vector<ExprASTNode*> allArgExprs;
            for (const auto& a : call->args) allArgExprs.push_back(a.get());
            for (const auto& na : call->namedArgs) allArgExprs.push_back(na.expr.get());

            std::vector<llvm::Value*> args;
            for (size_t i = 0; i < allArgExprs.size(); ++i) {
                llvm::Value* argVal = emitExpression(allArgExprs[i]);
                if (i == 0) {
                    argVal = coerceType(argVal, llvm::PointerType::get(*m_context, 0));
                }
                args.push_back(argVal);
            }

            if (args.empty()) {
                args.push_back(m_builder->CreateGlobalString("", "fmt.empty"));
            }

            // Always call with proper variadic function type signature
            return m_builder->CreateCall(printfTy, callee, args, "printftmp");
        }

        // Built-in File Functions: EOF(filenum) & LOF(filenum)
        if (lowerFn == "eof") {
            if (!call->args.empty()) {
                llvm::Value* numVal = emitExpression(call->args[0].get());
                if (!numVal) return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
                numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));
                llvm::Function* eofFn = getOrCreateFileEof();
                return m_builder->CreateCall(eofFn, {numVal}, "eof.res");
            }
            return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), 1);
        }

        if (lowerFn == "lof") {
            if (!call->args.empty()) {
                llvm::Value* numVal = emitExpression(call->args[0].get());
                if (!numVal) return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
                numVal = coerceType(numVal, llvm::Type::getInt32Ty(*m_context));
                llvm::Function* lofFn = getOrCreateFileLof();
                return m_builder->CreateCall(lofFn, {numVal}, "lof.res");
            }
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
        }

        std::string targetFuncName = call->funcName;
        bool isQualifiedModuleCall = false;
        // If calleeExpr is a chain of identifiers (e.g. Drivers.Terminal), reconstruct the qualified name
        if (call->calleeExpr) {
            std::function<std::string(ExprASTNode*)> getDottedPrefix = [&](ExprASTNode* e) -> std::string {
                if (auto v = dynamic_cast<VariableExprASTNode*>(e)) return v->name;
                if (auto m = dynamic_cast<MemberAccessExprASTNode*>(e)) {
                    std::string p = getDottedPrefix(m->base.get());
                    return p.empty() ? m->memberName : (p + "." + m->memberName);
                }
                return "";
            };
            std::string dotted = getDottedPrefix(call->calleeExpr.get());
            if (!dotted.empty()) {
                // If dotted prefix is NOT a local variable or struct instance, treat as qualified module call
                if (m_namedValues.find(dotted) == m_namedValues.end() && 
                    m_namedValues.find(dotted.substr(0, dotted.find('.'))) == m_namedValues.end()) {
                    targetFuncName = dotted + "." + call->funcName;
                    isQualifiedModuleCall = true;
                }
            }
        }

        if (!isQualifiedModuleCall && call->calleeExpr) {
            TypeSpec calleeType = deduceExprType(call->calleeExpr.get());
            if (calleeType.name.empty()) {
                if (auto varBase = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                    auto tIt = m_variableTypes.find(varBase->name);
                    if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(varBase->name));
                    if (tIt != m_variableTypes.end()) calleeType = tIt->second;
                }
            }
            if (!calleeType.name.empty()) {
                std::string typeName = calleeType.name;
                std::string cand1 = typeName + "." + call->funcName;
                std::string cand2 = typeName + "_" + call->funcName;
                if (m_funcAliases.count(cand1)) {
                    targetFuncName = m_funcAliases[cand1];
                } else if (m_funcAliases.count(toLower(cand1))) {
                    targetFuncName = m_funcAliases[toLower(cand1)];
                } else if (m_funcAliases.count(cand2)) {
                    targetFuncName = m_funcAliases[cand2];
                } else if (m_funcAliases.count(toLower(cand2))) {
                    targetFuncName = m_funcAliases[toLower(cand2)];
                } else if (findFunctionCaseInsensitive(m_module.get(), cand2)) {
                    targetFuncName = cand2;
                } else if (findFunctionCaseInsensitive(m_module.get(), cand1)) {
                    targetFuncName = cand1;
                } else {
                    auto aIt = m_funcAliases.find(typeName);
                    if (aIt != m_funcAliases.end()) {
                        std::string baseCls = aIt->second;
                        std::string candBase = baseCls + "_" + call->funcName;
                        if (findFunctionCaseInsensitive(m_module.get(), candBase)) {
                            targetFuncName = candBase;
                        }
                    }
                }
            }
        }

        if (!call->typeArgs.empty()) {
            targetFuncName = instantiateGenericProcedure(targetFuncName, call->typeArgs);
        } else if (m_genericProcTemplates.find(targetFuncName) != m_genericProcTemplates.end() ||
                   m_genericProcTemplates.find(toLower(targetFuncName)) != m_genericProcTemplates.end()) {
            // Infer type arguments from call arguments if not explicitly provided
            std::vector<TypeSpec> inferredTypeArgs;
            for (const auto& a : call->args) {
                inferredTypeArgs.push_back(deduceExprType(a.get()));
            }
            if (!inferredTypeArgs.empty()) {
                targetFuncName = instantiateGenericProcedure(targetFuncName, inferredTypeArgs);
            }
        }

        auto aliasIt = m_funcAliases.find(targetFuncName);
        if (aliasIt != m_funcAliases.end()) {
            targetFuncName = aliasIt->second;
        }
        llvm::Function* callee = findFunctionCaseInsensitive(m_module.get(), targetFuncName);


        // Auto-declare standard C library functions if not already declared
        if (!callee) {
            if (call->funcName == "puts") {
                llvm::FunctionType* putsTy = llvm::FunctionType::get(
                    llvm::Type::getInt32Ty(*m_context),
                    {llvm::PointerType::get(*m_context, 0)},
                    false
                );
                callee = llvm::Function::Create(putsTy, llvm::Function::ExternalLinkage, "puts", m_module.get());
            } else if (call->funcName == "printf") {
                llvm::FunctionType* printfTy = llvm::FunctionType::get(
                    llvm::Type::getInt32Ty(*m_context),
                    {llvm::PointerType::get(*m_context, 0)},
                    true // varargs
                );
                callee = llvm::Function::Create(printfTy, llvm::Function::ExternalLinkage, "printf", m_module.get());
            }
        }

        if (!callee) {
            // Check if this is a Property Get call (e.g. BaudRate() -> get_BaudRate())
            std::string getPropName = "get_" + targetFuncName;
            callee = findFunctionCaseInsensitive(m_module.get(), getPropName);
            if (!callee) {
                for (const auto& pair : m_structTypes) {
                    std::string cand = pair.first + "_get_" + targetFuncName;
                    callee = findFunctionCaseInsensitive(m_module.get(), cand);
                    if (callee) break;
                }
            }
        }

        if (!callee) {
            // Check if targetFuncName contains '.' (e.g. MathOps.Add or Core.IO.Write)
            size_t dotPos = targetFuncName.find('.');
            if (dotPos != std::string::npos) {
                std::string altName = targetFuncName;
                for (auto& ch : altName) {
                    if (ch == '.') ch = '_';
                }
                callee = findFunctionCaseInsensitive(m_module.get(), altName);
            } else if (m_module && m_module->getName().str().find('.') != std::string::npos) {
                // Intra-module call in dotted module (e.g. MakeAttribute in Drivers.Terminal -> Drivers_Terminal_MakeAttribute)
                std::string modPref = m_module->getName().str();
                for (auto& ch : modPref) {
                    if (ch == '.') ch = '_';
                }
                callee = findFunctionCaseInsensitive(m_module.get(), modPref + "_" + targetFuncName);
            }
        }

        if (!callee) {
            // Indirect function pointer call: e.g. fnPtr(arg1, arg2)
            llvm::Value* fnPtrVal = nullptr;
            auto it = m_namedValues.find(targetFuncName);
            if (it == m_namedValues.end()) it = m_namedValues.find(toLower(targetFuncName));
            if (it != m_namedValues.end()) {
                fnPtrVal = m_builder->CreateLoad(it->second->getAllocatedType(), it->second, targetFuncName + ".fnptr");
            } else if (call->calleeExpr) {
                TypeSpec cType = deduceExprType(call->calleeExpr.get());
                if (auto vb = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                    auto vIt = m_variableTypes.find(vb->name);
                    if (vIt != m_variableTypes.end()) cType = vIt->second;
                }
                if (m_structTypes.find(cType.name) == m_structTypes.end() &&
                    m_structTypes.find(toLower(cType.name)) == m_structTypes.end()) {
                    fnPtrVal = emitExpression(call->calleeExpr.get());
                }
            }

            if (fnPtrVal) {
                if (fnPtrVal->getType()->isIntegerTy()) {
                    fnPtrVal = m_builder->CreateIntToPtr(fnPtrVal, llvm::PointerType::get(*m_context, 0), "fnptr.cast");
                }
            }

            if (fnPtrVal && fnPtrVal->getType()->isPointerTy()) {
                std::vector<llvm::Value*> args;
                std::vector<llvm::Type*> paramTypes;
                for (const auto& a : call->args) {
                    llvm::Value* argVal = emitExpression(a.get());
                    args.push_back(argVal);
                    paramTypes.push_back(argVal->getType());
                }
                llvm::Type* retType = llvm::Type::getInt32Ty(*m_context);
                auto pIt = m_procReturnTypes.find(targetFuncName);
                if (pIt != m_procReturnTypes.end()) {
                    retType = getLlvmType(pIt->second);
                } else {
                    auto pItLower = m_procReturnTypes.find(toLower(targetFuncName));
                    if (pItLower != m_procReturnTypes.end()) {
                        retType = getLlvmType(pItLower->second);
                    }
                }
                llvm::FunctionType* fnTy = llvm::FunctionType::get(retType, paramTypes, false);
                return m_builder->CreateCall(fnTy, fnPtrVal, args, "indirect.call");
            }

            if (!isQualifiedModuleCall && call->calleeExpr) {
                TypeSpec calleeType = deduceExprType(call->calleeExpr.get());
                if (calleeType.name.empty()) {
                    if (auto varBase = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                        auto tIt = m_variableTypes.find(varBase->name);
                        if (tIt == m_variableTypes.end()) tIt = m_variableTypes.find(toLower(varBase->name));
                        if (tIt != m_variableTypes.end()) calleeType = tIt->second;
                    }
                }
                std::string targetType = !calleeType.name.empty() ? calleeType.name : "Type";
                Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                   call->column > 0 ? call->column : m_currentCol,
                                   true, "Type '" + targetType + "' has no method or member named '" + call->funcName + "'.", m_sourceText);
            } else {
                Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                   call->column > 0 ? call->column : m_currentCol,
                                   true, "Undeclared function or subroutine '" + targetFuncName + "'.", m_sourceText);
            }
            m_hadError = true;
            return nullptr;
        }

        std::vector<llvm::Value*> args;
        if (!isQualifiedModuleCall && call->calleeExpr && callee->getFunctionType()->getNumParams() == call->args.size() + 1) {
            std::string instanceName = "";
            if (auto varNode = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                instanceName = varNode->name;
            }
            if (!instanceName.empty()) {
                std::string lowerInst = toLower(instanceName);
                if (toLower(call->funcName) == "initialize") {
                    m_initializedObjects.insert(lowerInst);
                } else if (!m_initializedObjects.count(lowerInst)) {
                    // Check if variable is a Class type with an Initialize constructor
                    auto tIt = m_variableTypes.find(instanceName);
                    if (tIt != m_variableTypes.end()) {
                        std::string initFuncUnderscore = tIt->second.name + "_Initialize";
                        for (auto& ch : initFuncUnderscore) if (ch == '.') ch = '_';
                        std::string initFuncDot = tIt->second.name + ".Initialize";
                        std::string targetInit = initFuncUnderscore;
                        if (m_funcAliases.count(initFuncUnderscore)) targetInit = m_funcAliases[initFuncUnderscore];
                        else if (m_funcAliases.count(toLower(initFuncUnderscore))) targetInit = m_funcAliases[toLower(initFuncUnderscore)];
                        else if (m_funcAliases.count(initFuncDot)) targetInit = m_funcAliases[initFuncDot];
                        else if (m_funcAliases.count(toLower(initFuncDot))) targetInit = m_funcAliases[toLower(initFuncDot)];

                        if (findFunctionCaseInsensitive(m_module.get(), initFuncUnderscore) ||
                            findFunctionCaseInsensitive(m_module.get(), initFuncDot) ||
                            findFunctionCaseInsensitive(m_module.get(), targetInit)) {
                            throw std::runtime_error("Object '" + instanceName + "' of class '" + tIt->second.name + "' is used before being initialized. Call '" + instanceName + ".Initialize(...)' first.");
                        }
                    }
                }
            }

            llvm::Value* thisPtr = getPointerToExpr(call->calleeExpr.get());
            args.push_back(thisPtr);
        } else if (callee->getFunctionType()->getNumParams() == call->args.size() + 1) {
            // Check if calling a method directly on a Global or SingleUse Class singleton
            std::string prefixClass = "";
            if (call->calleeExpr) {
                if (auto v = dynamic_cast<VariableExprASTNode*>(call->calleeExpr.get())) {
                    prefixClass = v->name;
                }
            } else {
                size_t dotPos = targetFuncName.rfind('.');
                if (dotPos != std::string::npos) {
                    prefixClass = targetFuncName.substr(0, dotPos);
                }
            }
            if (!prefixClass.empty()) {
                auto sIt = m_classSingletons.find(prefixClass);
                if (sIt == m_classSingletons.end()) sIt = m_classSingletons.find(toLower(prefixClass));
                if (sIt != m_classSingletons.end()) {
                    args.push_back(sIt->second);
                }
            }
        }

        // If named arguments are used in call->namedArgs
        if (!call->namedArgs.empty()) {
            auto nameIt = m_procParamNames.find(targetFuncName);
            if (nameIt == m_procParamNames.end() && targetFuncName != call->funcName) {
                nameIt = m_procParamNames.find(call->funcName);
            }
            size_t totalExpected = callee->getFunctionType()->getNumParams();
            std::vector<ExprASTNode*> mappedExprs(totalExpected, nullptr);
            size_t posIdx = (args.size() > 0 ? 1 : 0);
            for (const auto& posExpr : call->args) {
                if (posIdx < totalExpected) {
                    mappedExprs[posIdx++] = posExpr.get();
                }
            }

            for (const auto& carg : call->namedArgs) {
                std::string lowerArg = toLower(carg.name);
                if (nameIt != m_procParamNames.end()) {
                    for (size_t p = 0; p < nameIt->second.size() && p < totalExpected; ++p) {
                        if (toLower(nameIt->second[p]) == lowerArg) {
                            mappedExprs[p] = carg.expr.get();
                            break;
                        }
                    }
                }
            }

            // Fill in arguments from mappedExprs or defaults
            auto defIt = m_procDefaults.find(targetFuncName);
            if (defIt == m_procDefaults.end() && targetFuncName != call->funcName) {
                defIt = m_procDefaults.find(call->funcName);
            }

            for (size_t p = args.size(); p < totalExpected; ++p) {
                ExprASTNode* exprNode = mappedExprs[p];
                if (!exprNode && defIt != m_procDefaults.end() && p < defIt->second.size()) {
                    exprNode = defIt->second[p];
                }
                llvm::Value* aVal = nullptr;
                if (exprNode) {
                    llvm::Type* pTy = callee->getFunctionType()->getParamType(p);
                    if (pTy->isPointerTy()) {
                        aVal = getPointerToExpr(exprNode);
                    }
                    if (!aVal) {
                        aVal = emitExpression(exprNode);
                    }
                }
                if (!aVal) {
                    llvm::Type* pTy = callee->getFunctionType()->getParamType(p);
                    if (pTy->isFloatingPointTy()) {
                        aVal = llvm::ConstantFP::get(pTy, 0.0);
                    } else if (pTy->isPointerTy()) {
                        aVal = llvm::Constant::getNullValue(pTy);
                    } else {
                        aVal = llvm::ConstantInt::get(pTy, 0);
                    }
                } else {
                    aVal = coerceType(aVal, callee->getFunctionType()->getParamType(p));
                }
                args.push_back(aVal);
            }
        } else {
            // Check if callee has ParamArray in last parameter
            bool isParamArrayProc = false;
            auto paIt = m_procParamArray.find(targetFuncName);
            if (paIt != m_procParamArray.end() && paIt->second) isParamArrayProc = true;
            if (!isParamArrayProc && targetFuncName != call->funcName) {
                auto paIt2 = m_procParamArray.find(call->funcName);
                if (paIt2 != m_procParamArray.end() && paIt2->second) isParamArrayProc = true;
            }

            size_t numParams = callee->getFunctionType()->getNumParams();
            if (isParamArrayProc && numParams > 0 && call->args.size() >= numParams - 1) {
                // Positional arguments before ParamArray
                size_t regularCount = numParams - 1;
                for (size_t i = 0; i < regularCount && i < call->args.size(); ++i) {
                    llvm::Value* argVal = emitExpression(call->args[i].get());
                    argVal = coerceType(argVal, callee->getFunctionType()->getParamType(args.size()));
                    args.push_back(argVal);
                }

                // Pack trailing arguments into a dynamic array buffer
                size_t varargCount = (call->args.size() >= regularCount) ? (call->args.size() - regularCount) : 0;
                llvm::Function* mallocFn = getOrCreateMalloc();
                llvm::Value* bufSize = llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), (varargCount + 1) * sizeof(uint64_t));
                llvm::Value* rawBuf = m_builder->CreateCall(mallocFn, {bufSize}, "paramarray.buf");

                for (size_t i = 0; i < varargCount; ++i) {
                    llvm::Value* elemVal = emitExpression(call->args[regularCount + i].get());
                    elemVal = coerceType(elemVal, llvm::Type::getInt64Ty(*m_context));
                    llvm::Value* slotPtr = m_builder->CreateGEP(
                        llvm::Type::getInt64Ty(*m_context),
                        rawBuf,
                        llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), i),
                        "pa.slot"
                    );
                    m_builder->CreateStore(elemVal, slotPtr);
                }
                llvm::Value* typedBuf = coerceType(rawBuf, callee->getFunctionType()->getParamType(args.size()));
                args.push_back(typedBuf);
            } else {
                std::string calleeName = callee->getName().str();
                auto byRefIt = m_procParamByRef.find(calleeName);
                if (byRefIt == m_procParamByRef.end()) {
                    byRefIt = m_procParamByRef.find(toLower(calleeName));
                }
                if (byRefIt == m_procParamByRef.end()) {
                    byRefIt = m_procParamByRef.find(targetFuncName);
                }
                if (byRefIt == m_procParamByRef.end()) {
                    byRefIt = m_procParamByRef.find(toLower(targetFuncName));
                }
                if (byRefIt == m_procParamByRef.end() && targetFuncName != call->funcName) {
                    byRefIt = m_procParamByRef.find(call->funcName);
                }
                if (byRefIt == m_procParamByRef.end() && targetFuncName != call->funcName) {
                    byRefIt = m_procParamByRef.find(toLower(call->funcName));
                }

                for (size_t i = 0; i < call->args.size(); ++i) {
                    llvm::Value* argVal = nullptr;
                    size_t paramIdx = args.size();
                    bool isByRefParam = false;
                    if (byRefIt != m_procParamByRef.end() && i < byRefIt->second.size()) {
                        isByRefParam = byRefIt->second[i];
                    }
                    if (isByRefParam) {
                        argVal = getPointerToExpr(call->args[i].get());
                    }
                    if (!argVal) {
                        argVal = emitExpression(call->args[i].get());
                    }
                    if (paramIdx < callee->getFunctionType()->getNumParams()) {
                        argVal = coerceType(argVal, callee->getFunctionType()->getParamType(paramIdx));
                    }
                    args.push_back(argVal);
                }
            }
        }

        // Fill in omitted optional arguments with their default values
        auto defIt = m_procDefaults.find(targetFuncName);
        if (defIt == m_procDefaults.end() && targetFuncName != call->funcName) {
            defIt = m_procDefaults.find(call->funcName);
        }
        if (defIt != m_procDefaults.end()) {
            const auto& defVec = defIt->second;
            while (args.size() < callee->getFunctionType()->getNumParams() && args.size() < defVec.size()) {
                size_t paramIdx = args.size();
                ExprASTNode* defExpr = defVec[paramIdx];
                if (!defExpr) {
                    // This parameter is required (not optional) - do not invent default argument
                    break;
                }
                llvm::Value* defVal = emitExpression(defExpr);
                if (!defVal) {
                    llvm::Type* pTy = callee->getFunctionType()->getParamType(paramIdx);
                    if (pTy->isFloatingPointTy()) {
                        defVal = llvm::ConstantFP::get(pTy, 0.0);
                    } else if (pTy->isPointerTy()) {
                        defVal = llvm::ConstantPointerNull::get(llvm::cast<llvm::PointerType>(pTy));
                    } else {
                        defVal = llvm::ConstantInt::get(pTy, 0);
                    }
                } else {
                    defVal = coerceType(defVal, callee->getFunctionType()->getParamType(paramIdx));
                }
                args.push_back(defVal);
            }
        }

        if (!callee->isVarArg()) {
            size_t expectedParams = callee->getFunctionType()->getNumParams();
            if (args.size() != expectedParams) {
                Diagnostic::report(m_sourceFilePath, call->line > 0 ? call->line : m_currentLine,
                                   call->column > 0 ? call->column : m_currentCol,
                                   true, "Procedure '" + targetFuncName + "' expects " +
                                   std::to_string(expectedParams) + " argument(s), but " +
                                   std::to_string(args.size()) + " were supplied.", m_sourceText);
                m_hadError = true;
                return nullptr;
            }
        }

        return m_builder->CreateCall(callee, args);
    }

    // Binary Expressions
    if (auto bin = dynamic_cast<BinaryExprASTNode*>(expr)) {
        std::string op = bin->op;
        for (auto& c : op) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        // String Concatenation:
        // 1. Operator '&' is ALWAYS string concatenation (VB6 semantics)
        // 2. Operator '+' is string concatenation if either side is a String expression
        if (op == "&" || (op == "+" && (isStringExpr(bin->lhs.get()) || isStringExpr(bin->rhs.get())))) {
            llvm::Value* l = emitExpression(bin->lhs.get());
            llvm::Value* r = emitExpression(bin->rhs.get());
            if (!l || !r) return nullptr;
            return concatStrings(l, r);
        }

        // String Equality / Inequality Comparison:
        if ((isStringExpr(bin->lhs.get()) || isStringExpr(bin->rhs.get())) && (op == "=" || op == "<>")) {
            llvm::Value* l = emitExpression(bin->lhs.get());
            llvm::Value* r = emitExpression(bin->rhs.get());
            if (!l || !r) return nullptr;
            l = convertToString(l);
            r = convertToString(r);
            llvm::Function* strcmpFn = getOrCreateStrcmp();
            llvm::Value* cmpRes = m_builder->CreateCall(strcmpFn, {l, r}, "strcmp");
            if (op == "=") {
                return m_builder->CreateICmpEQ(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "streq");
            } else {
                return m_builder->CreateICmpNE(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "strne");
            }
        }

        // Like String Pattern Matching:
        if (op == "like") {
            llvm::Value* l = emitExpression(bin->lhs.get());
            llvm::Value* r = emitExpression(bin->rhs.get());
            if (!l || !r) return nullptr;
            l = convertToString(l);
            r = convertToString(r);
            llvm::Function* likeFn = getOrCreateLikeMatch();
            return m_builder->CreateCall(likeFn, {l, r}, "likeres");
        }

        llvm::Value* l = emitExpression(bin->lhs.get());
        llvm::Value* r = emitExpression(bin->rhs.get());
        if (!l || !r) return nullptr;

        // Floating-Point Operations
        if (l->getType()->isFloatingPointTy() || r->getType()->isFloatingPointTy()) {
            llvm::Type* fpType = (l->getType()->isDoubleTy() || r->getType()->isDoubleTy())
                ? llvm::Type::getDoubleTy(*m_context)
                : llvm::Type::getFloatTy(*m_context);
            l = coerceType(l, fpType);
            r = coerceType(r, fpType);

            if (op == "+") return m_builder->CreateFAdd(l, r, "fadd");
            if (op == "-") return m_builder->CreateFSub(l, r, "fsub");
            if (op == "*") return m_builder->CreateFMul(l, r, "fmul");
            if (op == "/") return m_builder->CreateFDiv(l, r, "fdiv");

            if (op == "=")  return m_builder->CreateFCmpOEQ(l, r, "feq");
            if (op == "<>") return m_builder->CreateFCmpONE(l, r, "fne");
            if (op == "<")  return m_builder->CreateFCmpOLT(l, r, "flt");
            if (op == "<=") return m_builder->CreateFCmpOLE(l, r, "fle");
            if (op == ">")  return m_builder->CreateFCmpOGT(l, r, "fgt");
            if (op == ">=") return m_builder->CreateFCmpOGE(l, r, "fge");
        }

        // Pointer Arithmetic: ptr + offset or ptr - offset
        if (l->getType()->isPointerTy() && r->getType()->isIntegerTy()) {
            if (op == "+") {
                return m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), l, r, "ptradd");
            } else if (op == "-") {
                llvm::Value* negR = m_builder->CreateNeg(r, "ptrneg");
                return m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), l, negR, "ptrsub");
            } else if (op == "=" || op == "<>") {
                r = coerceType(r, l->getType());
            }
        }
        if (l->getType()->isIntegerTy() && r->getType()->isPointerTy()) {
            if (op == "+") {
                return m_builder->CreateGEP(llvm::Type::getInt8Ty(*m_context), r, l, "ptradd");
            } else if (op == "=" || op == "<>") {
                l = coerceType(l, r->getType());
            }
        }
        if (l->getType()->isPointerTy() && r->getType()->isPointerTy()) {
            // Both are pointers
            if (op == "=" || op == "<>") {
                TypeSpec lType = deduceExprType(bin->lhs.get());
                TypeSpec rType = deduceExprType(bin->rhs.get());
                if ((toLower(lType.name) == "string" && lType.pointerDepth == 0 && !lType.isArray) ||
                    (toLower(rType.name) == "string" && rType.pointerDepth == 0 && !rType.isArray)) {
                    l = convertToString(l);
                    r = convertToString(r);
                    llvm::Function* strcmpFn = getOrCreateStrcmp();
                    llvm::Value* cmpRes = m_builder->CreateCall(strcmpFn, {l, r}, "strcmp");
                    if (op == "=") {
                        return m_builder->CreateICmpEQ(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "streq");
                    } else {
                        return m_builder->CreateICmpNE(cmpRes, llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0), "strne");
                    }
                }
                if (op == "=")  return m_builder->CreateICmpEQ(l, r, "ptreq");
                if (op == "<>") return m_builder->CreateICmpNE(l, r, "ptrne");
            }
        }

        bool isUnsigned = isUnsignedExpr(bin->lhs.get()) || isUnsignedExpr(bin->rhs.get());

        // Equalize integer bitwidths
        if (l->getType()->isIntegerTy() && r->getType()->isIntegerTy()) {
            unsigned lBits = l->getType()->getIntegerBitWidth();
            unsigned rBits = r->getType()->getIntegerBitWidth();
            if (lBits < rBits) {
                l = isUnsigned ? m_builder->CreateZExt(l, r->getType(), "zext") : m_builder->CreateSExt(l, r->getType(), "sext");
            } else if (rBits < lBits) {
                r = isUnsigned ? m_builder->CreateZExt(r, l->getType(), "zext") : m_builder->CreateSExt(r, l->getType(), "sext");
            }
        }

        if (op == "+") return m_builder->CreateAdd(l, r, "addtmp");
        if (op == "-") return m_builder->CreateSub(l, r, "subtmp");
        if (op == "*") return m_builder->CreateMul(l, r, "multmp");
        if (op == "/") {
            if (auto numR = dynamic_cast<NumberExprASTNode*>(bin->rhs.get())) {
                if (!numR->isFloat && numR->val == 0) {
                    Diagnostic::report(m_sourceFilePath, bin->line > 0 ? bin->line : m_currentLine,
                                       bin->column > 0 ? bin->column : m_currentCol,
                                       true, "Division by zero at compile time in operator '" + bin->op + "'.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
            }
            if (!m_currentProcIsUnsafe && l->getType()->isIntegerTy()) {
                emitZeroDivCheck(r, "/");
            }
            return isUnsigned ? m_builder->CreateUDiv(l, r, "udivtmp") : m_builder->CreateSDiv(l, r, "sdivtmp");
        }
        if (op == "mod") {
            if (auto numR = dynamic_cast<NumberExprASTNode*>(bin->rhs.get())) {
                if (!numR->isFloat && numR->val == 0) {
                    Diagnostic::report(m_sourceFilePath, bin->line > 0 ? bin->line : m_currentLine,
                                       bin->column > 0 ? bin->column : m_currentCol,
                                       true, "Division by zero at compile time in operator '" + bin->op + "'.", m_sourceText);
                    m_hadError = true;
                    return nullptr;
                }
            }
            if (!m_currentProcIsUnsafe && l->getType()->isIntegerTy()) {
                emitZeroDivCheck(r, "Mod");
            }
            return isUnsigned ? m_builder->CreateURem(l, r, "umodtmp") : m_builder->CreateSRem(l, r, "smodtmp");
        }

        if (op == "and") return m_builder->CreateAnd(l, r, "andtmp");
        if (op == "or")  return m_builder->CreateOr(l, r, "ortmp");
        if (op == "xor") return m_builder->CreateXor(l, r, "xortmp");
        if (op == "lshift" || op == "rshift") {
            if (auto numR = dynamic_cast<NumberExprASTNode*>(bin->rhs.get())) {
                if (!numR->isFloat) {
                    unsigned bitWidth = l->getType()->isIntegerTy() ? l->getType()->getIntegerBitWidth() : 64;
                    if (numR->val < 0 || static_cast<uint64_t>(numR->val) >= bitWidth) {
                        Diagnostic::report(m_sourceFilePath, bin->line > 0 ? bin->line : m_currentLine,
                                           bin->column > 0 ? bin->column : m_currentCol,
                                           true, "Shift count " + std::to_string(numR->val) + " is out of range for integer of width " + std::to_string(bitWidth) + " [0.." + std::to_string(bitWidth - 1) + "].", m_sourceText);
                        m_hadError = true;
                        return nullptr;
                    }
                }
            }
            if (op == "lshift") return m_builder->CreateShl(l, r, "shltmp");
            return isUnsigned ? m_builder->CreateLShr(l, r, "lshrtmp") : m_builder->CreateAShr(l, r, "ashrtmp");
        }

        if (op == "=")  return m_builder->CreateICmpEQ(l, r, "eqtmp");
        if (op == "<>") return m_builder->CreateICmpNE(l, r, "netmp");
        if (op == "<") {
            return isUnsigned ? m_builder->CreateICmpULT(l, r, "ulttmp") : m_builder->CreateICmpSLT(l, r, "slttmp");
        }
        if (op == "<=") {
            return isUnsigned ? m_builder->CreateICmpULE(l, r, "uletmp") : m_builder->CreateICmpSLE(l, r, "sletmp");
        }
        if (op == ">") {
            return isUnsigned ? m_builder->CreateICmpUGT(l, r, "ugttmp") : m_builder->CreateICmpSGT(l, r, "sgttmp");
        }
        if (op == ">=") {
            return isUnsigned ? m_builder->CreateICmpUGE(l, r, "ugetmp") : m_builder->CreateICmpSGE(l, r, "sgetmp");
        }
    }

    // Unary Expressions
    if (auto un = dynamic_cast<UnaryExprASTNode*>(expr)) {
        llvm::Value* val = emitExpression(un->expr.get());
        if (!val) return nullptr;
        if (un->op == "Not" || un->op == "not") {
            return m_builder->CreateNot(val, "nottmp");
        }
        if (un->op == "-") {
            if (val->getType()->isFloatingPointTy()) {
                return m_builder->CreateFNeg(val, "fnegtmp");
            }
            return m_builder->CreateNeg(val, "negtmp");
        }
    }

    // TypeOf expr Is [Not] TargetType
    if (auto typeOfNode = dynamic_cast<TypeOfExprASTNode*>(expr)) {
        TypeSpec actualType = deduceExprType(typeOfNode->targetExpr.get());
        bool matches = false;

        std::string actualName = toLower(actualType.name);
        std::string targetName = toLower(typeOfNode->targetType.name);

        if (actualName == "long") actualName = "int32";
        if (targetName == "long") targetName = "int32";
        if (actualName == "int") actualName = "int32";
        if (targetName == "int") targetName = "int32";

        if (actualName == targetName &&
            actualType.pointerDepth == typeOfNode->targetType.pointerDepth &&
            actualType.isArray == typeOfNode->targetType.isArray) {
            matches = true;
        }

        if (typeOfNode->isNot) {
            matches = !matches;
        }

        return llvm::ConstantInt::get(llvm::Type::getInt1Ty(*m_context), matches ? 1 : 0);
    }

    // First-Class Lambda / Closure Expression: Function(params) [As Type] => expr
    if (auto lambda = dynamic_cast<LambdaExprASTNode*>(expr)) {
        static size_t lambdaCounter = 0;
        std::string lambdaName = "__llbc_lambda_" + std::to_string(++lambdaCounter);

        llvm::Type* retTy = getLlvmType(lambda->returnType);
        std::vector<llvm::Type*> paramTypes;
        for (const auto& p : lambda->parameters) {
            paramTypes.push_back(getLlvmType(p.type));
        }

        llvm::FunctionType* fnTy = llvm::FunctionType::get(retTy, paramTypes, false);
        llvm::Function* lambdaFn = llvm::Function::Create(
            fnTy,
            llvm::Function::InternalLinkage,
            lambdaName,
            m_module.get()
        );

        // Save current builder context
        auto prevBB = m_builder->GetInsertBlock();
        auto prevPoint = m_builder->GetInsertPoint();
        auto savedNamedValues = m_namedValues;
        auto savedVariableTypes = m_variableTypes;

        llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", lambdaFn);
        m_builder->SetInsertPoint(entryBB);

        size_t pIdx = 0;
        for (auto& arg : lambdaFn->args()) {
            if (pIdx < lambda->parameters.size()) {
                const auto& param = lambda->parameters[pIdx];
                arg.setName(param.name);
                llvm::AllocaInst* pAlloca = m_builder->CreateAlloca(arg.getType(), nullptr, param.name);
                m_builder->CreateStore(&arg, pAlloca);
                m_namedValues[param.name] = pAlloca;
                m_namedValues[toLower(param.name)] = pAlloca;
                m_variableTypes[param.name] = param.type;
                m_variableTypes[toLower(param.name)] = param.type;
            }
            pIdx++;
        }

        llvm::Value* bodyVal = emitExpression(lambda->bodyExpr.get());
        if (bodyVal) {
            bodyVal = coerceType(bodyVal, retTy);
            m_builder->CreateRet(bodyVal);
        } else {
            if (retTy->isVoidTy()) {
                m_builder->CreateRetVoid();
            } else {
                m_builder->CreateRet(llvm::Constant::getNullValue(retTy));
            }
        }

        // Restore outer function context
        m_namedValues = savedNamedValues;
        m_variableTypes = savedVariableTypes;
        if (prevBB) {
            m_builder->SetInsertPoint(prevBB, prevPoint);
        }

        // Return lambda function pointer as opaque pointer
        return m_builder->CreatePointerCast(lambdaFn, llvm::PointerType::get(*m_context, 0), "lambda.ptr");
    }

    if (auto sz = dynamic_cast<SizeOfExprASTNode*>(expr)) {
        llvm::Type* targetTy = getLlvmType(sz->targetType);
        const llvm::DataLayout& dl = m_module->getDataLayout();
        uint64_t typeSize = dl.getTypeAllocSize(targetTy);
        return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), typeSize);
    }

    if (auto off = dynamic_cast<OffsetOfExprASTNode*>(expr)) {
        std::string structName = off->targetType.name;
        auto stIt = m_structTypes.find(structName);
        if (stIt == m_structTypes.end()) stIt = m_structTypes.find(toLower(structName));
        if (stIt == m_structTypes.end() || !stIt->second) {
            Diagnostic::report(m_sourceFilePath, m_currentLine, m_currentCol, true,
                               "Cannot find structure '" + structName + "' in OffsetOf.", m_sourceText);
            m_hadError = true;
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
        }
        llvm::StructType* stTy = stIt->second;
        std::string fieldLower = toLower(off->fieldName);
        auto fIt = m_structFieldIndices[structName].find(fieldLower);
        if (fIt == m_structFieldIndices[structName].end()) {
            fIt = m_structFieldIndices[toLower(structName)].find(fieldLower);
        }
        if (fIt == m_structFieldIndices[structName].end() && fIt == m_structFieldIndices[toLower(structName)].end()) {
            Diagnostic::report(m_sourceFilePath, m_currentLine, m_currentCol, true,
                               "Structure '" + structName + "' has no member named '" + off->fieldName + "' in OffsetOf.", m_sourceText);
            m_hadError = true;
            return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), 0);
        }
        unsigned fieldIdx = fIt->second;
        const llvm::DataLayout& dl = m_module->getDataLayout();
        const llvm::StructLayout* sl = dl.getStructLayout(stTy);
        uint64_t fieldOffset = sl->getElementOffset(fieldIdx);
        return llvm::ConstantInt::get(llvm::Type::getInt64Ty(*m_context), fieldOffset);
    }

    return nullptr;
}

void LlvmEmitter::registerExternalProcedure(const std::string& name, const TypeSpec& retType, const std::vector<TypeSpec>& paramTypes, const std::string& aliasName, const std::vector<ExprASTNode*>& defExprs, const std::vector<bool>& paramByRefs) {
    std::string mangledName = aliasName.empty() ? name : aliasName;
    m_procReturnTypes[name] = retType;
    m_procReturnTypes[toLower(name)] = retType;
    m_procReturnTypes[mangledName] = retType;
    m_procReturnTypes[toLower(mangledName)] = retType;

    if (!defExprs.empty()) {
        m_procDefaults[name] = defExprs;
        m_procDefaults[toLower(name)] = defExprs;
        m_procDefaults[mangledName] = defExprs;
        m_procDefaults[toLower(mangledName)] = defExprs;
    }

    if (!paramByRefs.empty()) {
        m_procParamByRef[name] = paramByRefs;
        m_procParamByRef[toLower(name)] = paramByRefs;
        m_procParamByRef[mangledName] = paramByRefs;
        m_procParamByRef[toLower(mangledName)] = paramByRefs;
    }

    if (!aliasName.empty()) {
        m_funcAliases[name] = aliasName;
    }

    llvm::Type* llvmRetType = (toLower(retType.name) == "void" && retType.pointerDepth == 0)
        ? llvm::Type::getVoidTy(*m_context)
        : getLlvmType(retType);

    std::vector<llvm::Type*> llvmParamTypes;
    for (const auto& pt : paramTypes) {
        llvmParamTypes.push_back(getLlvmType(pt));
    }

    llvm::FunctionType* fnTy = llvm::FunctionType::get(llvmRetType, llvmParamTypes, false);
    if (!m_module->getFunction(mangledName)) {
        llvm::Function::Create(fnTy, llvm::Function::ExternalLinkage, mangledName, m_module.get());
    }
}

llvm::Function* LlvmEmitter::emitProcedure(const ProcedureNode& procNode, const std::string& className, const std::vector<std::unique_ptr<ASTNode>>* bodyStatements, bool isClassMethod) {
    if (!procNode.genericParams.empty()) {
        m_genericProcTemplates[procNode.name] = &procNode;

        m_genericProcTemplates[toLower(procNode.name)] = &procNode;
        if (!className.empty()) {
            std::string classProcName = className + "_" + procNode.name;
            m_genericProcTemplates[classProcName] = &procNode;
            m_genericProcTemplates[toLower(classProcName)] = &procNode;
        }
        return nullptr;
    }


    m_namedValues.clear();
    m_variableTypes = m_globalVariableTypes;


    // 1. Resolve Return Type
    llvm::Type* retType = procNode.isFunction ? getLlvmType(procNode.returnType) 
                                              : llvm::Type::getVoidTy(*m_context);

    // 2. Resolve Parameter Types
    std::vector<llvm::Type*> paramTypes;
    if (isClassMethod && !procNode.isDeclare) {
        paramTypes.push_back(llvm::PointerType::get(*m_context, 0));
    }
    for (const auto& param : procNode.parameters) {
        llvm::Type* pType = getLlvmType(param.type);
        if (param.isByRef) {
            pType = llvm::PointerType::get(*m_context, 0);
        }
        paramTypes.push_back(pType);
    }

    // 3. Create Function Prototype
    llvm::FunctionType* funcType = llvm::FunctionType::get(retType, paramTypes, false);
    llvm::GlobalValue::LinkageTypes linkage = (procNode.isPublic || procNode.isDeclare) ? llvm::Function::ExternalLinkage 
                                                                                         : llvm::Function::InternalLinkage;

    std::string mangledName = procNode.name;
    if (procNode.isDeclare && !procNode.aliasName.empty()) {
        mangledName = procNode.aliasName;
        m_funcAliases[procNode.name] = procNode.aliasName;
    } else if (!className.empty()) {
        if (procNode.propertyKind == ProcedureNode::PropertyKind::Get) {
            mangledName = className + "_get_" + procNode.name;
        } else if (procNode.propertyKind == ProcedureNode::PropertyKind::Let || procNode.propertyKind == ProcedureNode::PropertyKind::Set) {
            mangledName = className + "_set_" + procNode.name;
        } else {
            mangledName = className + "_" + procNode.name;
        }
    } else {
        if (procNode.propertyKind == ProcedureNode::PropertyKind::Get) {
            mangledName = "get_" + procNode.name;
        } else if (procNode.propertyKind == ProcedureNode::PropertyKind::Let || procNode.propertyKind == ProcedureNode::PropertyKind::Set) {
            mangledName = "set_" + procNode.name;
        }
    }

    // Variadic standard C functions like printf
    if (procNode.isDeclare && procNode.name == "printf") {
        funcType = llvm::FunctionType::get(retType, {paramTypes.front()}, true);
    }

    llvm::Function* func = m_module->getFunction(mangledName);
    if (!func) {
        func = llvm::Function::Create(funcType, linkage, mangledName, m_module.get());
        std::string triple = m_module->getTargetTriple().str();
        if (procNode.isInterrupt && (triple.find("x86") != std::string::npos || triple.find("i386") != std::string::npos || triple.find("i686") != std::string::npos)) {
            func->setCallingConv(llvm::CallingConv::X86_INTR);
        } else {
            func->setCallingConv(llvm::CallingConv::C);
        }
    }

    // Track default parameter values for optional parameters
    std::vector<ExprASTNode*> defExprs;
    std::vector<std::string> paramNames;
    std::vector<bool> paramByRefs;
    bool hasParamArray = false;
    for (const auto& param : procNode.parameters) {
        defExprs.push_back(param.defaultValue.get());
        paramNames.push_back(param.name);
        paramByRefs.push_back(param.isByRef);
        if (param.isParamArray) hasParamArray = true;
    }
    m_procDefaults[procNode.name] = defExprs;
    m_procParamNames[procNode.name] = paramNames;
    m_procParamByRef[procNode.name] = paramByRefs;
    m_procParamArray[procNode.name] = hasParamArray;
    if (mangledName != procNode.name) {
        m_procDefaults[mangledName] = defExprs;
        m_procParamNames[mangledName] = paramNames;
        m_procParamByRef[mangledName] = paramByRefs;
        m_procParamArray[mangledName] = hasParamArray;
    }

    if (procNode.isDeclare) {
        return func;
    }

    m_currentScopeClass = className;
    m_currentProcName = procNode.name;
    m_returnAssigned = false;
    m_currentProcIsUnsafe = procNode.isUnsafe;
    func->addFnAttr(llvm::Attribute::StackProtectStrong);

    if (procNode.isInline) {
        func->addFnAttr(llvm::Attribute::AlwaysInline);
    }
    if (procNode.isNoReturn) {
        func->addFnAttr(llvm::Attribute::NoReturn);
    }
    if (procNode.isExport) {
        func->setLinkage(llvm::GlobalValue::ExternalLinkage);
        func->setVisibility(llvm::GlobalValue::DefaultVisibility);
    }

    m_labels.clear();
    m_definedLabels.clear();
    m_referencedLabels.clear();
    m_catchStack.clear();
    m_byRefParams.clear();

    // DWARF DISubprogram for procedure
    llvm::DISubprogram* diSubprogram = nullptr;
    if (m_enableDebugInfo && m_diBuilder && m_diFile) {
        llvm::DISubroutineType* diFnType = m_diBuilder->createSubroutineType(
            m_diBuilder->getOrCreateTypeArray({})
        );
        unsigned lineNo = procNode.line > 0 ? procNode.line : 1;
        diSubprogram = m_diBuilder->createFunction(
            m_diFile,
            procNode.name,
            func->getName(),
            m_diFile,
            lineNo,
            diFnType,
            lineNo,
            llvm::DINode::FlagPrototyped,
            llvm::DISubprogram::SPFlagDefinition
        );
        func->setSubprogram(diSubprogram);
        m_diScopes.push_back(diSubprogram);
        emitDebugLocation(lineNo, 1);
    }

    // 4. Create Entry Block
    llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", func);
    m_builder->SetInsertPoint(entryBB);

    // 5. Store Parameters in Entry Allocas
    bool hasMe = (isClassMethod && !procNode.isDeclare);
    size_t paramIdx = 0;
    for (auto& arg : func->args()) {
        if (hasMe) {
            arg.setName("Me");
            llvm::AllocaInst* meAlloca = m_builder->CreateAlloca(arg.getType(), nullptr, "Me.addr");
            m_builder->CreateStore(&arg, meAlloca);
            m_namedValues["Me"] = meAlloca;
            m_namedValues["me"] = meAlloca;
            TypeSpec meType{className, 1};
            m_variableTypes["Me"] = meType;
            m_variableTypes["me"] = meType;
            hasMe = false;
            continue;
        }
        const auto& paramNode = procNode.parameters[paramIdx++];
        arg.setName(paramNode.name);

        llvm::AllocaInst* alloca = m_builder->CreateAlloca(arg.getType(), nullptr, paramNode.name + ".addr");
        m_builder->CreateStore(&arg, alloca);
        m_namedValues[paramNode.name] = alloca;
        m_namedValues[toLower(paramNode.name)] = alloca;
        m_variableTypes[paramNode.name] = paramNode.type;
        m_variableTypes[toLower(paramNode.name)] = paramNode.type;
        if (paramNode.isByRef) {
            m_byRefParams.insert(paramNode.name);
            m_byRefParams.insert(toLower(paramNode.name));
        }
    }

    // 6. Unified Exit Block & Return Value Alloca
    m_exitBlock = llvm::BasicBlock::Create(*m_context, "func.exit", func);
    m_retAlloca = nullptr;
    if (procNode.isFunction) {
        m_retAlloca = m_builder->CreateAlloca(retType, nullptr, procNode.name + ".result");
        m_builder->CreateStore(llvm::Constant::getNullValue(retType), m_retAlloca);
        m_namedValues[procNode.name] = m_retAlloca;
        m_namedValues[toLower(procNode.name)] = m_retAlloca;

        // If this is an instantiated generic procedure (e.g., Min_Int32), also register base template name
        size_t underPos = procNode.name.find('_');
        if (underPos != std::string::npos) {
            std::string baseTmpl = procNode.name.substr(0, underPos);
            if (m_genericProcTemplates.find(baseTmpl) != m_genericProcTemplates.end() ||
                m_genericProcTemplates.find(toLower(baseTmpl)) != m_genericProcTemplates.end()) {
                m_namedValues[baseTmpl] = m_retAlloca;
                m_namedValues[toLower(baseTmpl)] = m_retAlloca;
            }
        }
    }

    // 7. Lower Body Statements
    const auto& stmtsToEmit = bodyStatements ? *bodyStatements : procNode.body;
    for (const auto& stmt : stmtsToEmit) {
        emitStatement(stmt.get());
    }


    // Connect to exit block if insert block has no terminator
    if (!m_builder->GetInsertBlock()->getTerminator()) {
        m_builder->CreateBr(m_exitBlock);
    }

    // Emit exit block
    m_builder->SetInsertPoint(m_exitBlock);
    if (procNode.isFunction) {
        llvm::Value* retVal = m_builder->CreateLoad(retType, m_retAlloca, "retval");
        m_builder->CreateRet(retVal);
    } else {
        m_builder->CreateRetVoid();
    }

    if (m_enableDebugInfo && diSubprogram) {
        m_diScopes.pop_back();
        m_builder->SetCurrentDebugLocation(llvm::DebugLoc());
    }

    for (const auto& ref : m_referencedLabels) {
        if (!m_definedLabels.count(toLower(ref.name))) {
            Diagnostic::report(m_sourceFilePath, ref.line > 0 ? ref.line : procNode.line,
                               ref.col > 0 ? ref.col : 1, true,
                               "Undefined label '" + ref.name + "' in procedure '" + procNode.name + "'.", m_sourceText);
            m_hadError = true;
        }
    }

    if (procNode.isFunction && !procNode.isDeclare && !m_returnAssigned) {
        Diagnostic::report(m_sourceFilePath, procNode.line > 0 ? procNode.line : 1,
                           1, true,
                           "Function '" + procNode.name + "' does not assign a return value.", m_sourceText);
        m_hadError = true;
    }
    if (!m_hadError) {
        llvm::verifyFunction(*func);
    }
    return func;
}

bool LlvmEmitter::emitModule(const ModuleNode& moduleNode) {
    m_sourceFilePath = !moduleNode.sourceFilePath.empty() 
        ? moduleNode.sourceFilePath 
        : (moduleNode.name + ".bas");
    {
        std::ifstream srcFile(m_sourceFilePath);
        if (srcFile.is_open()) {
            std::stringstream buffer;
            buffer << srcFile.rdbuf();
            m_sourceText = buffer.str();
        }
    }

    if (m_enableDebugInfo && m_diBuilder) {
        std::string sourceFile = m_sourceFilePath;
        std::string dir = ".";
        std::string filename = sourceFile;
        size_t slashPos = sourceFile.find_last_of("/\\");
        if (slashPos != std::string::npos) {
            dir = sourceFile.substr(0, slashPos);
            filename = sourceFile.substr(slashPos + 1);
        }

        m_diFile = m_diBuilder->createFile(filename, dir);
        m_diCompileUnit = m_diBuilder->createCompileUnit(
            llvm::dwarf::DW_LANG_C99, // Closest compatible DWARF language identifier
            m_diFile,
            "Low-Level Basic Compiler (llbc)",
            /*isOptimized=*/false,
            /*flags=*/"",
            /*runtimeVersion=*/0
        );
    }
    // 1. Emit Enums
    for (const auto& member : moduleNode.members) {
        if (auto en = dynamic_cast<const EnumNode*>(member.get())) {
            emitEnum(*en);
        }
    }

    // 1.5 Emit Interfaces
    for (const auto& member : moduleNode.members) {
        if (auto iface = dynamic_cast<const InterfaceNode*>(member.get())) {
            emitInterface(*iface);
        }
    }

    // 1.6 Emit Delegates
    for (const auto& member : moduleNode.members) {
        if (auto del = dynamic_cast<const DelegateNode*>(member.get())) {
            emitDelegate(*del);
        }
    }

    // 2. Emit Structures
    for (const auto& member : moduleNode.members) {
        if (auto st = dynamic_cast<const StructureNode*>(member.get())) {
            emitStructure(*st);
        }
    }

    // 2.5 Emit Module-level Constants (Const)
    for (const auto& member : moduleNode.members) {
        if (auto c = dynamic_cast<const ConstStmtNode*>(member.get())) {
            if (c->value) {
                if (auto num = dynamic_cast<const NumberExprASTNode*>(c->value.get())) {
                    m_enumConstants[c->name] = num->val;
                    m_enumConstants[toLower(c->name)] = num->val;
                }
            }
            llvm::Type* constType = getLlvmType(c->type);
            llvm::Constant* initVal = llvm::Constant::getNullValue(constType);
            if (c->value) {
                if (auto num = dynamic_cast<const NumberExprASTNode*>(c->value.get())) {
                    if (num->isFloat && constType->isFloatingPointTy()) {
                        initVal = llvm::ConstantFP::get(constType, num->floatVal);
                    } else if (constType->isIntegerTy()) {
                        initVal = llvm::ConstantInt::get(constType, num->val);
                    }
                }
            }
            llvm::GlobalValue::LinkageTypes linkage = c->isPublic ? llvm::GlobalValue::ExternalLinkage : llvm::GlobalValue::InternalLinkage;
            new llvm::GlobalVariable(
                *m_module,
                constType,
                true, // isConstant
                linkage,
                initVal,
                c->name
            );
            m_constants.insert(c->name);
            m_constants.insert(toLower(c->name));
        }
    }

    // 2.6 Emit Module-level Static Assertions (#Assert)
    for (const auto& member : moduleNode.members) {
        if (auto assertStmt = dynamic_cast<const StaticAssertStmtNode*>(member.get())) {
            emitStaticAssert(*assertStmt);
        }
    }

    // 2.7 If this compilation unit is a Class, register its StructType and fields
    if (moduleNode.isClass) {
        m_classInstancing[moduleNode.name] = moduleNode.instancing;
        m_classInstancing[toLower(moduleNode.name)] = moduleNode.instancing;

        // Interface Implementation Validation
        for (const auto& ifaceName : moduleNode.implementsInterfaces) {
            auto ifIt = m_interfaces.find(ifaceName);
            if (ifIt == m_interfaces.end()) ifIt = m_interfaces.find(toLower(ifaceName));
            if (ifIt == m_interfaces.end()) {
                Diagnostic::report(m_sourceFilePath, 1, 1, true,
                                   "Cannot find interface '" + ifaceName + "' implemented by class '" + moduleNode.name + "'.", m_sourceText);
                m_hadError = true;
            } else {
                const InterfaceNode* targetIface = ifIt->second;
                for (const auto& requiredMethod : targetIface->methods) {
                    bool foundMethod = false;
                    std::string reqLower = toLower(requiredMethod.name);
                    for (const auto& member : moduleNode.members) {
                        if (auto proc = dynamic_cast<const ProcedureNode*>(member.get())) {
                            if (toLower(proc->name) == reqLower) {
                                foundMethod = true;
                                break;
                            }
                        }
                    }
                    if (!foundMethod) {
                        Diagnostic::report(m_sourceFilePath, 1, 1, true,
                                           "Class '" + moduleNode.name + "' does not implement required interface method '" + requiredMethod.name + "' from interface '" + targetIface->name + "'.", m_sourceText);
                        m_hadError = true;
                    }
                }
            }
        }

        std::vector<llvm::Type*> memberTypes;
        unsigned fieldIndex = 0;
        for (const auto& member : moduleNode.members) {
            if (auto dim = dynamic_cast<const DimStmtNode*>(member.get())) {
                llvm::Type* fTy = getLlvmType(dim->type);
                memberTypes.push_back(fTy);
                m_structFieldIndices[moduleNode.name][toLower(dim->varName)] = fieldIndex;
                m_structFieldIndices[toLower(moduleNode.name)][toLower(dim->varName)] = fieldIndex;
                m_structFieldTypes[moduleNode.name][toLower(dim->varName)] = dim->type;
                m_structFieldTypes[toLower(moduleNode.name)][toLower(dim->varName)] = dim->type;
                if (!dim->isPublic) {
                    registerPrivateField(moduleNode.name, dim->varName);
                }
                fieldIndex++;
            }
        }
        if (memberTypes.empty()) {
            memberTypes.push_back(llvm::Type::getInt8Ty(*m_context)); // non-empty struct dummy
        }
        llvm::StructType* classSt = llvm::StructType::create(*m_context, moduleNode.name);
        classSt->setBody(memberTypes, false);
        m_structTypes[moduleNode.name] = classSt;
        m_structTypes[toLower(moduleNode.name)] = classSt;

        // If marked <Instancing(Global)> or <Instancing(SingleUse)>, create internal static singleton instance in .bss
        if (moduleNode.instancing == InstancingKind::Global || moduleNode.instancing == InstancingKind::SingleUse) {
            llvm::GlobalVariable* singletonVar = new llvm::GlobalVariable(
                *m_module,
                classSt,
                false, // isConstant
                llvm::GlobalValue::InternalLinkage,
                llvm::ConstantAggregateZero::get(classSt),
                "__singleton_" + moduleNode.name
            );
            m_classSingletons[moduleNode.name] = singletonVar;
            m_classSingletons[toLower(moduleNode.name)] = singletonVar;
        }
    }

    // 2.8 Register Use Directives (aliases)
    for (const auto& useDir : moduleNode.uses) {
        std::string fullTarget = !useDir.containerPath.empty()
            ? (useDir.containerPath + "." + useDir.targetPath)
            : useDir.targetPath;
        if (!useDir.aliasName.empty()) {
            m_funcAliases[useDir.aliasName] = fullTarget;
            m_funcAliases[toLower(useDir.aliasName)] = fullTarget;
        } else {
            // Unqualified target name becomes an alias for the full target
            std::string shortName = useDir.targetPath;
            m_funcAliases[shortName] = fullTarget;
            m_funcAliases[toLower(shortName)] = fullTarget;
        }
    }

    // 3. Emit Module-level Global Variables (Dim)
    if (!moduleNode.isClass) {
        for (const auto& member : moduleNode.members) {
            if (auto dim = dynamic_cast<const DimStmtNode*>(member.get())) {
            llvm::Type* varType = getLlvmType(dim->type);
            llvm::Constant* initVal = llvm::Constant::getNullValue(varType);
            if (dim->initValue) {
                if (auto num = dynamic_cast<const NumberExprASTNode*>(dim->initValue.get())) {
                    if (num->isFloat && varType->isFloatingPointTy()) {
                        initVal = llvm::ConstantFP::get(varType, num->floatVal);
                    } else if (varType->isIntegerTy()) {
                        initVal = llvm::ConstantInt::get(varType, num->val);
                    }
                }
            }
            m_variableTypes[dim->varName] = dim->type;
            m_variableTypes[toLower(dim->varName)] = dim->type;
            m_globalVariableTypes[dim->varName] = dim->type;
            m_globalVariableTypes[toLower(dim->varName)] = dim->type;
            llvm::GlobalValue::LinkageTypes linkage = llvm::GlobalValue::InternalLinkage;
            new llvm::GlobalVariable(
                *m_module,
                varType,
                false, // isConstant
                linkage,
                initVal,
                dim->varName
            );
        }
    }
    }

    // Determine normalized module/namespace prefix
    std::string modulePrefix = "";
    if (moduleNode.name.find('.') != std::string::npos) {
        modulePrefix = moduleNode.name;
        for (auto& ch : modulePrefix) {
            if (ch == '.') ch = '_';
        }
    }

    // 4. Pre-declare all Procedures (so calls/Property Let/Get can resolve in any order)
    for (const auto& member : moduleNode.members) {
        if (auto proc = dynamic_cast<const ProcedureNode*>(member.get())) {
            if (!proc->genericParams.empty()) {
                m_genericProcTemplates[proc->name] = proc;
                m_genericProcTemplates[toLower(proc->name)] = proc;
                continue;
            }
            std::string className = moduleNode.isClass ? moduleNode.name : "";
            llvm::Type* retType = proc->isFunction ? getLlvmType(proc->returnType) : llvm::Type::getVoidTy(*m_context);
            std::vector<llvm::Type*> paramTypes;
            if (moduleNode.isClass && !proc->isDeclare) {
                paramTypes.push_back(llvm::PointerType::get(*m_context, 0));
            }
            for (const auto& param : proc->parameters) {
                llvm::Type* pType = getLlvmType(param.type);
                if (param.isByRef) pType = llvm::PointerType::get(*m_context, 0);
                paramTypes.push_back(pType);
            }
            llvm::FunctionType* funcType = llvm::FunctionType::get(retType, paramTypes, false);
            std::string mangledName = proc->name;
            if (proc->isDeclare) {
                if (!proc->aliasName.empty()) {
                    mangledName = proc->aliasName;
                    m_funcAliases[proc->name] = proc->aliasName;
                }
            } else if (!className.empty()) {
                if (proc->propertyKind == ProcedureNode::PropertyKind::Get) {
                    mangledName = className + "_get_" + proc->name;
                } else if (proc->propertyKind == ProcedureNode::PropertyKind::Let || proc->propertyKind == ProcedureNode::PropertyKind::Set) {
                    mangledName = className + "_set_" + proc->name;
                } else {
                    mangledName = className + "_" + proc->name;
                }
            } else if (!modulePrefix.empty()) {
                mangledName = modulePrefix + "_" + proc->name;
                m_funcAliases[moduleNode.name + "." + proc->name] = mangledName;
            } else {
                if (proc->propertyKind == ProcedureNode::PropertyKind::Get) {
                    mangledName = "get_" + proc->name;
                } else if (proc->propertyKind == ProcedureNode::PropertyKind::Let || proc->propertyKind == ProcedureNode::PropertyKind::Set) {
                    mangledName = "set_" + proc->name;
                }
            }
            // Track procedure parameter metadata early for call-site resolution
            std::vector<ExprASTNode*> defExprs;
            std::vector<std::string> paramNames;
            std::vector<bool> paramByRefs;
            bool hasParamArray = false;
            for (const auto& param : proc->parameters) {
                defExprs.push_back(param.defaultValue.get());
                paramNames.push_back(param.name);
                paramByRefs.push_back(param.isByRef);
                if (param.isParamArray) hasParamArray = true;
            }
            m_procDefaults[proc->name] = defExprs;
            m_procParamNames[proc->name] = paramNames;
            m_procParamByRef[proc->name] = paramByRefs;
            m_procParamArray[proc->name] = hasParamArray;
            m_procReturnTypes[proc->name] = proc->returnType;
            m_procReturnTypes[toLower(proc->name)] = proc->returnType;
            if (mangledName != proc->name) {
                m_procDefaults[mangledName] = defExprs;
                m_procParamNames[mangledName] = paramNames;
                m_procParamByRef[mangledName] = paramByRefs;
                m_procParamArray[mangledName] = hasParamArray;
                m_procReturnTypes[mangledName] = proc->returnType;
                m_procReturnTypes[toLower(mangledName)] = proc->returnType;
            }

            if (!m_module->getFunction(mangledName)) {
                llvm::GlobalValue::LinkageTypes linkage = (proc->isPublic || proc->isDeclare) ? llvm::Function::ExternalLinkage : llvm::Function::InternalLinkage;
                llvm::Function::Create(funcType, linkage, mangledName, m_module.get());
            }
        }
    }

    // 5. Emit Procedure Bodies
    for (const auto& member : moduleNode.members) {
        if (auto proc = dynamic_cast<const ProcedureNode*>(member.get())) {
            if (!proc->genericParams.empty()) {
                continue;
            }
            std::string scopeName = moduleNode.isClass ? moduleNode.name : (!modulePrefix.empty() ? modulePrefix : "");
            emitProcedure(*proc, scopeName, nullptr, moduleNode.isClass);
        }
    }

    // 6. Synthesize C 'main' wrapper if LLB 'Main' exists and no 'main' is defined
    llvm::Function* mainFn = m_module->getFunction("main");
    llvm::Function* llbMain = m_module->getFunction("Main");
    if (!mainFn && llbMain) {
        llvm::FunctionType* cMainType = llvm::FunctionType::get(
            llvm::Type::getInt32Ty(*m_context),
            {llvm::Type::getInt32Ty(*m_context), llvm::PointerType::get(*m_context, 0)},
            false
        );
        mainFn = llvm::Function::Create(cMainType, llvm::Function::ExternalLinkage, "main", m_module.get());
        llvm::BasicBlock* entryBB = llvm::BasicBlock::Create(*m_context, "entry", mainFn);
        m_builder->SetInsertPoint(entryBB);

        llvm::Value* retVal = nullptr;
        bool isVoid = llbMain->getReturnType()->isVoidTy();
        llvm::Twine callName = isVoid ? "" : "call.main";
        if (llbMain->getFunctionType()->getNumParams() == 0) {
            retVal = m_builder->CreateCall(llbMain, {}, callName);
        } else if (llbMain->getFunctionType()->getNumParams() == 1) {
            llvm::Value* argc = mainFn->getArg(0);
            argc = coerceType(argc, llbMain->getFunctionType()->getParamType(0));
            retVal = m_builder->CreateCall(llbMain, {argc}, callName);
        } else {
            llvm::Value* argc = mainFn->getArg(0);
            llvm::Value* argv = mainFn->getArg(1);
            argc = coerceType(argc, llbMain->getFunctionType()->getParamType(0));
            argv = coerceType(argv, llbMain->getFunctionType()->getParamType(1));
            retVal = m_builder->CreateCall(llbMain, {argc, argv}, callName);
        }

        if (retVal && !isVoid && retVal->getType()->isIntegerTy()) {
            retVal = coerceType(retVal, llvm::Type::getInt32Ty(*m_context));
            m_builder->CreateRet(retVal);
        } else {
            m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*m_context), 0));
        }
    }

    if (m_enableDebugInfo && m_diBuilder) {
        m_diBuilder->finalize();
    }

    if (m_hadError) {
        return false;
    }

    return !llvm::verifyModule(*m_module, &llvm::errs());
}

void LlvmEmitter::printIR() const {
    m_module->print(llvm::outs(), nullptr);
}

} // namespace llbc