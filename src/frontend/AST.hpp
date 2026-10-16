/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/AST.hpp
 * Summary: Mature Abstract Syntax Tree definitions for expressions, assignments, and control flow.
 */

#ifndef LLBC_AST_HPP
#define LLBC_AST_HPP

#include <string>
#include <vector>
#include <memory>

namespace llbc {

struct TypeSpec {
    std::string name;
    int pointerDepth{0};
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

// --- Expressions ---
class ExprASTNode : public ASTNode {
public:
    virtual ~ExprASTNode() = default;
};

class NumberExprASTNode : public ExprASTNode {
public:
    int64_t val;
    explicit NumberExprASTNode(int64_t v) : val(v) {}
};

class StringExprASTNode : public ExprASTNode {
public:
    std::string val;
    explicit StringExprASTNode(std::string v) : val(std::move(v)) {}
};

class VariableExprASTNode : public ExprASTNode {
public:
    std::string name;
    explicit VariableExprASTNode(std::string n) : name(std::move(n)) {}
};

class BinaryExprASTNode : public ExprASTNode {
public:
    char op;
    std::unique_ptr<ExprASTNode> lhs;
    std::unique_ptr<ExprASTNode> rhs;
    BinaryExprASTNode(char o, std::unique_ptr<ExprASTNode> l, std::unique_ptr<ExprASTNode> r)
        : op(o), lhs(std::move(l)), rhs(std::move(r)) {}
};

class CallExprASTNode : public ExprASTNode {
public:
    std::string funcName;
    std::vector<std::unique_ptr<ExprASTNode>> args;
};

// --- Statements ---
class DimStmtNode : public ASTNode {
public:
    std::string varName;
    TypeSpec type;
};

class AssignStmtNode : public ASTNode {
public:
    std::string varName;
    std::unique_ptr<ExprASTNode> value;
};

struct IfBranch {
    std::unique_ptr<ExprASTNode> condition;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class IfStmtNode : public ASTNode {
public:
    std::vector<IfBranch> branches; // Handles If and ElseIf
    std::vector<std::unique_ptr<ASTNode>> elseBody; // Handles optional Else
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