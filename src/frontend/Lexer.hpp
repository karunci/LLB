/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/Lexer.hpp
 * Summary: Lexical analyzer interface for Stage-0 C++ bootstrap compiler.
 */

#ifndef LLBC_LEXER_HPP
#define LLBC_LEXER_HPP

#include <string>
#include <vector>
#include <string_view>

namespace llbc {

enum class TokenType {
    // EOF / Special
    Eof,
    Identifier,
    NumberLiteral,
    StringLiteral,

    // VB6 & LLB Keywords
    KwModule,
    KwClass,
    KwEnd,
    KwSub,
    KwFunction,
    KwDim,
    KwAs,
    KwByVal,
    KwByRef,
    KwPublic,
    KwPrivate,
    KwUnsafe,
    KwVolatile,
    KwPointer,
    KwTo,
    KwAsm,
    KwImport,

    // Symbols & Operators
    Equal,
    Comma,
    Dot,
    LParen,
    RParen,
    Colon,
    Plus,
    Minus,
    Asterisk,
    Slash
};

struct Token {
    TokenType type;
    std::string text;
    size_t line;
    size_t column;
};

class Lexer {
public:
    explicit Lexer(std::string source);
    Token nextToken();

private:
    std::string m_source;
    size_t m_cursor{0};
    size_t m_line{1};
    size_t m_column{1};

    char peek() const;
    char advance();
    void skipWhitespaceAndComments();
    Token makeToken(TokenType type, const std::string& text);
    TokenType identifyKeyword(const std::string& text) const;
};

} // namespace llbc

#endif // LLBC_LEXER_HPP