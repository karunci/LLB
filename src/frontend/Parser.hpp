/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/Parser.hpp
 * Summary: Parser header declaring expression and statement parsing helpers. 
 *          Recursive Descent Parser interface for Stage-0 bootstrap.
 */

#ifndef LLBC_PARSER_HPP
#define LLBC_PARSER_HPP

#include "Lexer.hpp"
#include "AST.hpp"
#include <memory>

namespace llbc {

class Parser {
public:
    explicit Parser(Lexer lexer);

    std::unique_ptr<ModuleNode> parseModule();
    std::unique_ptr<ProcedureNode> parseProcedure();
    std::unique_ptr<DimStmtNode> parseDimStatement();
    std::unique_ptr<IfStmtNode> parseIfStatement();

    // Expression parsing helper declarations
    std::unique_ptr<ExprASTNode> parseExpression();
    std::unique_ptr<ExprASTNode> parsePrimaryExpr();
    std::unique_ptr<ExprASTNode> parseAdditiveExpr();

private:
    Lexer m_lexer;
    Token m_currentToken;

    void consume();
    bool match(TokenType type);
    bool expect(TokenType type, const std::string& errorMessage);
    TypeSpec parseTypeSpec();
};

} // namespace llbc

#endif // LLBC_PARSER_HPP