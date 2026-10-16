/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/AST.hpp
 * Summary: Abstract Syntax Tree definitions for Low-Level Basic statements and types.
 */

#ifndef LLBC_AST_HPP
#define LLBC_AST_HPP

#include <string>
#include <vector>
#include <memory>

namespace llbc {

struct TypeSpec {
    std::string name;
    int pointerDepth{0}; // Replaces bool isPointer
    bool isVolatile{false};
};

struct ParameterNode {
    std::string name;
    TypeSpec type;
    bool isByRef{false};
};

class ASTNode {
public:
    virtual ~ASTNode() = default;
};

class CallExprASTNode : public ASTNode {
public:
    std::string funcName;
    std::vector<std::string> stringArgs; // Holds string literals or expression identifiers
};

class DimStmtNode : public ASTNode {
public:
    std::string varName;
    TypeSpec type;
};

class ProcedureNode : public ASTNode {
public:
    std::string name;
    bool isPublic{true};
    bool isUnsafe{false};
    bool isFunction{false};
    bool isDeclare{false}; 
    TypeSpec returnType;
    std::vector<ParameterNode> parameters;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class ModuleNode : public ASTNode {
public:
    std::string name;
    bool isClass{false};
    std::vector<std::unique_ptr<ASTNode>> members;
};

} // namespace llbc

#endif // LLBC_AST_HPP