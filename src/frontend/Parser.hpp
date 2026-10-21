/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#ifndef LLBC_PARSER_HPP
#define LLBC_PARSER_HPP

#include "Lexer.hpp"
#include "AST.hpp"
#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>

namespace llbc {

class Parser {
public:
    explicit Parser(Lexer lexer, std::unordered_map<std::string, int64_t> defines = {}, std::string sourceFilePath = "");

    std::unique_ptr<ModuleNode> parseModule();

    void reportError(const std::string& message, const Token* tok = nullptr);

private:
    Lexer m_lexer;
    Token m_currentToken;
    Token m_prevToken;
    std::string m_sourceFilePath;

    // Preprocessor & Conditional Compilation State
    std::unordered_map<std::string, int64_t> m_condConstants;
    struct CondFrame {
        bool anyBranchTaken{false};
        bool currentBranchActive{true};
    };
    std::vector<CondFrame> m_condStack;

    void handleDirective();
    void skipInactiveConditionalBlock();
    int64_t evalCondExpr();
    int64_t evalCondOr();
    int64_t evalCondXor();
    int64_t evalCondAnd();
    int64_t evalCondEquality();
    int64_t evalCondRelational();
    int64_t evalCondAdditive();
    int64_t evalCondMultiplicative();
    int64_t evalCondUnary();
    int64_t evalCondPrimary();

    void consume();
    bool match(TokenType type);
    bool check(TokenType type) const;
    bool expect(TokenType type, const std::string& errorMessage);
    bool checkKeyword(const std::string& kw) const;
    bool matchKeyword(const std::string& kw);

    size_t m_withDepth{0};
    size_t m_forDepth{0};
    size_t m_doDepth{0};
    size_t m_whileDepth{0};
    std::unordered_set<std::string> m_definedProcedures;

    // Types
    TypeSpec parseTypeSpec();

    // Declarations & Members
    std::unique_ptr<ProcedureNode> parseProcedure(bool isPublic = true, bool isInline = false, bool isNoReturn = false, bool isExport = false);
    std::unique_ptr<StructureNode> parseStructure(bool isPacked = false, int alignment = 0);
    std::unique_ptr<StructureNode> parseUnion(bool isPacked = false, int alignment = 0);
    std::unique_ptr<ConstStmtNode> parseConstStatement(bool isPublic = false);
    std::unique_ptr<EnumNode> parseEnum(bool isPublic = true);
    std::unique_ptr<InterfaceNode> parseInterface(bool isPublic = true);
    std::unique_ptr<DelegateNode> parseDelegate(bool isPublic = true);
    void parseTypeAlias();
    ImportDirective parseImportStatement();
    UseDirective parseUseStatement();

    std::unordered_map<std::string, TypeSpec> m_typeAliases;

    // Statements
    std::unique_ptr<ASTNode> parseStatement();
    std::vector<std::unique_ptr<ASTNode>> parseStatementBlock(const std::vector<std::string>& stopKeywords);
    std::unique_ptr<DimStmtNode> parseDimStatement();
    std::unique_ptr<IfStmtNode> parseIfStatement();
    std::unique_ptr<ForStmtNode> parseForStatement();
    std::unique_ptr<ForEachStmtNode> parseForEachStatement();
    std::unique_ptr<DoLoopStmtNode> parseDoLoopStatement();
    std::unique_ptr<WhileStmtNode> parseWhileStatement();
    std::unique_ptr<ExitStmtNode> parseExitStatement();
    std::unique_ptr<SelectStmtNode> parseSelectStatement();
    std::unique_ptr<MatchStmtNode> parseMatchStatement();
    std::unique_ptr<AsmStmtNode> parseAsmStatement();
    std::unique_ptr<WithStmtNode> parseWithStatement();
    std::unique_ptr<UsingStmtNode> parseUsingStatement();
    std::unique_ptr<PrintStmtNode> parsePrintStatement();
    std::unique_ptr<ASTNode> parsePrintOrPrintFileStatement();
    std::unique_ptr<InputStmtNode> parseInputStatement();
    std::unique_ptr<ASTNode> parseInputOrInputFileStatement();
    std::unique_ptr<OpenStmtNode> parseOpenStatement();
    std::unique_ptr<CloseStmtNode> parseCloseStatement();
    std::unique_ptr<LineInputStmtNode> parseLineInputStatement();
    std::unique_ptr<DeleteStmtNode> parseDeleteStatement();
    std::unique_ptr<ReDimStmtNode> parseReDimStatement();
    std::unique_ptr<EraseStmtNode> parseEraseStatement();
    std::unique_ptr<GoToStmtNode> parseGoToStatement();
    std::unique_ptr<TryStmtNode> parseTryStatement();
    std::unique_ptr<ASTNode> parseAssignOrCallStatement();

    // Expressions & Operator Precedence
    std::unique_ptr<ExprASTNode> parseExpression();
    std::unique_ptr<ExprASTNode> parseLogicalOr();
    std::unique_ptr<ExprASTNode> parseLogicalXor();
    std::unique_ptr<ExprASTNode> parseLogicalAnd();
    std::unique_ptr<ExprASTNode> parseEquality();
    std::unique_ptr<ExprASTNode> parseRelational();
    std::unique_ptr<ExprASTNode> parseShift();
    std::unique_ptr<ExprASTNode> parseAdditiveExpr();
    std::unique_ptr<ExprASTNode> parseMultiplicative();
    std::unique_ptr<ExprASTNode> parseUnary();
    std::unique_ptr<ExprASTNode> parsePostfixExpr();
    std::unique_ptr<ExprASTNode> parsePrimaryExpr();
};

} // namespace llbc

#endif // LLBC_PARSER_HPP