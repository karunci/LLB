/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/Lexer.cpp
 * Summary: Lexical analyzer implementation converting LLB source text into tokens.
 */

#include "Lexer.hpp"
#include <cctype>
#include <unordered_map>

namespace llbc {

Lexer::Lexer(std::string source) : m_source(std::move(source)) {}

char Lexer::peek() const {
    if (m_cursor >= m_source.size()) return '\0';
    return m_source[m_cursor];
}

char Lexer::advance() {
    if (m_cursor >= m_source.size()) return '\0';
    char c = m_source[m_cursor++];
    if (c == '\n') {
        m_line++;
        m_column = 1;
    } else {
        m_column++;
    }
    return c;
}

void Lexer::skipWhitespaceAndComments() {
    while (m_cursor < m_source.size()) {
        char c = peek();
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance();
        } else if (c == '\'') { // VB6 Style Comment
            while (peek() != '\n' && peek() != '\0') {
                advance();
            }
        } else {
            break;
        }
    }
}

TokenType Lexer::identifyKeyword(const std::string& text) const {
    // Convert to lowercase for case-insensitive VB syntax
    std::string lower;
    for (char c : text) lower += static_cast<char>(std::tolower(c));

    static const std::unordered_map<std::string, TokenType> keywords = {
        {"module", TokenType::KwModule},
        {"class", TokenType::KwClass},
        {"end", TokenType::KwEnd},
        {"sub", TokenType::KwSub},
        {"function", TokenType::KwFunction},
        {"dim", TokenType::KwDim},
        {"as", TokenType::KwAs},
        {"byval", TokenType::KwByVal},
        {"byref", TokenType::KwByRef},
        {"public", TokenType::KwPublic},
        {"private", TokenType::KwPrivate},
        {"unsafe", TokenType::KwUnsafe},
        {"volatile", TokenType::KwVolatile},
        {"pointer", TokenType::KwPointer},
        {"to", TokenType::KwTo},
        {"asm", TokenType::KwAsm},
        {"import", TokenType::KwImport}
    };

    auto it = keywords.find(lower);
    if (it != keywords.end()) return it->second;
    return TokenType::Identifier;
}

Token Lexer::nextToken() {
    skipWhitespaceAndComments();

    if (m_cursor >= m_source.size()) {
        return makeToken(TokenType::Eof, "");
    }

    size_t startLine = m_line;
    size_t startCol = m_column;
    char c = advance();

    // Single-character symbols
    switch (c) {
        case '=': return Token{TokenType::Equal, "=", startLine, startCol};
        case ',': return Token{TokenType::Comma, ",", startLine, startCol};
        case '.': return Token{TokenType::Dot, ".", startLine, startCol};
        case '(': return Token{TokenType::LParen, "(", startLine, startCol};
        case ')': return Token{TokenType::RParen, ")", startLine, startCol};
        case ':': return Token{TokenType::Colon, ":", startLine, startCol};
        case '+': return Token{TokenType::Plus, "+", startLine, startCol};
        case '-': return Token{TokenType::Minus, "-", startLine, startCol};
        case '*': return Token{TokenType::Asterisk, "*", startLine, startCol};
        case '/': return Token{TokenType::Slash, "/", startLine, startCol};
        default: break;
    }

    // Identifiers & Keywords
    if (std::isalpha(c) || c == '_') {
        std::string text(1, c);
        while (std::isalnum(peek()) || peek() == '_') {
            text += advance();
        }
        TokenType type = identifyKeyword(text);
        return Token{type, text, startLine, startCol};
    }

    // Numeric Literals (Hex & Dec)
    if (std::isdigit(c) || (c == '&' && (peek() == 'H' || peek() == 'h'))) {
        std::string text(1, c);
        if (c == '&') {
            text += advance(); // Accept 'H'
        }
        while (std::isxdigit(peek())) {
            text += advance();
        }
        return Token{TokenType::NumberLiteral, text, startLine, startCol};
    }

    // String Literals
    if (c == '"') {
        std::string text;
        while (peek() != '"' && peek() != '\0') {
            text += advance();
        }
        if (peek() == '"') advance(); // Consume closing quote
        return Token{TokenType::StringLiteral, text, startLine, startCol};
    }

    return Token{TokenType::Identifier, std::string(1, c), startLine, startCol};
}

Token Lexer::makeToken(TokenType type, const std::string& text) {
    return Token{type, text, m_line, m_column};
}

} // namespace llbc