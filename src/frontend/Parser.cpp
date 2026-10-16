/*
 * Project Name: PRK-OS / Low-Level Basic Compiler
 * Filename: src/frontend/Parser.cpp
 * Workspace Path: src/frontend/Parser.cpp
 * Summary: Robust recursive descent parser supporting expressions, precedence, parentheses, nested control flow, and flexible keyword/identifier fallback.
 */

#include "Parser.hpp"
#include <iostream>
#include <stdexcept>

namespace llbc {

Parser::Parser(Lexer lexer) : m_lexer(std::move(lexer)) {
    consume();
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
    
    // Optional Volatile qualifier
    if (m_currentToken.text == "Volatile" || m_currentToken.text == "volatile" || m_currentToken.type == TokenType::KwVolatile) {
        consume();
        spec.isVolatile = true;
    }
    
    // Robust nested pointer unwrapping (Pointer To Pointer To ...)
    while (m_currentToken.text == "Pointer" || m_currentToken.text == "pointer" || m_currentToken.type == TokenType::KwPointer) {
        consume(); // Safely consume 'Pointer'
        
        if (m_currentToken.text == "To" || m_currentToken.text == "to" || m_currentToken.type == TokenType::KwTo) {
            consume(); // Safely consume 'To'
        } else {
            throw std::runtime_error("Expected 'To' after 'Pointer' at line " + std::to_string(m_currentToken.line));
        }
        spec.pointerDepth++;
    }

    // Capture base type name
    spec.name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected type name identifier");

    return spec;
}

std::unique_ptr<DimStmtNode> Parser::parseDimStatement() {
    auto dimNode = std::make_unique<DimStmtNode>();
    expect(TokenType::Identifier, "Expected variable name after 'Dim'");
    dimNode->varName = m_currentToken.text;
    
    if (m_currentToken.type == TokenType::KwAs || m_currentToken.text == "As" || m_currentToken.text == "as") {
        consume();
    } else {
        expect(TokenType::KwAs, "Expected 'As' in variable declaration");
    }
    
    dimNode->type = parseTypeSpec();
    return dimNode;
}

// Expression Parser with Parentheses and Binary Operators
std::unique_ptr<ExprASTNode> Parser::parseExpression() {
    return parseAdditiveExpr();
}

std::unique_ptr<ExprASTNode> Parser::parsePrimaryExpr() {
    if (m_currentToken.type == TokenType::StringLiteral) {
        auto node = std::make_unique<StringExprASTNode>(m_currentToken.text);
        consume();
        return node;
    }
    if (m_currentToken.type == TokenType::Identifier) {
        std::string name = m_currentToken.text;
        consume();
        // Function Call Expression
        if (match(TokenType::LParen)) {
            auto callNode = std::make_unique<CallExprASTNode>();
            callNode->funcName = name;
            if (m_currentToken.type != TokenType::RParen) {
                do {
                    callNode->args.push_back(parseExpression());
                } while (match(TokenType::Comma));
            }
            expect(TokenType::RParen, "Expected ')' after argument list");
            return callNode;
        }
        return std::make_unique<VariableExprASTNode>(name);
    }
    if (match(TokenType::LParen)) {
        auto node = parseExpression();
        expect(TokenType::RParen, "Expected ')' to close parenthesized expression");
        return node;
    }
    
    // Safely parse number literal or fallback to 0 if text is non-numeric
    int64_t val = 0;
    try {
        val = std::stoll(m_currentToken.text);
    } catch (...) {
        val = 0;
    }
    consume();
    return std::make_unique<NumberExprASTNode>(val);
}

std::unique_ptr<ExprASTNode> Parser::parseAdditiveExpr() {
    auto lhs = parsePrimaryExpr();
    while (m_currentToken.text == "+" || m_currentToken.text == "-" || m_currentToken.text == "<") {
        char op = m_currentToken.text[0];
        consume();
        auto rhs = parsePrimaryExpr();
        lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<IfStmtNode> Parser::parseIfStatement() {
    auto ifNode = std::make_unique<IfStmtNode>();
    
    IfBranch primaryBranch;
    consume(); // consume 'If'
    primaryBranch.condition = parseExpression();
    
    if (m_currentToken.text == "Then" || m_currentToken.text == "then") {
        consume();
    }

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.text == "ElseIf" || m_currentToken.text == "elseif" ||
            m_currentToken.text == "Else" || m_currentToken.text == "else" ||
            (m_currentToken.text == "End" || m_currentToken.text == "end")) {
            break;
        }
        if (match(TokenType::KwDim) || m_currentToken.text == "Dim" || m_currentToken.text == "dim") {
            if (m_currentToken.text == "Dim" || m_currentToken.text == "dim") consume();
            primaryBranch.body.push_back(parseDimStatement());
        } else {
            consume();
        }
    }
    ifNode->branches.push_back(std::move(primaryBranch));

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.text == "ElseIf" || m_currentToken.text == "elseif") {
            consume();
            IfBranch elseifBranch;
            elseifBranch.condition = parseExpression();
            if (m_currentToken.text == "Then" || m_currentToken.text == "then") consume();
            while (m_currentToken.type != TokenType::Eof &&
                   m_currentToken.text != "ElseIf" && m_currentToken.text != "elseif" &&
                   m_currentToken.text != "Else" && m_currentToken.text != "else" &&
                   m_currentToken.text != "End" && m_currentToken.text != "end") {
                consume();
            }
            ifNode->branches.push_back(std::move(elseifBranch));
        } else if (m_currentToken.text == "Else" || m_currentToken.text == "else") {
            consume();
            while (m_currentToken.type != TokenType::Eof &&
                   m_currentToken.text != "End" && m_currentToken.text != "end") {
                consume();
            }
        } else if (m_currentToken.text == "End" || m_currentToken.text == "end") {
            consume(); 
            if (m_currentToken.text == "If" || m_currentToken.text == "if") {
                consume(); 
            }
            break;
        } else {
            consume();
        }
    }

    return ifNode;
}

std::unique_ptr<ProcedureNode> Parser::parseProcedure() {
    auto procNode = std::make_unique<ProcedureNode>();

    if (match(TokenType::KwPublic) || m_currentToken.text == "Public" || m_currentToken.text == "public") {
        if (m_currentToken.text == "Public" || m_currentToken.text == "public") consume();
        procNode->isPublic = true;
    } else if (match(TokenType::KwPrivate) || m_currentToken.text == "Private" || m_currentToken.text == "private") {
        if (m_currentToken.text == "Private" || m_currentToken.text == "private") consume();
        procNode->isPublic = false;
    }

    if (m_currentToken.text == "Declare" || m_currentToken.text == "declare") {
        consume();
        procNode->isDeclare = true;
    }

    if (match(TokenType::KwUnsafe) || m_currentToken.text == "Unsafe" || m_currentToken.text == "unsafe") {
        if (m_currentToken.text == "Unsafe" || m_currentToken.text == "unsafe") consume();
        procNode->isUnsafe = true;
    }

    if (match(TokenType::KwSub) || m_currentToken.text == "Sub" || m_currentToken.text == "sub") {
        if (m_currentToken.text == "Sub" || m_currentToken.text == "sub") consume();
        procNode->isFunction = false;
    } else if (match(TokenType::KwFunction) || m_currentToken.text == "Function" || m_currentToken.text == "function") {
        if (m_currentToken.text == "Function" || m_currentToken.text == "function") consume();
        procNode->isFunction = true;
    } else {
        throw std::runtime_error("Expected 'Sub' or 'Function'");
    }

    procNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected procedure name");

    expect(TokenType::LParen, "Expected '(' after procedure name");
    
    if (m_currentToken.type != TokenType::RParen) {
        do {
            ParameterNode param;
            if (match(TokenType::KwByRef) || m_currentToken.text == "ByRef" || m_currentToken.text == "byref") {
                if (m_currentToken.text == "ByRef" || m_currentToken.text == "byref") consume();
                param.isByRef = true;
            } else {
                if (match(TokenType::KwByVal) || m_currentToken.text == "ByVal" || m_currentToken.text == "byval") {
                    if (m_currentToken.text == "ByVal" || m_currentToken.text == "byval") consume();
                }
            }

            param.name = m_currentToken.text;
            expect(TokenType::Identifier, "Expected parameter identifier");
            
            if (m_currentToken.type == TokenType::KwAs || m_currentToken.text == "As" || m_currentToken.text == "as") {
                consume();
            } else {
                expect(TokenType::KwAs, "Expected 'As' after parameter name");
            }
            
            param.type = parseTypeSpec();

            procNode->parameters.push_back(param);
        } while (match(TokenType::Comma));
    }

    expect(TokenType::RParen, "Expected ')' after parameter list");

    if (procNode->isFunction) {
        if (m_currentToken.type == TokenType::KwAs || m_currentToken.text == "As" || m_currentToken.text == "as") {
            consume();
        } else {
            expect(TokenType::KwAs, "Expected 'As' for Function return type");
        }
        procNode->returnType = parseTypeSpec();
    }

    if (procNode->isDeclare) {
        return procNode;
    }

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd) {
            consume();
            if (procNode->isFunction && (m_currentToken.type == TokenType::KwFunction || m_currentToken.text == "Function" || m_currentToken.text == "function")) {
                if (m_currentToken.type != TokenType::KwFunction) consume();
                break;
            } else if (!procNode->isFunction && (m_currentToken.type == TokenType::KwSub || m_currentToken.text == "Sub" || m_currentToken.text == "sub")) {
                if (m_currentToken.type != TokenType::KwSub) consume();
                break;
            } else {
                consume();
            }
        } else if (match(TokenType::KwDim) || m_currentToken.text == "Dim" || m_currentToken.text == "dim") {
            if (m_currentToken.text == "Dim" || m_currentToken.text == "dim") consume();
            procNode->body.push_back(parseDimStatement());
        } else if (m_currentToken.text == "If" || m_currentToken.text == "if") {
            procNode->body.push_back(parseIfStatement());
        } else if (m_currentToken.text == "Exit" || m_currentToken.text == "exit") {
            consume();
            if (m_currentToken.text == "Function" || m_currentToken.text == "function" ||
                m_currentToken.text == "Sub" || m_currentToken.text == "sub") {
                consume();
            }
        } else if (m_currentToken.type == TokenType::Identifier) {
            std::string ident = m_currentToken.text;
            consume();

            if (m_currentToken.text == "=") {
                consume();
                auto valExpr = parseExpression();
                auto assignNode = std::make_unique<AssignStmtNode>();
                assignNode->varName = ident;
                assignNode->value = std::move(valExpr);
                procNode->body.push_back(std::move(assignNode));
            } else {
                auto callNode = std::make_unique<CallExprASTNode>();
                callNode->funcName = ident;
                if (match(TokenType::LParen)) {
                    if (m_currentToken.type != TokenType::RParen) {
                        do {
                            callNode->args.push_back(parseExpression());
                        } while (match(TokenType::Comma));
                    }
                    expect(TokenType::RParen, "Expected ')'");
                }
                procNode->body.push_back(std::move(callNode));
            }
        } else {
            consume();
        }
    }

    return procNode;
}

std::unique_ptr<ModuleNode> Parser::parseModule() {
    auto moduleNode = std::make_unique<ModuleNode>();

    if (match(TokenType::KwModule) || m_currentToken.text == "Module" || m_currentToken.text == "module") {
        if (m_currentToken.text == "Module" || m_currentToken.text == "module") consume();
        moduleNode->isClass = false;
    } else if (match(TokenType::KwClass) || m_currentToken.text == "Class" || m_currentToken.text == "class") {
        if (m_currentToken.text == "Class" || m_currentToken.text == "class") consume();
        moduleNode->isClass = true;
    } else {
        throw std::runtime_error("Source file must begin with 'Module' or 'Class'");
    }

    moduleNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected module or class name");

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd) {
            consume();
            if ((moduleNode->isClass && (m_currentToken.type == TokenType::KwClass || m_currentToken.text == "Class" || m_currentToken.text == "class")) ||
                (!moduleNode->isClass && (m_currentToken.type == TokenType::KwModule || m_currentToken.text == "Module" || m_currentToken.text == "module"))) {
                if (m_currentToken.type != TokenType::KwClass && m_currentToken.type != TokenType::KwModule) consume();
                break;
            } else {
                consume();
            }
        } else if (match(TokenType::KwSub) || 
                   match(TokenType::KwFunction) ||
                   match(TokenType::KwUnsafe) ||
                   match(TokenType::KwPublic) ||
                   match(TokenType::KwPrivate) ||
                   m_currentToken.text == "Sub" || m_currentToken.text == "sub" ||
                   m_currentToken.text == "Function" || m_currentToken.text == "function" ||
                   m_currentToken.text == "Unsafe" || m_currentToken.text == "unsafe" ||
                   m_currentToken.text == "Public" || m_currentToken.text == "public" ||
                   m_currentToken.text == "Private" || m_currentToken.text == "private" ||
                   m_currentToken.text == "Declare" || m_currentToken.text == "declare") {
            moduleNode->members.push_back(parseProcedure());
        } else {
            consume();
        }
    }

    return moduleNode;
}

} // namespace llbc