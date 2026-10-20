/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
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
    KwStructure,
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
    KwUse,
    KwIf,
    KwThen,
    KwElseIf,
    KwElse,
    KwFor,
    KwNext,
    KwStep,
    KwDo,
    KwLoop,
    KwWhile,
    KwWend,
    KwUntil,
    KwExit,
    KwSelect,
    KwCase,
    KwMe,
    KwDeclare,
    KwConst,
    KwOptional,
    KwDelegate,
    KwCall,
    KwTrue,
    KwFalse,
    KwCPtr,
    KwCType,
    KwEnum,
    KwWith,
    KwUsing,
    KwMatch,
    KwLib,
    KwAlias,
    KwPrint,
    KwInput,
    KwType,
    KwAddressOf,
    KwProperty,
    KwGet,
    KwLet,
    KwSet,
    KwEach,
    KwIn,
    KwNew,
    KwDelete,
    KwReDim,
    KwPreserve,
    KwIs,
    KwNothing,
    KwErase,
    KwGoTo,
    KwTry,
    KwCatch,
    KwFinally,
    KwParamArray,
    KwLike,
    KwUnion,
    KwTypeOf,
    KwOpen,
    KwClose,
    KwOutput,
    KwAppend,
    KwBinary,
    KwLine,
    KwEof,
    KwLof,
    KwInterface,
    KwImplements,
    KwNamespace,
    KwOf,

    // Operators as keywords
    KwAnd,
    KwOr,
    KwXor,
    KwNot,
    KwLShift,
    KwRShift,
    KwMod,

    // Symbols & Operators
    Equal,          // =
    NotEqual,       // <>
    Less,           // <
    LessEqual,      // <=
    Greater,        // >
    GreaterEqual,   // >=
    Comma,          // ,
    Semicolon,      // ;
    Hash,           // #
    Dot,            // .
    LParen,         // (
    RParen,         // )
    Colon,          // :
    ColonEqual,     // :=
    FatArrow,       // =>
    Plus,           // +
    Minus,          // -
    Asterisk,       // *
    Slash,          // /
    Ampersand,      // &
    At              // @
};

struct Token {
    TokenType type{TokenType::Eof};
    std::string text;
    size_t line{1};
    size_t column{1};
    bool hasLeadingNewline{false};
};

class Lexer {
public:
    explicit Lexer(std::string source);
    Token nextToken();
    Token peekToken();
    const std::string& getSource() const { return m_source; }

private:
    std::string m_source;
    size_t m_cursor{0};
    size_t m_line{1};
    size_t m_column{1};
    bool m_hasLeadingNewline{false};

    char peek() const;
    char peekNext() const;
    char advance();
    void skipWhitespaceAndComments();
    Token makeToken(TokenType type, const std::string& text, size_t line, size_t col);
    TokenType identifyKeyword(const std::string& text) const;
};

} // namespace llbc

#endif // LLBC_LEXER_HPP