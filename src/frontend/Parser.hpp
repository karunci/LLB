/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/Parser.hpp
 * Summary: Recursive Descent Parser interface for Stage-0 bootstrap.
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

private:
    Lexer m_lexer;
    Token m_currentToken;

    void consume();
    bool match(TokenType type);
    bool expect(TokenType type, const std::string& errorMessage);

    TypeSpec parseTypeSpec();
    std::unique_ptr<DimStmtNode> parseDimStatement();
    std::unique_ptr<ProcedureNode> parseProcedure();
};

} // namespace llbc

#endif // LLBC_PARSER_HPP