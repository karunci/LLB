/*
 * Project Name: Low-Level Basic Compiler (llbc)
 * Filename: src/frontend/Parser.cpp
 * Summary: Parser implementation translating tokens into an AST representation.
 */

#include "Parser.hpp"
#include <iostream>
#include <stdexcept>

namespace llbc {

Parser::Parser(Lexer lexer) : m_lexer(std::move(lexer)) {
    consume(); // Load first token
}

void Parser::consume() {
    m_currentToken = m_lexer.nextToken();
}

bool Parser::match(TokenType type) {
    if (m_currentToken.type == type) {
        consume();
        return true;
    }
    return false;
}

bool Parser::expect(TokenType type, const std::string& errorMessage) {
    if (m_currentToken.type == type) {
        consume();
        return true;
    }
    std::cerr << "[Parser Error] Line " << m_currentToken.line 
              << ":" << m_currentToken.column << " - " 
              << errorMessage << " (Found: '" << m_currentToken.text << "')\n";
    throw std::runtime_error("Parse failure");
}

TypeSpec Parser::parseTypeSpec() {
    TypeSpec spec;
    if (match(TokenType::KwVolatile)) {
        spec.isVolatile = true;
    }
    
    // Support nested pointers (e.g., Pointer To Pointer To Byte)
    while (match(TokenType::KwPointer)) {
        expect(TokenType::KwTo, "Expected 'To' after 'Pointer'");
        spec.pointerDepth++;
    }

    spec.name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected type name identifier");
    return spec;
}

std::unique_ptr<DimStmtNode> Parser::parseDimStatement() {
    auto dimNode = std::make_unique<DimStmtNode>();
    expect(TokenType::Identifier, "Expected variable name after 'Dim'");
    dimNode->varName = m_currentToken.text;
    expect(TokenType::KwAs, "Expected 'As' in variable declaration");
    dimNode->type = parseTypeSpec();
    return dimNode;
}

std::unique_ptr<ProcedureNode> Parser::parseProcedure() {
    auto procNode = std::make_unique<ProcedureNode>();

    if (match(TokenType::KwPublic)) procNode->isPublic = true;
    else if (match(TokenType::KwPrivate)) procNode->isPublic = false;

    // Check for 'Declare' keyword (safely checking token text)
    if (m_currentToken.text == "Declare" || m_currentToken.text == "declare") {
        consume();
        procNode->isDeclare = true;
    }

    if (match(TokenType::KwUnsafe)) procNode->isUnsafe = true;

    if (match(TokenType::KwSub)) {
        procNode->isFunction = false;
    } else if (match(TokenType::KwFunction)) {
        procNode->isFunction = true;
    } else {
        throw std::runtime_error("Expected 'Sub' or 'Function'");
    }

    procNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected procedure name");

    expect(TokenType::LParen, "Expected '(' after procedure name");
    
    // Parse Parameters
    if (m_currentToken.type != TokenType::RParen) {
        do {
            ParameterNode param;
            if (match(TokenType::KwByRef)) param.isByRef = true;
            else match(TokenType::KwByVal);

            param.name = m_currentToken.text;
            expect(TokenType::Identifier, "Expected parameter identifier");
            expect(TokenType::KwAs, "Expected 'As' after parameter name");
            param.type = parseTypeSpec();

            procNode->parameters.push_back(param);
        } while (match(TokenType::Comma));
    }

    expect(TokenType::RParen, "Expected ')' after parameter list");

    if (procNode->isFunction) {
        expect(TokenType::KwAs, "Expected 'As' for Function return type");
        procNode->returnType = parseTypeSpec();
    }

    // External C declarations (Declare Function ...) have no body to parse
    if (procNode->isDeclare) {
        return procNode;
    }

    // Parse Procedure Body
    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd) {
            consume();
            if (procNode->isFunction && m_currentToken.type == TokenType::KwFunction) {
                consume();
                break;
            } else if (!procNode->isFunction && m_currentToken.type == TokenType::KwSub) {
                consume();
                break;
            } else {
                consume();
            }
        } else if (m_currentToken.type == TokenType::KwDim) {
            consume();
            procNode->body.push_back(parseDimStatement());
        } else if (m_currentToken.type == TokenType::Identifier) {
            // Parse Procedure Call (e.g., puts CPtr(...))
            auto callNode = std::make_unique<CallExprASTNode>();
            callNode->funcName = m_currentToken.text;
            consume(); // Consume function name

            // Consume arguments up to end of line or next statement
            while (m_currentToken.type != TokenType::Eof && 
                   m_currentToken.type != TokenType::KwDim && 
                   m_currentToken.type != TokenType::KwIf && 
                   m_currentToken.type != TokenType::KwEnd) {
                
                if (m_currentToken.type == TokenType::StringLiteral) {
                    callNode->stringArgs.push_back(m_currentToken.text);
                }
                consume();
            }
            procNode->body.push_back(std::move(callNode));
        } else {
            consume();
        }
    }

    return procNode;
}

std::unique_ptr<ModuleNode> Parser::parseModule() {
    auto moduleNode = std::make_unique<ModuleNode>();

    if (match(TokenType::KwModule)) {
        moduleNode->isClass = false;
    } else if (match(TokenType::KwClass)) {
        moduleNode->isClass = true;
    } else {
        throw std::runtime_error("Source file must begin with 'Module' or 'Class'");
    }

    moduleNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected module or class name");

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd) {
            consume(); // Consume 'End'
            if ((moduleNode->isClass && m_currentToken.type == TokenType::KwClass) ||
                (!moduleNode->isClass && m_currentToken.type == TokenType::KwModule)) {
                consume(); // Consume 'Class' or 'Module'
                break;
            } else {
                consume();
            }
        } else if (m_currentToken.type == TokenType::KwSub || 
                   m_currentToken.type == TokenType::KwFunction ||
                   m_currentToken.type == TokenType::KwUnsafe ||
                   m_currentToken.type == TokenType::KwPublic ||
                   m_currentToken.type == TokenType::KwPrivate ||
                   m_currentToken.text == "Declare" || m_currentToken.text == "declare") {
            moduleNode->members.push_back(parseProcedure());
        } else {
            consume(); // Top-level structure terminator (e.g., End Structure, End Type)
        }
    }

    return moduleNode;
}

} // namespace llbc