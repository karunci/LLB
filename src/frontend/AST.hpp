/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#ifndef LLBC_AST_HPP
#define LLBC_AST_HPP

#include <string>
#include <vector>
#include <memory>
#include <cstdint>

namespace llbc {

struct TypeSpec {
    std::string name;
    int pointerDepth{0};
    bool isVolatile{false};
    bool isArray{false};
    size_t arraySize{0};
    std::vector<size_t> dimensions;
    std::vector<TypeSpec> typeArgs; // e.g. T in Box(Of T) or Pair(Of K, V)
};

class ExprASTNode;

struct ParameterNode {
    std::string name;
    TypeSpec type;
    bool isByRef{false};
    bool isOptional{false};
    bool isParamArray{false};
    std::unique_ptr<ExprASTNode> defaultValue;
};

class ASTNode {
public:
    virtual ~ASTNode() = default;
    size_t line{1};
    size_t column{1};
};

// --- Expressions ---
class ExprASTNode : public ASTNode {
public:
    virtual ~ExprASTNode() = default;
};

class NumberExprASTNode : public ExprASTNode {
public:
    int64_t val{0};
    double floatVal{0.0};
    bool isFloat{false};
    std::string typeHint;
    explicit NumberExprASTNode(int v, std::string hint = "") : val(v), typeHint(std::move(hint)) {}
    explicit NumberExprASTNode(int64_t v, std::string hint = "") : val(v), typeHint(std::move(hint)) {}
    explicit NumberExprASTNode(double fv, std::string hint = "") : floatVal(fv), isFloat(true), typeHint(std::move(hint)) {}
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
    std::string op;
    std::unique_ptr<ExprASTNode> lhs;
    std::unique_ptr<ExprASTNode> rhs;
    BinaryExprASTNode(std::string o, std::unique_ptr<ExprASTNode> l, std::unique_ptr<ExprASTNode> r)
        : op(std::move(o)), lhs(std::move(l)), rhs(std::move(r)) {}
};

class UnaryExprASTNode : public ExprASTNode {
public:
    std::string op;
    std::unique_ptr<ExprASTNode> expr;
    UnaryExprASTNode(std::string o, std::unique_ptr<ExprASTNode> e)
        : op(std::move(o)), expr(std::move(e)) {}
};

class CastExprASTNode : public ExprASTNode {
public:
    enum class CastKind { CPtr, CType };
    CastKind kind;
    TypeSpec targetType;
    std::unique_ptr<ExprASTNode> expr;
    CastExprASTNode(CastKind k, TypeSpec t, std::unique_ptr<ExprASTNode> e)
        : kind(k), targetType(std::move(t)), expr(std::move(e)) {}
};

class AddressOfExprASTNode : public ExprASTNode {
public:
    std::string targetName;
    std::unique_ptr<ExprASTNode> targetExpr;
    explicit AddressOfExprASTNode(std::string name) : targetName(std::move(name)) {}
    explicit AddressOfExprASTNode(std::unique_ptr<ExprASTNode> expr) : targetExpr(std::move(expr)) {}
};

class MemberAccessExprASTNode : public ExprASTNode {
public:
    std::unique_ptr<ExprASTNode> base;
    std::string memberName;
    MemberAccessExprASTNode(std::unique_ptr<ExprASTNode> b, std::string m)
        : base(std::move(b)), memberName(std::move(m)) {}
};

class IndexExprASTNode : public ExprASTNode {
public:
    std::unique_ptr<ExprASTNode> base;
    std::unique_ptr<ExprASTNode> index;
    std::vector<std::unique_ptr<ExprASTNode>> indices;
    IndexExprASTNode(std::unique_ptr<ExprASTNode> b, std::unique_ptr<ExprASTNode> idx)
        : base(std::move(b)), index(std::move(idx)) {}
    IndexExprASTNode(std::unique_ptr<ExprASTNode> b, std::vector<std::unique_ptr<ExprASTNode>> idxs)
        : base(std::move(b)), indices(std::move(idxs)) {}
};

struct CallArgument {
    std::string name; // empty if positional
    std::unique_ptr<ExprASTNode> expr;
};

class CallExprASTNode : public ExprASTNode {
public:
    std::string funcName;
    std::unique_ptr<ExprASTNode> calleeExpr; // Optional base object (e.g. Me or instance)
    std::vector<std::unique_ptr<ExprASTNode>> args;
    std::vector<CallArgument> namedArgs;
    std::vector<TypeSpec> typeArgs; // Explicit generic arguments, e.g. Min(Of Int32)(a, b) or Min[Int32](a, b)
};


class NewExprASTNode : public ExprASTNode {
public:
    std::string className;
    TypeSpec typeSpec;
    std::vector<std::unique_ptr<ExprASTNode>> args;
};

class TypeOfExprASTNode : public ExprASTNode {
public:
    std::unique_ptr<ExprASTNode> targetExpr;
    TypeSpec targetType;
    bool isNot{false};

    TypeOfExprASTNode(std::unique_ptr<ExprASTNode> expr, TypeSpec type, bool notFlag = false)
        : targetExpr(std::move(expr)), targetType(std::move(type)), isNot(notFlag) {}
};

class LambdaExprASTNode : public ExprASTNode {
public:
    std::vector<ParameterNode> parameters;
    TypeSpec returnType;
    std::unique_ptr<ExprASTNode> bodyExpr;
};

// --- Statements ---

class DimStmtNode : public ASTNode {
public:
    std::string varName;
    TypeSpec type;
    std::unique_ptr<ExprASTNode> initValue;
};

class ConstStmtNode : public ASTNode {
public:
    std::string name;
    TypeSpec type;
    std::unique_ptr<ExprASTNode> value;
    bool isPublic{false};
};

class AssignStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> target; // Can be VariableExpr, MemberAccess, or IndexExpr
    std::unique_ptr<ExprASTNode> value;
};

class CallStmtNode : public ASTNode {
public:
    std::unique_ptr<CallExprASTNode> call;
    explicit CallStmtNode(std::unique_ptr<CallExprASTNode> c) : call(std::move(c)) {}
};

struct IfBranch {
    std::unique_ptr<ExprASTNode> condition;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class IfStmtNode : public ASTNode {
public:
    std::vector<IfBranch> branches; // Handles primary If and any ElseIf branches
    std::vector<std::unique_ptr<ASTNode>> elseBody; // Handles optional Else
};

class ForStmtNode : public ASTNode {
public:
    std::string varName;
    std::unique_ptr<ExprASTNode> startExpr;
    std::unique_ptr<ExprASTNode> endExpr;
    std::unique_ptr<ExprASTNode> stepExpr; // null if default (+1)
    std::vector<std::unique_ptr<ASTNode>> body;
};

class ForEachStmtNode : public ASTNode {
public:
    std::string varName;
    std::unique_ptr<ExprASTNode> collectionExpr;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class DoLoopStmtNode : public ASTNode {
public:
    enum class LoopType {
        Infinite,
        PreWhile,
        PreUntil,
        PostWhile,
        PostUntil
    };
    LoopType loopType{LoopType::Infinite};
    std::unique_ptr<ExprASTNode> condition;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class WhileStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> condition;
    std::vector<std::unique_ptr<ASTNode>> body;
};

struct CaseBranch {
    std::vector<std::unique_ptr<ExprASTNode>> values; // Empty if Case Else
    std::vector<std::unique_ptr<ASTNode>> body;
    bool isElse{false};
};

class SelectStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> expr;
    std::vector<CaseBranch> branches;
};

struct MatchPattern {
    enum class Kind {
        Value,
        Range,
        OkPattern,
        ErrPattern,
        Wildcard
    };
    Kind kind{Kind::Value};
    std::unique_ptr<ExprASTNode> expr;
    std::unique_ptr<ExprASTNode> rangeEnd;
    std::string boundVar;
};

struct MatchCaseBranch {
    std::vector<MatchPattern> patterns;
    std::vector<std::unique_ptr<ASTNode>> body;
    bool isElse{false};
};

class MatchStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> expr;
    std::vector<MatchCaseBranch> branches;
};

class ExitStmtNode : public ASTNode {
public:
    enum class ExitKind {
        Sub,
        Function,
        For,
        Do,
        While
    };
    ExitKind kind;
    explicit ExitStmtNode(ExitKind k) : kind(k) {}
};

class AsmStmtNode : public ASTNode {
public:
    std::string assemblyCode;
    std::string constraints{"~{dirflag},~{fpsr},~{flags}"};
    std::vector<std::unique_ptr<ExprASTNode>> inputOperands;

    explicit AsmStmtNode(std::string code) : assemblyCode(std::move(code)) {}
};

struct PrintItem {
    std::unique_ptr<ExprASTNode> expr;
    char separator{';'}; // ',' for tab, ';' for no space
};

class PrintStmtNode : public ASTNode {
public:
    std::vector<PrintItem> items;
    bool hasTrailingSeparator{false};
};

class InputStmtNode : public ASTNode {
public:
    std::string prompt;
    std::unique_ptr<ExprASTNode> target;
};

// File I/O Nodes
enum class FileMode {
    Input,
    Output,
    Append,
    Binary
};

class OpenStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> filePath;
    FileMode mode{FileMode::Input};
    std::unique_ptr<ExprASTNode> fileNumber;
};

class CloseStmtNode : public ASTNode {
public:
    std::vector<std::unique_ptr<ExprASTNode>> fileNumbers; // Empty means close all
};

class PrintFileStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> fileNumber;
    std::vector<PrintItem> items;
    bool hasTrailingSeparator{false};
};

class LineInputStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> fileNumber;
    std::unique_ptr<ExprASTNode> targetVar;
};

class InputFileStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> fileNumber;
    std::vector<std::unique_ptr<ExprASTNode>> targets;
};

class DeleteStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> target;
};

class ReDimStmtNode : public ASTNode {
public:
    bool isPreserve{false};
    std::string varName;
    std::vector<std::unique_ptr<ExprASTNode>> dimensions;
};

class EraseStmtNode : public ASTNode {
public:
    std::string varName;
    std::unique_ptr<ExprASTNode> targetExpr;
};

class LabelStmtNode : public ASTNode {
public:
    std::string labelName;
    explicit LabelStmtNode(std::string name) : labelName(std::move(name)) {}
};

class GoToStmtNode : public ASTNode {
public:
    std::string labelName;
    explicit GoToStmtNode(std::string name) : labelName(std::move(name)) {}
};

class TryStmtNode : public ASTNode {
public:
    std::vector<std::unique_ptr<ASTNode>> tryBody;
    std::string catchVarName; // e.g. "ex" in Catch ex As Int32
    std::vector<std::unique_ptr<ASTNode>> catchBody;
    std::vector<std::unique_ptr<ASTNode>> finallyBody;
};

struct StructureField {
    std::string name;
    TypeSpec type;
    bool isPublic{true};
};

class StructureNode : public ASTNode {
public:
    std::string name;
    std::vector<std::string> genericParams; // e.g. ["T"] for Structure Box(Of T)
    bool isPacked{false};
    bool isUnion{false};
    int alignment{0};
    std::vector<StructureField> fields;
};

class WithStmtNode : public ASTNode {
public:
    std::unique_ptr<ExprASTNode> target;
    std::vector<std::unique_ptr<ASTNode>> body;
};

class UsingStmtNode : public ASTNode {
public:
    std::string varName;
    TypeSpec type;
    std::unique_ptr<ExprASTNode> initExpr;
    std::vector<std::unique_ptr<ASTNode>> body;
};

struct EnumMember {
    std::string name;
    int64_t value{0};
    bool hasExplicitValue{false};
};

class EnumNode : public ASTNode {
public:
    std::string name;
    bool isPublic{true};
    std::vector<EnumMember> members;
};

class ProcedureNode : public ASTNode {
public:
    enum class PropertyKind {
        None,
        Get,
        Let,
        Set
    };

    std::string name;
    std::vector<std::string> genericParams; // e.g. ["T"] for Function Min(Of T)
    std::string libName;
    std::string aliasName;
    bool isPublic{true};
    bool isUnsafe{false};
    bool isFunction{false};
    bool isDeclare{false};
    bool isInline{false};
    bool isNoReturn{false};
    bool isExport{false};
    PropertyKind propertyKind{PropertyKind::None};
    TypeSpec returnType;
    std::vector<ParameterNode> parameters;
    std::vector<std::unique_ptr<ASTNode>> body;
};


struct ImportDirective {
    std::string moduleName;
    std::string symbolName;
    std::string aliasName;
    std::string filePath;
};

struct InterfaceMethod {
    std::string name;
    bool isFunction{false};
    TypeSpec returnType;
    std::vector<ParameterNode> parameters;
};

class InterfaceNode : public ASTNode {
public:
    std::string name;
    bool isPublic{true};
    std::vector<InterfaceMethod> methods;
};

class ModuleNode : public ASTNode {
public:
    std::string name;
    std::string sourceFilePath;
    bool isClass{false};
    bool isInterface{false};
    std::vector<std::string> implementsInterfaces;
    std::vector<ImportDirective> imports;
    std::vector<std::unique_ptr<ASTNode>> members;
};

} // namespace llbc

#endif // LLBC_AST_HPP