/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
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

char Lexer::peekNext() const {
    if (m_cursor + 1 >= m_source.size()) return '\0';
    return m_source[m_cursor + 1];
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
    m_hasLeadingNewline = false;
    while (m_cursor < m_source.size()) {
        char c = peek();
        if (c == ' ' || c == '\t') {
            advance();
        } else if (c == '\r' || c == '\n') {
            m_hasLeadingNewline = true;
            advance();
        } else if (c == '\'') { // VB6 Style Comment
            m_hasLeadingNewline = true;
            while (peek() != '\n' && peek() != '\0') {
                advance();
            }
        } else if (c == '_') {
            // Line continuation: '_' followed by spaces, optional comment, then newline
            size_t probe = m_cursor + 1;
            while (probe < m_source.size() && (m_source[probe] == ' ' || m_source[probe] == '\t')) {
                probe++;
            }
            if (probe < m_source.size() && m_source[probe] == '\'') {
                while (probe < m_source.size() && m_source[probe] != '\n') {
                    probe++;
                }
            }
            if (probe < m_source.size() && (m_source[probe] == '\r' || m_source[probe] == '\n')) {
                advance(); // consume '_'
                while (peek() == ' ' || peek() == '\t') advance();
                if (peek() == '\'') {
                    while (peek() != '\n' && peek() != '\0') advance();
                }
                if (peek() == '\r') advance();
                if (peek() == '\n') advance();
                // Line continuation swallowed newline: do NOT set m_hasLeadingNewline
            } else {
                break;
            }
        } else {
            break;
        }
    }
}

TokenType Lexer::identifyKeyword(const std::string& text) const {
    // Convert to lowercase for case-insensitive VB syntax
    std::string lower;
    lower.reserve(text.size());
    for (char c : text) lower += static_cast<char>(std::tolower(c));

    static const std::unordered_map<std::string, TokenType> keywords = {
        {"module", TokenType::KwModule},
        {"class", TokenType::KwClass},
        {"structure", TokenType::KwStructure},
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
        {"import", TokenType::KwImport},
        {"if", TokenType::KwIf},
        {"then", TokenType::KwThen},
        {"elseif", TokenType::KwElseIf},
        {"else", TokenType::KwElse},
        {"for", TokenType::KwFor},
        {"next", TokenType::KwNext},
        {"step", TokenType::KwStep},
        {"do", TokenType::KwDo},
        {"loop", TokenType::KwLoop},
        {"while", TokenType::KwWhile},
        {"wend", TokenType::KwWend},
        {"until", TokenType::KwUntil},
        {"exit", TokenType::KwExit},
        {"select", TokenType::KwSelect},
        {"case", TokenType::KwCase},
        {"me", TokenType::KwMe},
        {"declare", TokenType::KwDeclare},
        {"const", TokenType::KwConst},
        {"optional", TokenType::KwOptional},
        {"delegate", TokenType::KwDelegate},
        {"call", TokenType::KwCall},
        {"true", TokenType::KwTrue},
        {"false", TokenType::KwFalse},
        {"cptr", TokenType::KwCPtr},
        {"ctype", TokenType::KwCType},
        {"enum", TokenType::KwEnum},
        {"with", TokenType::KwWith},
        {"using", TokenType::KwUsing},
        {"match", TokenType::KwMatch},
        {"lib", TokenType::KwLib},
        {"alias", TokenType::KwAlias},
        {"print", TokenType::KwPrint},
        {"input", TokenType::KwInput},
        {"type", TokenType::KwType},
        {"addressof", TokenType::KwAddressOf},
        {"property", TokenType::KwProperty},
        {"get", TokenType::KwGet},
        {"let", TokenType::KwLet},
        {"set", TokenType::KwSet},
        {"each", TokenType::KwEach},
        {"in", TokenType::KwIn},
        {"new", TokenType::KwNew},
        {"delete", TokenType::KwDelete},
        {"redim", TokenType::KwReDim},
        {"preserve", TokenType::KwPreserve},
        {"is", TokenType::KwIs},
        {"nothing", TokenType::KwNothing},
        {"erase", TokenType::KwErase},
        {"goto", TokenType::KwGoTo},
        {"try", TokenType::KwTry},
        {"catch", TokenType::KwCatch},
        {"finally", TokenType::KwFinally},
        {"paramarray", TokenType::KwParamArray},
        {"like", TokenType::KwLike},
        {"union", TokenType::KwUnion},
        {"typeof", TokenType::KwTypeOf},
        {"open", TokenType::KwOpen},
        {"close", TokenType::KwClose},
        {"output", TokenType::KwOutput},
        {"append", TokenType::KwAppend},
        {"binary", TokenType::KwBinary},
        {"line", TokenType::KwLine},
        {"eof", TokenType::KwEof},
        {"lof", TokenType::KwLof},
        {"interface", TokenType::KwInterface},
        {"implements", TokenType::KwImplements},
        {"namespace", TokenType::KwNamespace},
        {"of", TokenType::KwOf},
        {"and", TokenType::KwAnd},
        {"or", TokenType::KwOr},
        {"xor", TokenType::KwXor},
        {"not", TokenType::KwNot},
        {"lshift", TokenType::KwLShift},
        {"rshift", TokenType::KwRShift},
        {"mod", TokenType::KwMod}
    };

    auto it = keywords.find(lower);
    if (it != keywords.end()) return it->second;
    return TokenType::Identifier;
}

Token Lexer::peekToken() {
    size_t savedCursor = m_cursor;
    size_t savedLine = m_line;
    size_t savedCol = m_column;
    bool savedNewline = m_hasLeadingNewline;

    Token tok = nextToken();

    m_cursor = savedCursor;
    m_line = savedLine;
    m_column = savedCol;
    m_hasLeadingNewline = savedNewline;

    return tok;
}

Token Lexer::nextToken() {
    skipWhitespaceAndComments();

    if (m_cursor >= m_source.size()) {
        return Token{TokenType::Eof, "", m_line, m_column, m_hasLeadingNewline};
    }

    size_t startLine = m_line;
    size_t startCol = m_column;
    char c = advance();

    // Multi-character and single-character symbols
    switch (c) {
        case '=':
            if (peek() == '>') {
                advance();
                return makeToken(TokenType::FatArrow, "=>", startLine, startCol);
            }
            return makeToken(TokenType::Equal, "=", startLine, startCol);
        case '<':
            if (peek() == '>') {
                advance();
                return makeToken(TokenType::NotEqual, "<>", startLine, startCol);
            }
            if (peek() == '=') {
                advance();
                return makeToken(TokenType::LessEqual, "<=", startLine, startCol);
            }
            return makeToken(TokenType::Less, "<", startLine, startCol);
        case '>':
            if (peek() == '=') {
                advance();
                return makeToken(TokenType::GreaterEqual, ">=", startLine, startCol);
            }
            return makeToken(TokenType::Greater, ">", startLine, startCol);
        case ',': return makeToken(TokenType::Comma, ",", startLine, startCol);
        case ';': return makeToken(TokenType::Semicolon, ";", startLine, startCol);
        case '#': return makeToken(TokenType::Hash, "#", startLine, startCol);
        case '.': return makeToken(TokenType::Dot, ".", startLine, startCol);
        case '(': return makeToken(TokenType::LParen, "(", startLine, startCol);
        case ')': return makeToken(TokenType::RParen, ")", startLine, startCol);
        case ':':
            if (peek() == '=') {
                advance();
                return makeToken(TokenType::ColonEqual, ":=", startLine, startCol);
            }
            return makeToken(TokenType::Colon, ":", startLine, startCol);
        case '+': return makeToken(TokenType::Plus, "+", startLine, startCol);
        case '-': return makeToken(TokenType::Minus, "-", startLine, startCol);
        case '*': return makeToken(TokenType::Asterisk, "*", startLine, startCol);
        case '/': return makeToken(TokenType::Slash, "/", startLine, startCol);
        default: break;
    }

    // Identifiers & Keywords: starts with [A-Za-z_]
    if (std::isalpha(static_cast<unsigned char>(c)) || c == '_') {
        std::string text(1, c);
        while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') {
            text += advance();
        }
        TokenType type = identifyKeyword(text);
        return makeToken(type, text, startLine, startCol);
    }

    // Numeric Literals (Hex: &H... or &h..., Dec: digits)
    if (c == '&') {
        if (peek() == 'H' || peek() == 'h') {
            std::string text = "&";
            text += advance(); // consume 'H' or 'h'
            while (std::isxdigit(static_cast<unsigned char>(peek()))) {
                text += advance();
            }
            return makeToken(TokenType::NumberLiteral, text, startLine, startCol);
        }
        return makeToken(TokenType::Ampersand, "&", startLine, startCol);
    }

    if (std::isdigit(static_cast<unsigned char>(c))) {
        std::string text(1, c);
        while (std::isdigit(static_cast<unsigned char>(peek()))) {
            text += advance();
        }
        if (peek() == '.' && std::isdigit(static_cast<unsigned char>(peekNext()))) {
            text += advance(); // consume '.'
            while (std::isdigit(static_cast<unsigned char>(peek()))) {
                text += advance();
            }
            if (peek() == 'e' || peek() == 'E') {
                text += advance();
                if (peek() == '+' || peek() == '-') {
                    text += advance();
                }
                while (std::isdigit(static_cast<unsigned char>(peek()))) {
                    text += advance();
                }
            }
            if (peek() == 'f' || peek() == 'F' || peek() == '!') {
                text += advance();
            } else if (peek() == '#') {
                text += advance();
            }
        }
        return makeToken(TokenType::NumberLiteral, text, startLine, startCol);
    }

    // String Literals
    if (c == '"') {
        std::string text;
        while (peek() != '\0') {
            if (peek() == '"') {
                advance();
                // Check for double quotes in VB ("" -> ")
                if (peek() == '"') {
                    text += advance();
                } else {
                    break;
                }
            } else if (peek() == '\\') {
                advance(); // consume backslash
                char esc = advance();
                switch (esc) {
                    case 'n': text += '\n'; break;
                    case 't': text += '\t'; break;
                    case 'r': text += '\r'; break;
                    case '\\': text += '\\'; break;
                    case '"': text += '"'; break;
                    case '0': text += '\0'; break;
                    default:
                        text += '\\';
                        text += esc;
                        break;
                }
            } else {
                text += advance();
            }
        }
        return makeToken(TokenType::StringLiteral, text, startLine, startCol);
    }

    return makeToken(TokenType::Identifier, std::string(1, c), startLine, startCol);
}

Token Lexer::makeToken(TokenType type, const std::string& text, size_t line, size_t col) {
    return Token{type, text, line, col, m_hasLeadingNewline};
}

} // namespace llbc