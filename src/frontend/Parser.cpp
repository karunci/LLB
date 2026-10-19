/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

#include "Parser.hpp"
#include "Diagnostic.hpp"
#include <iostream>
#include <stdexcept>
#include <algorithm>

namespace llbc {

static std::string toLower(const std::string& str) {
    std::string res;
    res.reserve(str.size());
    for (char c : str) res += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return res;
}

Parser::Parser(Lexer lexer, std::unordered_map<std::string, int64_t> defines, std::string sourceFilePath)
    : m_lexer(std::move(lexer)), m_sourceFilePath(std::move(sourceFilePath)), m_condConstants(std::move(defines)) {
    // Default compiler preprocessor constants
    if (m_condConstants.find("__LLBC__") == m_condConstants.end()) {
        m_condConstants["__LLBC__"] = 1;
    }
    if (m_condConstants.find("__LLBC_STAGE0__") == m_condConstants.end()) {
        m_condConstants["__LLBC_STAGE0__"] = 1;
    }
    consume();
}

void Parser::reportError(const std::string& message, const Token* tok) {
    const Token& t = tok ? *tok : m_currentToken;
    Diagnostic::report(m_sourceFilePath, t.line, t.column, true, message, m_lexer.getSource());
}

int64_t Parser::evalCondPrimary() {
    if (match(TokenType::LParen)) {
        int64_t val = evalCondExpr();
        expect(TokenType::RParen, "Expected ')' in conditional expression");
        return val;
    }

    if (m_currentToken.type == TokenType::NumberLiteral) {
        std::string num = m_currentToken.text;
        consume();
        if (num.size() >= 2 && (num[0] == '&' && (num[1] == 'H' || num[1] == 'h'))) {
            return std::stoll(num.substr(2), nullptr, 16);
        }
        return std::stoll(num, nullptr, 10);
    }

    if (m_currentToken.type == TokenType::KwTrue || checkKeyword("True")) {
        consume();
        return -1; // VB6 True is -1
    }

    if (m_currentToken.type == TokenType::KwFalse || checkKeyword("False")) {
        consume();
        return 0;
    }

    if (m_currentToken.type == TokenType::Identifier) {
        std::string ident = m_currentToken.text;
        consume();
        auto it = m_condConstants.find(ident);
        if (it != m_condConstants.end()) {
            return it->second;
        }
        // Case-insensitive lookup fallback
        std::string lowerIdent = toLower(ident);
        for (const auto& kv : m_condConstants) {
            if (toLower(kv.first) == lowerIdent) {
                return kv.second;
            }
        }
        return 0; // Undefined preprocessor constants evaluate to 0 in VB
    }

    throw std::runtime_error("Unexpected token '" + m_currentToken.text + "' in conditional compilation expression");
}

int64_t Parser::evalCondUnary() {
    if (m_currentToken.type == TokenType::Minus) {
        consume();
        return -evalCondUnary();
    }
    if (m_currentToken.type == TokenType::Plus) {
        consume();
        return evalCondUnary();
    }
    if (m_currentToken.type == TokenType::KwNot || checkKeyword("Not")) {
        consume();
        return ~evalCondUnary();
    }
    return evalCondPrimary();
}

int64_t Parser::evalCondMultiplicative() {
    int64_t lhs = evalCondUnary();
    while (m_currentToken.type == TokenType::Asterisk || 
           m_currentToken.type == TokenType::Slash || 
           m_currentToken.type == TokenType::KwMod || checkKeyword("Mod")) {
        if (m_currentToken.type == TokenType::Asterisk) {
            consume();
            lhs = lhs * evalCondUnary();
        } else if (m_currentToken.type == TokenType::Slash) {
            consume();
            int64_t rhs = evalCondUnary();
            lhs = (rhs != 0) ? (lhs / rhs) : 0;
        } else {
            consume();
            int64_t rhs = evalCondUnary();
            lhs = (rhs != 0) ? (lhs % rhs) : 0;
        }
    }
    return lhs;
}

int64_t Parser::evalCondAdditive() {
    int64_t lhs = evalCondMultiplicative();
    while (m_currentToken.type == TokenType::Plus || m_currentToken.type == TokenType::Minus) {
        if (m_currentToken.type == TokenType::Plus) {
            consume();
            lhs = lhs + evalCondMultiplicative();
        } else {
            consume();
            lhs = lhs - evalCondMultiplicative();
        }
    }
    return lhs;
}

int64_t Parser::evalCondRelational() {
    int64_t lhs = evalCondAdditive();
    while (m_currentToken.type == TokenType::Less || 
           m_currentToken.type == TokenType::LessEqual ||
           m_currentToken.type == TokenType::Greater || 
           m_currentToken.type == TokenType::GreaterEqual) {
        TokenType op = m_currentToken.type;
        consume();
        int64_t rhs = evalCondAdditive();
        if (op == TokenType::Less) lhs = (lhs < rhs) ? -1 : 0;
        else if (op == TokenType::LessEqual) lhs = (lhs <= rhs) ? -1 : 0;
        else if (op == TokenType::Greater) lhs = (lhs > rhs) ? -1 : 0;
        else if (op == TokenType::GreaterEqual) lhs = (lhs >= rhs) ? -1 : 0;
    }
    return lhs;
}

int64_t Parser::evalCondEquality() {
    int64_t lhs = evalCondRelational();
    while (m_currentToken.type == TokenType::Equal || m_currentToken.type == TokenType::NotEqual) {
        TokenType op = m_currentToken.type;
        consume();
        int64_t rhs = evalCondRelational();
        if (op == TokenType::Equal) lhs = (lhs == rhs) ? -1 : 0;
        else lhs = (lhs != rhs) ? -1 : 0;
    }
    return lhs;
}

int64_t Parser::evalCondAnd() {
    int64_t lhs = evalCondEquality();
    while (m_currentToken.type == TokenType::KwAnd || checkKeyword("And")) {
        consume();
        lhs = lhs & evalCondEquality();
    }
    return lhs;
}

int64_t Parser::evalCondXor() {
    int64_t lhs = evalCondAnd();
    while (m_currentToken.type == TokenType::KwXor || checkKeyword("Xor")) {
        consume();
        lhs = lhs ^ evalCondAnd();
    }
    return lhs;
}

int64_t Parser::evalCondOr() {
    int64_t lhs = evalCondXor();
    while (m_currentToken.type == TokenType::KwOr || checkKeyword("Or")) {
        consume();
        lhs = lhs | evalCondXor();
    }
    return lhs;
}

int64_t Parser::evalCondExpr() {
    return evalCondOr();
}

void Parser::skipInactiveConditionalBlock() {
    int depth = 0;
    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::Hash) {
            Token next = m_lexer.peekToken();
            std::string kw = toLower(next.text);
            if (kw == "if") {
                depth++;
                consume(); // '#'
                consume(); // 'If'
                continue;
            } else if (kw == "end") {
                if (depth > 0) {
                    depth--;
                    consume(); // '#'
                    consume(); // 'End'
                    if (checkKeyword("If")) consume();
                    continue;
                } else {
                    // Reached matching '#End If' at our current level
                    return;
                }
            } else if (depth == 0 && (kw == "elseif" || kw == "else")) {
                // Reached next branch at our current level
                return;
            }
        }
        consume();
    }
}

void Parser::handleDirective() {
    expect(TokenType::Hash, "Expected '#' at start of directive");
    std::string dir = toLower(m_currentToken.text);
    consume();

    if (dir == "const") {
        std::string constName = m_currentToken.text;
        expect(TokenType::Identifier, "Expected identifier after #Const");
        expect(TokenType::Equal, "Expected '=' in #Const declaration");
        int64_t val = evalCondExpr();
        m_condConstants[constName] = val;
    } else if (dir == "if") {
        int64_t condVal = evalCondExpr();
        if (m_currentToken.type == TokenType::KwThen || checkKeyword("Then")) {
            consume();
        }
        bool isActive = (condVal != 0);
        m_condStack.push_back({isActive, isActive});
        if (!isActive) {
            skipInactiveConditionalBlock();
            handleDirective();
        }
    } else if (dir == "elseif") {
        if (m_condStack.empty()) {
            throw std::runtime_error("#ElseIf without #If");
        }
        int64_t condVal = evalCondExpr();
        if (m_currentToken.type == TokenType::KwThen || checkKeyword("Then")) {
            consume();
        }
        CondFrame& frame = m_condStack.back();
        if (!frame.anyBranchTaken && condVal != 0) {
            frame.anyBranchTaken = true;
            frame.currentBranchActive = true;
        } else {
            frame.currentBranchActive = false;
            skipInactiveConditionalBlock();
            handleDirective();
        }
    } else if (dir == "else") {
        if (m_condStack.empty()) {
            throw std::runtime_error("#Else without #If");
        }
        CondFrame& frame = m_condStack.back();
        if (!frame.anyBranchTaken) {
            frame.anyBranchTaken = true;
            frame.currentBranchActive = true;
        } else {
            frame.currentBranchActive = false;
            skipInactiveConditionalBlock();
            handleDirective();
        }
    } else if (dir == "end") {
        if (checkKeyword("If")) {
            consume();
        }
        if (m_condStack.empty()) {
            throw std::runtime_error("#End If without #If");
        }
        m_condStack.pop_back();
    } else {
        throw std::runtime_error("Unknown directive: #" + dir);
    }
}

void Parser::consume() {
    m_prevToken = m_currentToken;
    m_currentToken = m_lexer.nextToken();
}

bool Parser::check(TokenType type) const {
    return m_currentToken.type == type;
}

bool Parser::match(TokenType type) {
    if (m_currentToken.type == type) {
        consume();
        return true;
    }
    return false;
}

bool Parser::checkKeyword(const std::string& kw) const {
    return toLower(m_currentToken.text) == toLower(kw);
}

bool Parser::matchKeyword(const std::string& kw) {
    if (checkKeyword(kw)) {
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
    reportError(errorMessage + " (Found: '" + m_currentToken.text + "')");
    throw std::runtime_error("Parse failure");
}

TypeSpec Parser::parseTypeSpec() {
    TypeSpec spec;

    if (m_currentToken.type == TokenType::KwVolatile || checkKeyword("Volatile")) {
        consume();
        spec.isVolatile = true;
    }

    while (m_currentToken.type == TokenType::KwPointer || checkKeyword("Pointer")) {
        consume();
        if (m_currentToken.type == TokenType::KwTo || checkKeyword("To")) {
            consume();
            spec.pointerDepth++;
        } else {
            // Bare 'Pointer' (opaque pointer / void* / ptr)
            spec.pointerDepth++;
            spec.name = "Byte";
            return spec;
        }
    }

    if (m_currentToken.type == TokenType::Identifier || 
        !m_currentToken.text.empty()) {
        spec.name = m_currentToken.text;
        consume();

        // Support generic type arguments: e.g. Box(Of T) or Pair(Of K, V)
        if (match(TokenType::LParen)) {
            if (m_currentToken.type == TokenType::KwOf || checkKeyword("Of")) {
                consume();
            }
            do {
                spec.typeArgs.push_back(parseTypeSpec());
            } while (match(TokenType::Comma));
            expect(TokenType::RParen, "Expected ')' after generic type arguments");
        }
    } else {
        expect(TokenType::Identifier, "Expected type name identifier");
    }

    // Resolve Type Alias if registered
    auto aliasIt = m_typeAliases.find(spec.name);
    if (aliasIt != m_typeAliases.end()) {
        TypeSpec resolved = aliasIt->second;
        resolved.pointerDepth += spec.pointerDepth;
        if (spec.isVolatile) resolved.isVolatile = true;
        if (resolved.typeArgs.empty()) resolved.typeArgs = spec.typeArgs;
        return resolved;
    }

    return spec;

}

void Parser::parseTypeAlias() {
    // TypeAlias AliasName = TargetType
    std::string aliasName = m_currentToken.text;
    expect(TokenType::Identifier, "Expected alias identifier after 'TypeAlias'");
    expect(TokenType::Equal, "Expected '=' in TypeAlias definition");
    TypeSpec targetType = parseTypeSpec();
    m_typeAliases[aliasName] = targetType;
}

ImportDirective Parser::parseImportStatement() {
    ImportDirective directive;

    // Case 1: Import "path/file.bas"
    if (m_currentToken.type == TokenType::StringLiteral) {
        directive.filePath = m_currentToken.text;
        consume();
        return directive;
    }

    // Case 2 & 3: Import ModuleName[.Symbol] [As Alias] [In "path/file.bas"]
    std::string firstPart = m_currentToken.text;
    expect(TokenType::Identifier, "Expected module identifier or string path after 'Import'");

    if (match(TokenType::Dot)) {
        directive.moduleName = firstPart;
        directive.symbolName = m_currentToken.text;
        expect(TokenType::Identifier, "Expected symbol identifier after '.' in Import");
    } else {
        directive.moduleName = firstPart;
    }

    // Optional: As Alias
    if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
        consume();
        directive.aliasName = m_currentToken.text;
        expect(TokenType::Identifier, "Expected alias identifier after 'As'");
    }

    // Optional: In "path/file.bas"
    if (m_currentToken.type == TokenType::KwIn || checkKeyword("In")) {
        consume();
        if (m_currentToken.type == TokenType::StringLiteral) {
            directive.filePath = m_currentToken.text;
            consume();
        } else {
            expect(TokenType::StringLiteral, "Expected file path string after 'In'");
        }
    }

    return directive;
}

std::unique_ptr<DimStmtNode> Parser::parseDimStatement() {
    auto dimNode = std::make_unique<DimStmtNode>();
    
    // Identifier variable name
    std::string name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected variable name after 'Dim'");
    dimNode->varName = name;

    bool isArray = false;
    size_t arraySize = 0;
    std::vector<size_t> dimensions;

    // Optional array dimensions: Dim entries(256) or Dim matrix(3, 4) As Int32
    if (match(TokenType::LParen)) {
        isArray = true;
        do {
            size_t dim = 0;
            if (m_currentToken.type == TokenType::NumberLiteral) {
                try {
                    std::string numText = m_currentToken.text;
                    if (numText.size() >= 2 && (numText[0] == '&' && (numText[1] == 'H' || numText[1] == 'h'))) {
                        dim = std::stoull(numText.substr(2), nullptr, 16);
                    } else {
                        dim = std::stoull(numText, nullptr, 10);
                    }
                } catch (...) {
                    dim = 0;
                }
                consume();
            }
            dimensions.push_back(dim);
        } while (match(TokenType::Comma));

        if (!dimensions.empty()) {
            arraySize = dimensions[0];
            for (size_t i = 1; i < dimensions.size(); ++i) {
                arraySize *= dimensions[i];
            }
        }
        expect(TokenType::RParen, "Expected ')' after array dimension");
    }

    if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
        consume();
    } else {
        expect(TokenType::KwAs, "Expected 'As' in variable declaration");
    }

    dimNode->type = parseTypeSpec();
    dimNode->type.isArray = isArray;
    dimNode->type.arraySize = arraySize;
    dimNode->type.dimensions = dimensions;

    if (match(TokenType::Equal)) {
        dimNode->initValue = parseExpression();
    }

    return dimNode;
}

std::unique_ptr<ConstStmtNode> Parser::parseConstStatement(bool isPublic) {
    auto constNode = std::make_unique<ConstStmtNode>();
    constNode->isPublic = isPublic;

    std::string name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected constant identifier");
    constNode->name = name;

    if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
        consume();
        constNode->type = parseTypeSpec();
    }

    expect(TokenType::Equal, "Expected '=' in constant declaration");
    constNode->value = parseExpression();
    return constNode;
}

std::unique_ptr<IfStmtNode> Parser::parseIfStatement() {
    auto ifNode = std::make_unique<IfStmtNode>();

    IfBranch primaryBranch;
    primaryBranch.condition = parseExpression();

    if (m_currentToken.type == TokenType::KwThen || checkKeyword("Then")) {
        consume();
    } else {
        expect(TokenType::KwThen, "Expected 'Then' after If condition");
    }

    size_t thenLine = m_prevToken.line;

    // Check for single-line If: statements on the same line after 'Then'
    if (m_currentToken.line == thenLine && 
        m_currentToken.type != TokenType::Eof && 
        m_currentToken.type != TokenType::Colon) {
        
        primaryBranch.body.push_back(parseStatement());

        if (m_currentToken.line == thenLine && 
            (m_currentToken.type == TokenType::KwElse || checkKeyword("Else"))) {
            consume();
            ifNode->elseBody.push_back(parseStatement());
        }

        ifNode->branches.push_back(std::move(primaryBranch));
        return ifNode;
    }

    // Block If: parse statements until ElseIf, Else, or End If
    primaryBranch.body = parseStatementBlock({"ElseIf", "Else", "End"});
    ifNode->branches.push_back(std::move(primaryBranch));

    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwElseIf || checkKeyword("ElseIf")) {
            consume();
            IfBranch elseifBranch;
            elseifBranch.condition = parseExpression();
            if (m_currentToken.type == TokenType::KwThen || checkKeyword("Then")) {
                consume();
            }
            elseifBranch.body = parseStatementBlock({"ElseIf", "Else", "End"});
            ifNode->branches.push_back(std::move(elseifBranch));
        } else if (m_currentToken.type == TokenType::KwElse || checkKeyword("Else")) {
            consume();
            ifNode->elseBody = parseStatementBlock({"End"});
        } else if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwIf || checkKeyword("If")) {
                consume();
            }
            break;
        } else {
            break;
        }
    }

    return ifNode;
}

std::unique_ptr<ForStmtNode> Parser::parseForStatement() {
    auto forNode = std::make_unique<ForStmtNode>();

    std::string varName = m_currentToken.text;
    expect(TokenType::Identifier, "Expected variable name after 'For'");
    forNode->varName = varName;

    expect(TokenType::Equal, "Expected '=' in For loop header");
    forNode->startExpr = parseExpression();

    if (m_currentToken.type == TokenType::KwTo || checkKeyword("To")) {
        consume();
    } else {
        expect(TokenType::KwTo, "Expected 'To' in For loop");
    }

    forNode->endExpr = parseExpression();

    if (m_currentToken.type == TokenType::KwStep || checkKeyword("Step")) {
        consume();
        forNode->stepExpr = parseExpression();
    }

    forNode->body = parseStatementBlock({"Next"});

    if (m_currentToken.type == TokenType::KwNext || checkKeyword("Next")) {
        consume();
        // Optional loop variable after Next, e.g. "Next i"
        if (m_currentToken.type == TokenType::Identifier) {
            consume();
        }
    }

    return forNode;
}

std::unique_ptr<ForEachStmtNode> Parser::parseForEachStatement() {
    auto forEachNode = std::make_unique<ForEachStmtNode>();

    std::string varName = m_currentToken.text;
    expect(TokenType::Identifier, "Expected element variable name after 'For Each'");
    forEachNode->varName = varName;

    if (m_currentToken.type == TokenType::KwIn || checkKeyword("In")) {
        consume();
    } else {
        expect(TokenType::KwIn, "Expected 'In' after element variable in For Each loop");
    }

    forEachNode->collectionExpr = parseExpression();

    forEachNode->body = parseStatementBlock({"Next"});

    if (m_currentToken.type == TokenType::KwNext || checkKeyword("Next")) {
        consume();
        // Optional loop variable after Next, e.g. "Next item"
        if (m_currentToken.type == TokenType::Identifier) {
            consume();
        }
    }

    return forEachNode;
}

std::unique_ptr<DoLoopStmtNode> Parser::parseDoLoopStatement() {
    auto doNode = std::make_unique<DoLoopStmtNode>();

    if (m_currentToken.type == TokenType::KwWhile || checkKeyword("While")) {
        consume();
        doNode->loopType = DoLoopStmtNode::LoopType::PreWhile;
        doNode->condition = parseExpression();
    } else if (m_currentToken.type == TokenType::KwUntil || checkKeyword("Until")) {
        consume();
        doNode->loopType = DoLoopStmtNode::LoopType::PreUntil;
        doNode->condition = parseExpression();
    } else {
        doNode->loopType = DoLoopStmtNode::LoopType::Infinite;
    }

    doNode->body = parseStatementBlock({"Loop"});

    if (m_currentToken.type == TokenType::KwLoop || checkKeyword("Loop")) {
        consume();
        if (m_currentToken.type == TokenType::KwWhile || checkKeyword("While")) {
            consume();
            doNode->loopType = DoLoopStmtNode::LoopType::PostWhile;
            doNode->condition = parseExpression();
        } else if (m_currentToken.type == TokenType::KwUntil || checkKeyword("Until")) {
            consume();
            doNode->loopType = DoLoopStmtNode::LoopType::PostUntil;
            doNode->condition = parseExpression();
        }
    }

    return doNode;
}

std::unique_ptr<WhileStmtNode> Parser::parseWhileStatement() {
    auto whileNode = std::make_unique<WhileStmtNode>();
    whileNode->condition = parseExpression();

    whileNode->body = parseStatementBlock({"Wend"});

    if (m_currentToken.type == TokenType::KwWend || checkKeyword("Wend")) {
        consume();
    }

    return whileNode;
}

std::unique_ptr<ExitStmtNode> Parser::parseExitStatement() {
    if (m_currentToken.type == TokenType::KwSub || checkKeyword("Sub")) {
        consume();
        return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::Sub);
    }
    if (m_currentToken.type == TokenType::KwFunction || checkKeyword("Function")) {
        consume();
        return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::Function);
    }
    if (m_currentToken.type == TokenType::KwFor || checkKeyword("For")) {
        consume();
        return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::For);
    }
    if (m_currentToken.type == TokenType::KwDo || checkKeyword("Do")) {
        consume();
        return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::Do);
    }
    if (m_currentToken.type == TokenType::KwWhile || checkKeyword("While")) {
        consume();
        return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::While);
    }

    return std::make_unique<ExitStmtNode>(ExitStmtNode::ExitKind::Sub);
}

std::unique_ptr<SelectStmtNode> Parser::parseSelectStatement() {
    auto selectNode = std::make_unique<SelectStmtNode>();

    if (m_currentToken.type == TokenType::KwCase || checkKeyword("Case")) {
        consume();
    } else {
        expect(TokenType::KwCase, "Expected 'Case' after 'Select'");
    }

    selectNode->expr = parseExpression();

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwSelect || checkKeyword("Select")) {
                consume();
            }
            break;
        }

        if (m_currentToken.type == TokenType::KwCase || checkKeyword("Case")) {
            consume();
            CaseBranch branch;
            if (m_currentToken.type == TokenType::KwElse || checkKeyword("Else")) {
                consume();
                branch.isElse = true;
            } else {
                do {
                    branch.values.push_back(parseExpression());
                } while (match(TokenType::Comma));
            }

            branch.body = parseStatementBlock({"Case", "End"});
            selectNode->branches.push_back(std::move(branch));
        } else {
            consume();
        }
    }

    return selectNode;
}

std::unique_ptr<MatchStmtNode> Parser::parseMatchStatement() {
    auto matchNode = std::make_unique<MatchStmtNode>();

    matchNode->expr = parseExpression();

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwMatch || checkKeyword("Match")) {
                consume();
            }
            break;
        }

        if (m_currentToken.type == TokenType::KwCase || checkKeyword("Case")) {
            consume();
            MatchCaseBranch branch;

            if (m_currentToken.type == TokenType::KwElse || checkKeyword("Else")) {
                consume();
                branch.isElse = true;
            } else if (m_currentToken.type == TokenType::Identifier && m_currentToken.text == "_") {
                consume();
                branch.isElse = true;
            } else {
                do {
                    MatchPattern pat;
                    if (m_currentToken.type == TokenType::Identifier && (toLower(m_currentToken.text) == "ok" || toLower(m_currentToken.text) == "err") && m_lexer.peekToken().type == TokenType::LParen) {
                        std::string constructor = toLower(m_currentToken.text);
                        consume(); // 'Ok' or 'Err'
                        consume(); // '('
                        std::string boundVar = "";
                        if (m_currentToken.type == TokenType::Identifier) {
                            boundVar = m_currentToken.text;
                            consume();
                        }
                        expect(TokenType::RParen, "Expected ')' after pattern constructor");
                        pat.kind = (constructor == "ok") ? MatchPattern::Kind::OkPattern : MatchPattern::Kind::ErrPattern;
                        pat.boundVar = boundVar;
                    } else if (m_currentToken.type == TokenType::Identifier && m_currentToken.text == "_") {
                        consume();
                        pat.kind = MatchPattern::Kind::Wildcard;
                    } else {
                        pat.expr = parseExpression();
                        if (m_currentToken.type == TokenType::KwTo || checkKeyword("To")) {
                            consume(); // 'To'
                            pat.rangeEnd = parseExpression();
                            pat.kind = MatchPattern::Kind::Range;
                        } else {
                            pat.kind = MatchPattern::Kind::Value;
                        }
                    }
                    branch.patterns.push_back(std::move(pat));
                } while (match(TokenType::Comma));
            }

            branch.body = parseStatementBlock({"Case", "End"});
            matchNode->branches.push_back(std::move(branch));
        } else {
            consume();
        }
    }

    return matchNode;
}

std::unique_ptr<AsmStmtNode> Parser::parseAsmStatement() {
    // Single-line Asm on same line, e.g.: Asm "hlt"
    if (m_currentToken.type == TokenType::StringLiteral && !m_currentToken.hasLeadingNewline) {
        std::string code = m_currentToken.text;
        consume();
        return std::make_unique<AsmStmtNode>(code);
    }

    // Multiline Asm block until 'End Asm'
    std::string fullCode;
    std::string constraintsStr;
    std::vector<std::unique_ptr<ExprASTNode>> inputs;

    // Phase 0: Template strings
    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwAsm || checkKeyword("Asm")) {
                consume();
            }
            auto node = std::make_unique<AsmStmtNode>(fullCode);
            return node;
        }

        if (m_currentToken.type == TokenType::Colon) {
            // Reached output operands separator ':'
            break;
        }

        if (m_currentToken.type == TokenType::StringLiteral) {
            if (!fullCode.empty()) fullCode += "\n";
            fullCode += m_currentToken.text;
            consume();
        } else {
            consume();
        }
    }

    // Phase 1: Output operands (after first ':')
    if (m_currentToken.type == TokenType::Colon) {
        consume();
        while (m_currentToken.type != TokenType::Colon &&
               m_currentToken.type != TokenType::KwEnd && !checkKeyword("End") &&
               m_currentToken.type != TokenType::Eof) {
            // For future output operands handling
            consume();
        }
    }

    // Phase 2: Input operands (after second ':')
    if (m_currentToken.type == TokenType::Colon) {
        consume();
        while (m_currentToken.type != TokenType::Colon &&
               m_currentToken.type != TokenType::KwEnd && !checkKeyword("End") &&
               m_currentToken.type != TokenType::Eof) {
            if (m_currentToken.type == TokenType::StringLiteral) {
                std::string c = m_currentToken.text;
                consume();
                if (!constraintsStr.empty()) constraintsStr += ",";
                constraintsStr += c;

                if (match(TokenType::LParen)) {
                    inputs.push_back(parseExpression());
                    expect(TokenType::RParen, "Expected ')' after input operand expression in Asm");
                }
            } else if (match(TokenType::Comma)) {
                continue;
            } else {
                consume();
            }
        }
    }

    // Phase 3: Clobbers (after third ':')
    if (m_currentToken.type == TokenType::Colon) {
        consume();
        while (m_currentToken.type != TokenType::KwEnd && !checkKeyword("End") &&
               m_currentToken.type != TokenType::Eof) {
            if (m_currentToken.type == TokenType::StringLiteral) {
                std::string clobber = "~{" + m_currentToken.text + "}";
                consume();
                if (!constraintsStr.empty()) constraintsStr += ",";
                constraintsStr += clobber;
            } else if (match(TokenType::Comma)) {
                continue;
            } else {
                consume();
            }
        }
    }

    // Consume trailing 'End Asm'
    while (m_currentToken.type != TokenType::Eof) {
        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwAsm || checkKeyword("Asm")) {
                consume();
            }
            break;
        }
        consume();
    }

    // Always include standard clobbers if not already present
    if (!constraintsStr.empty()) {
        constraintsStr += ",~{dirflag},~{fpsr},~{flags}";
    } else {
        constraintsStr = "~{dirflag},~{fpsr},~{flags}";
    }

    auto node = std::make_unique<AsmStmtNode>(fullCode);
    node->constraints = constraintsStr;
    node->inputOperands = std::move(inputs);
    return node;
}

std::unique_ptr<WithStmtNode> Parser::parseWithStatement() {
    auto withNode = std::make_unique<WithStmtNode>();
    withNode->target = parseExpression();
    m_withDepth++;
    withNode->body = parseStatementBlock({"End"});
    m_withDepth--;

    if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
        consume();
        if (m_currentToken.type == TokenType::KwWith || checkKeyword("With")) {
            consume();
        }
    }
    return withNode;
}

std::unique_ptr<UsingStmtNode> Parser::parseUsingStatement() {
    auto usingNode = std::make_unique<UsingStmtNode>();

    if (m_currentToken.type == TokenType::Identifier) {
        usingNode->varName = m_currentToken.text;
        consume();

        if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
            consume();
            usingNode->type = parseTypeSpec();
        }

        if (match(TokenType::Equal)) {
            usingNode->initExpr = parseExpression();
        }
    } else {
        usingNode->initExpr = parseExpression();
    }

    usingNode->body = parseStatementBlock({"End"});

    if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
        consume();
        if (m_currentToken.type == TokenType::KwUsing || checkKeyword("Using")) {
            consume();
        }
    }
    return usingNode;
}

std::unique_ptr<ASTNode> Parser::parseAssignOrCallStatement() {
    auto targetExpr = parsePostfixExpr();

    // Check if target is a label definition: e.g. "MyLabel:"
    if (m_currentToken.type == TokenType::Colon) {
        if (auto var = dynamic_cast<VariableExprASTNode*>(targetExpr.get())) {
            consume(); // consume ':'
            return std::make_unique<LabelStmtNode>(var->name);
        }
    }

    // Check if followed by '=' -> Assignment
    if (match(TokenType::Equal)) {
        auto assignNode = std::make_unique<AssignStmtNode>();

        // If target was parsed as CallExprASTNode (e.g. buffer(i) or matrix(r, c) or arr(i)(j)), convert to IndexExprASTNode
        std::function<std::unique_ptr<ExprASTNode>(std::unique_ptr<ExprASTNode>)> convertCallToIndex =
            [&](std::unique_ptr<ExprASTNode> node) -> std::unique_ptr<ExprASTNode> {
                if (auto call = dynamic_cast<CallExprASTNode*>(node.get())) {
                    if (!call->args.empty()) {
                        std::unique_ptr<ExprASTNode> base;
                        if (call->calleeExpr) {
                            base = convertCallToIndex(std::move(call->calleeExpr));
                        } else {
                            base = std::make_unique<VariableExprASTNode>(call->funcName);
                        }
                        if (call->args.size() == 1) {
                            return std::make_unique<IndexExprASTNode>(std::move(base), std::move(call->args[0]));
                        } else {
                            return std::make_unique<IndexExprASTNode>(std::move(base), std::move(call->args));
                        }
                    }
                }
                return node;
            };
        targetExpr = convertCallToIndex(std::move(targetExpr));

        assignNode->target = std::move(targetExpr);
        assignNode->value = parseExpression();
        return assignNode;
    }

    // Otherwise, this is a procedure call statement
    // Case A: targetExpr is already a CallExprASTNode with parens: func(arg1, arg2)
    if (auto call = dynamic_cast<CallExprASTNode*>(targetExpr.get())) {
        std::unique_ptr<CallExprASTNode> callPtr(static_cast<CallExprASTNode*>(targetExpr.release()));
        return std::make_unique<CallStmtNode>(std::move(callPtr));
    }

    // Case B: Unparenthesized call: SubName arg1, arg2
    auto callNode = std::make_unique<CallExprASTNode>();
    if (auto var = dynamic_cast<VariableExprASTNode*>(targetExpr.get())) {
        callNode->funcName = var->name;
    } else if (auto member = dynamic_cast<MemberAccessExprASTNode*>(targetExpr.get())) {
        callNode->funcName = member->memberName;
        callNode->calleeExpr = std::move(member->base);
    } else {
        callNode->funcName = "";
    }

    size_t callLine = m_prevToken.line;

    // Parse comma-separated arguments on the same line
    // Do not parse if at colon, newline, or block-closing keywords
    if (m_currentToken.line == callLine && 
        m_currentToken.type != TokenType::Colon && 
        m_currentToken.type != TokenType::Eof &&
        !checkKeyword("End") && !checkKeyword("Else") && !checkKeyword("ElseIf") &&
        !checkKeyword("Loop") && !checkKeyword("Next") && !checkKeyword("Wend")) {
        
        do {
            if (m_currentToken.type == TokenType::Identifier && m_lexer.peekToken().type == TokenType::ColonEqual) {
                std::string argName = m_currentToken.text;
                consume(); // identifier
                consume(); // ':='
                auto exprVal = parseExpression();
                callNode->namedArgs.push_back({argName, std::move(exprVal)});
            } else {
                auto exprVal = parseExpression();
                callNode->args.push_back(std::move(exprVal));
            }
        } while (match(TokenType::Comma));
    }

    return std::make_unique<CallStmtNode>(std::move(callNode));
}

std::unique_ptr<ASTNode> Parser::parseStatement() {
    while (match(TokenType::Colon)) {}

    // Preprocessor Directives
    while (m_currentToken.type == TokenType::Hash) {
        handleDirective();
        while (match(TokenType::Colon)) {}
    }

    size_t stmtLine = m_currentToken.line;
    size_t stmtCol = m_currentToken.column;

    std::unique_ptr<ASTNode> result;

    if (m_currentToken.type == TokenType::KwDim || checkKeyword("Dim")) {
        consume();
        result = parseDimStatement();
    } else if (m_currentToken.type == TokenType::KwConst || checkKeyword("Const")) {
        consume();
        result = parseConstStatement(false);
    } else if (m_currentToken.type == TokenType::KwIf || checkKeyword("If")) {
        consume();
        result = parseIfStatement();
    } else if (m_currentToken.type == TokenType::KwFor || checkKeyword("For")) {
        consume();
        if (m_currentToken.type == TokenType::KwEach || checkKeyword("Each")) {
            consume();
            result = parseForEachStatement();
        } else {
            result = parseForStatement();
        }
    } else if (m_currentToken.type == TokenType::KwDo || checkKeyword("Do")) {
        consume();
        result = parseDoLoopStatement();
    } else if (m_currentToken.type == TokenType::KwWhile || checkKeyword("While")) {
        consume();
        result = parseWhileStatement();
    } else if (m_currentToken.type == TokenType::KwExit || checkKeyword("Exit")) {
        consume();
        result = parseExitStatement();
    } else if (m_currentToken.type == TokenType::KwSelect || checkKeyword("Select")) {
        consume();
        result = parseSelectStatement();
    } else if (m_currentToken.type == TokenType::KwMatch || checkKeyword("Match")) {
        consume();
        result = parseMatchStatement();
    } else if (m_currentToken.type == TokenType::KwAsm || checkKeyword("Asm")) {
        consume();
        result = parseAsmStatement();
    } else if (m_currentToken.type == TokenType::KwWith || checkKeyword("With")) {
        consume();
        result = parseWithStatement();
    } else if (m_currentToken.type == TokenType::KwUsing || checkKeyword("Using")) {
        consume();
        result = parseUsingStatement();
    } else if (m_currentToken.type == TokenType::KwOpen || checkKeyword("Open")) {
        consume();
        result = parseOpenStatement();
    } else if (m_currentToken.type == TokenType::KwClose || checkKeyword("Close")) {
        consume();
        result = parseCloseStatement();
    } else if (m_currentToken.type == TokenType::KwLine || checkKeyword("Line")) {
        consume();
        if (m_currentToken.type == TokenType::KwInput || checkKeyword("Input")) {
            consume();
            result = parseLineInputStatement();
        }
    } else if (m_currentToken.type == TokenType::KwPrint || checkKeyword("Print")) {
        consume();
        result = parsePrintOrPrintFileStatement();
    } else if (m_currentToken.type == TokenType::KwInput || checkKeyword("Input")) {
        consume();
        result = parseInputOrInputFileStatement();
    } else if (m_currentToken.type == TokenType::KwDelete || checkKeyword("Delete")) {
        consume();
        result = parseDeleteStatement();
    } else if (m_currentToken.type == TokenType::KwReDim || checkKeyword("ReDim")) {
        consume();
        result = parseReDimStatement();
    } else if (m_currentToken.type == TokenType::KwErase || checkKeyword("Erase")) {
        consume();
        result = parseEraseStatement();
    } else if (m_currentToken.type == TokenType::KwGoTo || checkKeyword("GoTo")) {
        consume();
        result = parseGoToStatement();
    } else if (m_currentToken.type == TokenType::KwTry || checkKeyword("Try")) {
        consume();
        result = parseTryStatement();
    } else {
        result = parseAssignOrCallStatement();
    }

    if (result) {
        result->line = stmtLine;
        result->column = stmtCol;
    }
    return result;
}

std::unique_ptr<GoToStmtNode> Parser::parseGoToStatement() {
    std::string targetLabel = m_currentToken.text;
    expect(TokenType::Identifier, "Expected label identifier after 'GoTo'");
    return std::make_unique<GoToStmtNode>(targetLabel);
}

std::unique_ptr<TryStmtNode> Parser::parseTryStatement() {
    auto tryNode = std::make_unique<TryStmtNode>();

    // Parse try body until Catch, Finally, or End
    tryNode->tryBody = parseStatementBlock({"Catch", "Finally", "End"});

    if (m_currentToken.type == TokenType::KwCatch || checkKeyword("Catch")) {
        consume();
        // Optional catch variable: e.g. Catch ex As Int32 or Catch ex
        if (m_currentToken.type == TokenType::Identifier) {
            tryNode->catchVarName = m_currentToken.text;
            consume();
            if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                consume();
                parseTypeSpec(); // consume optional type specification
            }
        }
        tryNode->catchBody = parseStatementBlock({"Finally", "End"});
    }

    if (m_currentToken.type == TokenType::KwFinally || checkKeyword("Finally")) {
        consume();
        tryNode->finallyBody = parseStatementBlock({"End"});
    }

    if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
        consume();
        if (m_currentToken.type == TokenType::KwTry || checkKeyword("Try")) {
            consume();
        }
    }

    return tryNode;
}

std::unique_ptr<DeleteStmtNode> Parser::parseDeleteStatement() {
    auto delNode = std::make_unique<DeleteStmtNode>();
    delNode->target = parsePostfixExpr();
    return delNode;
}

std::unique_ptr<ReDimStmtNode> Parser::parseReDimStatement() {
    auto redimNode = std::make_unique<ReDimStmtNode>();
    if (m_currentToken.type == TokenType::KwPreserve || checkKeyword("Preserve")) {
        consume();
        redimNode->isPreserve = true;
    }

    redimNode->varName = m_currentToken.text;
    expect(TokenType::Identifier, "Expected array identifier after 'ReDim'");

    expect(TokenType::LParen, "Expected '(' after array identifier in 'ReDim'");
    if (!check(TokenType::RParen)) {
        do {
            redimNode->dimensions.push_back(parseExpression());
        } while (match(TokenType::Comma));
    }
    expect(TokenType::RParen, "Expected ')' after dimensions in 'ReDim'");

    return redimNode;
}

std::unique_ptr<EraseStmtNode> Parser::parseEraseStatement() {
    auto eraseNode = std::make_unique<EraseStmtNode>();
    eraseNode->varName = m_currentToken.text;
    eraseNode->targetExpr = parsePostfixExpr();
    return eraseNode;
}

std::unique_ptr<PrintStmtNode> Parser::parsePrintStatement() {
    auto printNode = std::make_unique<PrintStmtNode>();
    size_t printLine = m_prevToken.line;

    while (m_currentToken.line == printLine &&
           m_currentToken.type != TokenType::Colon &&
           m_currentToken.type != TokenType::Eof &&
           !checkKeyword("End") && !checkKeyword("Else") && !checkKeyword("ElseIf") &&
           !checkKeyword("Loop") && !checkKeyword("Next") && !checkKeyword("Wend")) {

        if (m_currentToken.type == TokenType::Semicolon) {
            consume();
            printNode->hasTrailingSeparator = true;
            continue;
        }
        if (m_currentToken.type == TokenType::Comma) {
            consume();
            PrintItem item;
            item.expr = nullptr;
            item.separator = ',';
            printNode->items.push_back(std::move(item));
            printNode->hasTrailingSeparator = true;
            continue;
        }

        PrintItem item;
        item.expr = parseExpression();
        item.separator = ';';

        if (m_currentToken.line == printLine) {
            if (m_currentToken.type == TokenType::Comma) {
                item.separator = ',';
                consume();
                printNode->hasTrailingSeparator = true;
            } else if (m_currentToken.type == TokenType::Semicolon) {
                item.separator = ';';
                consume();
                printNode->hasTrailingSeparator = true;
            } else {
                printNode->hasTrailingSeparator = false;
            }
        } else {
            printNode->hasTrailingSeparator = false;
        }

        printNode->items.push_back(std::move(item));
    }

    return printNode;
}

std::unique_ptr<ASTNode> Parser::parsePrintOrPrintFileStatement() {
    // Check if Print #filenum, expr...
    if (m_currentToken.type == TokenType::Hash) {
        consume(); // consume '#'
        auto printFileNode = std::make_unique<PrintFileStmtNode>();
        printFileNode->fileNumber = parseExpression();

        if (m_currentToken.type == TokenType::Comma) {
            consume(); // consume ',' after #filenum
        }

        size_t printLine = m_prevToken.line;
        while (m_currentToken.line == printLine &&
               m_currentToken.type != TokenType::Colon &&
               m_currentToken.type != TokenType::Eof &&
               !checkKeyword("End") && !checkKeyword("Else") && !checkKeyword("ElseIf") &&
               !checkKeyword("Loop") && !checkKeyword("Next") && !checkKeyword("Wend")) {

            if (m_currentToken.type == TokenType::Semicolon) {
                consume();
                printFileNode->hasTrailingSeparator = true;
                continue;
            }
            if (m_currentToken.type == TokenType::Comma) {
                consume();
                PrintItem item;
                item.expr = nullptr;
                item.separator = ',';
                printFileNode->items.push_back(std::move(item));
                printFileNode->hasTrailingSeparator = true;
                continue;
            }

            PrintItem item;
            item.expr = parseExpression();
            item.separator = ';';

            if (m_currentToken.line == printLine) {
                if (m_currentToken.type == TokenType::Comma) {
                    item.separator = ',';
                    consume();
                    printFileNode->hasTrailingSeparator = true;
                } else if (m_currentToken.type == TokenType::Semicolon) {
                    item.separator = ';';
                    consume();
                    printFileNode->hasTrailingSeparator = true;
                } else {
                    printFileNode->hasTrailingSeparator = false;
                }
            } else {
                printFileNode->hasTrailingSeparator = false;
            }

            printFileNode->items.push_back(std::move(item));
        }

        return printFileNode;
    }

    return parsePrintStatement();
}

std::unique_ptr<ASTNode> Parser::parseInputOrInputFileStatement() {
    // Check if Input #filenum, var1, var2...
    if (m_currentToken.type == TokenType::Hash) {
        consume(); // consume '#'
        auto inputFileNode = std::make_unique<InputFileStmtNode>();
        inputFileNode->fileNumber = parseExpression();

        expect(TokenType::Comma, "Expected ',' after file number in 'Input #'");
        do {
            inputFileNode->targets.push_back(parsePostfixExpr());
        } while (match(TokenType::Comma));

        return inputFileNode;
    }

    return parseInputStatement();
}

std::unique_ptr<InputStmtNode> Parser::parseInputStatement() {
    auto inputNode = std::make_unique<InputStmtNode>();
    if (m_currentToken.type == TokenType::StringLiteral) {
        inputNode->prompt = m_currentToken.text;
        consume();
        if (m_currentToken.type == TokenType::Semicolon || m_currentToken.type == TokenType::Comma) {
            consume();
        }
    }
    inputNode->target = parsePostfixExpr();
    return inputNode;
}

std::unique_ptr<OpenStmtNode> Parser::parseOpenStatement() {
    auto openNode = std::make_unique<OpenStmtNode>();
    openNode->filePath = parseExpression();

    expect(TokenType::KwFor, "Expected 'For' after file path in 'Open'");

    if (m_currentToken.type == TokenType::KwOutput || checkKeyword("Output")) {
        consume();
        openNode->mode = FileMode::Output;
    } else if (m_currentToken.type == TokenType::KwAppend || checkKeyword("Append")) {
        consume();
        openNode->mode = FileMode::Append;
    } else if (m_currentToken.type == TokenType::KwBinary || checkKeyword("Binary")) {
        consume();
        openNode->mode = FileMode::Binary;
    } else if (m_currentToken.type == TokenType::KwInput || checkKeyword("Input")) {
        consume();
        openNode->mode = FileMode::Input;
    } else {
        throw std::runtime_error("Expected 'Input', 'Output', 'Append', or 'Binary' mode in 'Open'");
    }

    expect(TokenType::KwAs, "Expected 'As' before file number in 'Open'");

    if (match(TokenType::Hash)) {
        // Optional '#' before file number
    }

    openNode->fileNumber = parseExpression();
    return openNode;
}

std::unique_ptr<CloseStmtNode> Parser::parseCloseStatement() {
    auto closeNode = std::make_unique<CloseStmtNode>();

    size_t closeLine = m_prevToken.line;
    if (m_currentToken.line == closeLine &&
        m_currentToken.type != TokenType::Colon &&
        m_currentToken.type != TokenType::Eof &&
        !checkKeyword("End") && !checkKeyword("Else")) {

        do {
            if (match(TokenType::Hash)) {
                // Optional '#' before file number
            }
            closeNode->fileNumbers.push_back(parseExpression());
        } while (match(TokenType::Comma));
    }

    return closeNode;
}

std::unique_ptr<LineInputStmtNode> Parser::parseLineInputStatement() {
    auto lineNode = std::make_unique<LineInputStmtNode>();

    if (match(TokenType::Hash)) {
        // Optional '#'
    }
    lineNode->fileNumber = parseExpression();

    expect(TokenType::Comma, "Expected ',' after file number in 'Line Input'");
    lineNode->targetVar = parsePostfixExpr();

    return lineNode;
}

std::vector<std::unique_ptr<ASTNode>> Parser::parseStatementBlock(const std::vector<std::string>& stopKeywords) {
    std::vector<std::unique_ptr<ASTNode>> statements;

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        // Preprocessor Directives inside statement blocks (#Const, #If, #ElseIf, #Else, #End If)
        if (m_currentToken.type == TokenType::Hash) {
            handleDirective();
            continue;
        }

        // Check if current token matches any stop keyword
        bool shouldStop = false;
        for (const auto& stop : stopKeywords) {
            if (checkKeyword(stop)) {
                shouldStop = true;
                break;
            }
        }
        if (shouldStop) break;

        statements.push_back(parseStatement());
    }

    return statements;
}

// --- Expression Parsing with Operator Precedence ---

std::unique_ptr<ExprASTNode> Parser::parseExpression() {
    return parseLogicalOr();
}

std::unique_ptr<ExprASTNode> Parser::parseLogicalOr() {
    auto lhs = parseLogicalXor();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::KwOr || checkKeyword("Or"))) {
        consume();
        auto rhs = parseLogicalXor();
        lhs = std::make_unique<BinaryExprASTNode>("Or", std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseLogicalXor() {
    auto lhs = parseLogicalAnd();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::KwXor || checkKeyword("Xor"))) {
        consume();
        auto rhs = parseLogicalAnd();
        lhs = std::make_unique<BinaryExprASTNode>("Xor", std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseLogicalAnd() {
    auto lhs = parseEquality();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::KwAnd || checkKeyword("And"))) {
        consume();
        auto rhs = parseEquality();
        lhs = std::make_unique<BinaryExprASTNode>("And", std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseEquality() {
    auto lhs = parseRelational();
    while (!m_currentToken.hasLeadingNewline) {
        if (m_currentToken.type == TokenType::Equal || m_currentToken.type == TokenType::NotEqual) {
            std::string op = m_currentToken.text;
            consume();
            auto rhs = parseRelational();
            lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
        } else if (m_currentToken.type == TokenType::KwIs || checkKeyword("Is")) {
            consume();
            bool isNot = false;
            if (m_currentToken.type == TokenType::KwNot || checkKeyword("Not")) {
                consume();
                isNot = true;
            }
            auto rhs = parseRelational();
            std::string op = isNot ? "<>" : "=";
            lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
        } else {
            break;
        }
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseRelational() {
    auto lhs = parseShift();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::Less || 
           m_currentToken.type == TokenType::LessEqual || 
           m_currentToken.type == TokenType::Greater || 
           m_currentToken.type == TokenType::GreaterEqual ||
           m_currentToken.type == TokenType::KwLike || checkKeyword("Like"))) {
        std::string op = m_currentToken.text;
        consume();
        auto rhs = parseShift();
        lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseShift() {
    auto lhs = parseAdditiveExpr();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::KwLShift || checkKeyword("LShift") ||
           m_currentToken.type == TokenType::KwRShift || checkKeyword("RShift"))) {
        std::string op = m_currentToken.text;
        consume();
        auto rhs = parseAdditiveExpr();
        lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseAdditiveExpr() {
    auto lhs = parseMultiplicative();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::Plus || m_currentToken.type == TokenType::Minus || m_currentToken.type == TokenType::Ampersand)) {
        std::string op = m_currentToken.text;
        consume();
        auto rhs = parseMultiplicative();
        lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseMultiplicative() {
    auto lhs = parseUnary();
    while (!m_currentToken.hasLeadingNewline && (m_currentToken.type == TokenType::Asterisk || 
           m_currentToken.type == TokenType::Slash || 
           m_currentToken.type == TokenType::KwMod || checkKeyword("Mod"))) {
        std::string op = m_currentToken.text;
        consume();
        auto rhs = parseUnary();
        lhs = std::make_unique<BinaryExprASTNode>(op, std::move(lhs), std::move(rhs));
    }
    return lhs;
}

std::unique_ptr<ExprASTNode> Parser::parseUnary() {
    if (m_currentToken.type == TokenType::KwNot || checkKeyword("Not")) {
        consume();
        auto expr = parseUnary();
        return std::make_unique<UnaryExprASTNode>("Not", std::move(expr));
    }
    if (m_currentToken.type == TokenType::Minus) {
        consume();
        auto expr = parseUnary();
        return std::make_unique<UnaryExprASTNode>("-", std::move(expr));
    }
    if (m_currentToken.type == TokenType::Plus) {
        consume();
        return parseUnary();
    }
    return parsePostfixExpr();
}

std::unique_ptr<ExprASTNode> Parser::parsePostfixExpr() {
    auto expr = parsePrimaryExpr();

    while (true) {
        // Dot member access: expr.member (do not cross newlines without continuation)
        if (!m_currentToken.hasLeadingNewline && match(TokenType::Dot)) {
            std::string memberName = m_currentToken.text;
            expect(TokenType::Identifier, "Expected member name after '.'");
            expr = std::make_unique<MemberAccessExprASTNode>(std::move(expr), memberName);
            continue;
        }

        // Parentheses: function call or index expr: expr(...) (do not cross newlines)
        if (!m_currentToken.hasLeadingNewline && match(TokenType::LParen)) {
            auto callNode = std::make_unique<CallExprASTNode>();
            if (auto var = dynamic_cast<VariableExprASTNode*>(expr.get())) {
                callNode->funcName = var->name;
            } else if (auto member = dynamic_cast<MemberAccessExprASTNode*>(expr.get())) {
                callNode->funcName = member->memberName;
                callNode->calleeExpr = std::move(member->base);
            } else {
                callNode->calleeExpr = std::move(expr);
            }

            // Check if this is an explicit generic type argument list: Func(Of T, U)(args)
            if (m_currentToken.type == TokenType::KwOf || checkKeyword("Of")) {
                consume();
                do {
                    callNode->typeArgs.push_back(parseTypeSpec());
                } while (match(TokenType::Comma));
                expect(TokenType::RParen, "Expected ')' after generic type arguments");
                expect(TokenType::LParen, "Expected '(' after generic type argument list");
            }

            if (!check(TokenType::RParen)) {
                do {
                    if (m_currentToken.type == TokenType::Identifier && m_lexer.peekToken().type == TokenType::ColonEqual) {
                        std::string argName = m_currentToken.text;
                        consume(); // consume identifier
                        consume(); // consume ':='
                        auto exprVal = parseExpression();
                        callNode->namedArgs.push_back({argName, std::move(exprVal)});
                    } else {
                        auto exprVal = parseExpression();
                        callNode->args.push_back(std::move(exprVal));
                    }
                } while (match(TokenType::Comma));
            }
            expect(TokenType::RParen, "Expected ')' after argument list");
            expr = std::move(callNode);
            continue;
        }


        break;
    }

    return expr;
}

std::unique_ptr<ExprASTNode> Parser::parsePrimaryExpr() {
    // String Literal
    if (m_currentToken.type == TokenType::StringLiteral) {
        auto node = std::make_unique<StringExprASTNode>(m_currentToken.text);
        consume();
        return node;
    }

    // Implicit With Member Access: .Member
    if (m_withDepth > 0 && match(TokenType::Dot)) {
        std::string member = m_currentToken.text;
        expect(TokenType::Identifier, "Expected member name after '.'");
        return std::make_unique<MemberAccessExprASTNode>(nullptr, member);
    }

    // Number Literal
    if (m_currentToken.type == TokenType::NumberLiteral) {
        std::string text = m_currentToken.text;
        if (text.find('.') != std::string::npos || text.find('e') != std::string::npos || text.find('E') != std::string::npos) {
            double val = 0.0;
            try {
                val = std::stod(text);
            } catch (...) {
                val = 0.0;
            }
            std::string hint = "double";
            if (!text.empty() && (text.back() == 'f' || text.back() == 'F' || text.back() == '!')) {
                hint = "single";
            }
            consume();
            return std::make_unique<NumberExprASTNode>(val, hint);
        }
        int64_t val = 0;
        try {
            if (text.size() >= 2 && text[0] == '&' && (text[1] == 'H' || text[1] == 'h')) {
                val = static_cast<int64_t>(std::stoull(text.substr(2), nullptr, 16));
            } else {
                val = std::stoll(text, nullptr, 10);
            }
        } catch (...) {
            val = 0;
        }
        consume();
        return std::make_unique<NumberExprASTNode>(val);
    }

    // Boolean Literals
    if (m_currentToken.type == TokenType::KwTrue || checkKeyword("True")) {
        consume();
        return std::make_unique<NumberExprASTNode>(static_cast<int64_t>(1), "Boolean");
    }
    if (m_currentToken.type == TokenType::KwFalse || checkKeyword("False")) {
        consume();
        return std::make_unique<NumberExprASTNode>(static_cast<int64_t>(0), "Boolean");
    }

    // Nothing literal (null pointer / zero object reference)
    if (m_currentToken.type == TokenType::KwNothing || checkKeyword("Nothing")) {
        consume();
        return std::make_unique<NumberExprASTNode>(static_cast<int64_t>(0), "Nothing");
    }

    // Built-in CPtr(Type, Expr)
    if (m_currentToken.type == TokenType::KwCPtr || checkKeyword("CPtr")) {
        consume();
        expect(TokenType::LParen, "Expected '(' after CPtr");
        TypeSpec targetType = parseTypeSpec();
        expect(TokenType::Comma, "Expected ',' after type in CPtr");
        auto castExpr = parseExpression();
        expect(TokenType::RParen, "Expected ')' after CPtr expression");
        return std::make_unique<CastExprASTNode>(CastExprASTNode::CastKind::CPtr, std::move(targetType), std::move(castExpr));
    }

    // Built-in CType(Type, Expr)
    if (m_currentToken.type == TokenType::KwCType || checkKeyword("CType")) {
        consume();
        expect(TokenType::LParen, "Expected '(' after CType");
        TypeSpec targetType = parseTypeSpec();
        expect(TokenType::Comma, "Expected ',' after type in CType");
        auto castExpr = parseExpression();
        expect(TokenType::RParen, "Expected ')' after CType expression");
        return std::make_unique<CastExprASTNode>(CastExprASTNode::CastKind::CType, std::move(targetType), std::move(castExpr));
    }

    // AddressOf funcName
    if (m_currentToken.type == TokenType::KwAddressOf || checkKeyword("AddressOf")) {
        consume();
        std::string target = m_currentToken.text;
        expect(TokenType::Identifier, "Expected procedure or function identifier after 'AddressOf'");
        return std::make_unique<AddressOfExprASTNode>(target);
    }

    // New ClassName[(args...)]
    if (m_currentToken.type == TokenType::KwNew || checkKeyword("New")) {
        consume();
        auto newNode = std::make_unique<NewExprASTNode>();
        newNode->className = m_currentToken.text;
        expect(TokenType::Identifier, "Expected class name after 'New'");
        newNode->typeSpec.name = newNode->className;
        newNode->typeSpec.pointerDepth = 1; // Objects instantiated with New are pointers to instance struct

        if (match(TokenType::LParen)) {
            if (!check(TokenType::RParen)) {
                do {
                    newNode->args.push_back(parseExpression());
                } while (match(TokenType::Comma));
            }
            expect(TokenType::RParen, "Expected ')' after constructor arguments");
        }
        return newNode;
    }

    // TypeOf expr Is [Not] TypeName
    if (m_currentToken.type == TokenType::KwTypeOf || checkKeyword("TypeOf")) {
        consume();
        auto exprNode = parsePostfixExpr();
        if (m_currentToken.type == TokenType::KwIs || checkKeyword("Is")) {
            consume();
        } else {
            expect(TokenType::KwIs, "Expected 'Is' after TypeOf expression");
        }
        bool isNot = false;
        if (m_currentToken.type == TokenType::KwNot || checkKeyword("Not")) {
            consume();
            isNot = true;
        }
        TypeSpec targetType = parseTypeSpec();
        return std::make_unique<TypeOfExprASTNode>(std::move(exprNode), std::move(targetType), isNot);
    }

    // Parenthesized Expression: (expr)
    if (match(TokenType::LParen)) {
        auto node = parseExpression();
        expect(TokenType::RParen, "Expected ')' to close parenthesized expression");
        return node;
    }

    // Lambda Expression: Function([params]) [As Type] => Expr
    if (m_currentToken.type == TokenType::KwFunction || checkKeyword("Function")) {
        consume();
        auto lambdaNode = std::make_unique<LambdaExprASTNode>();
        if (match(TokenType::LParen)) {
            if (!check(TokenType::RParen)) {
                do {
                    ParameterNode param;
                    if (m_currentToken.type == TokenType::KwByVal || checkKeyword("ByVal")) {
                        consume();
                        param.isByRef = false;
                    } else if (m_currentToken.type == TokenType::KwByRef || checkKeyword("ByRef")) {
                        consume();
                        param.isByRef = true;
                    }
                    param.name = m_currentToken.text;
                    expect(TokenType::Identifier, "Expected parameter name in lambda");
                    if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                        consume();
                    }
                    param.type = parseTypeSpec();
                    lambdaNode->parameters.push_back(std::move(param));
                } while (match(TokenType::Comma));
            }
            expect(TokenType::RParen, "Expected ')' after lambda parameter list");
        }

        if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
            consume();
            lambdaNode->returnType = parseTypeSpec();
        } else {
            lambdaNode->returnType = TypeSpec{"Int32"};
        }

        if (m_currentToken.type == TokenType::FatArrow) {
            consume();
        } else {
            expect(TokenType::FatArrow, "Expected '=>' after lambda signature");
        }

        lambdaNode->bodyExpr = parseExpression();
        return lambdaNode;
    }

    // Identifier, 'Me', or built-in File Functions (EOF, LOF)
    if (m_currentToken.type == TokenType::Identifier || 
        m_currentToken.type == TokenType::KwMe || checkKeyword("Me") ||
        m_currentToken.type == TokenType::KwEof || checkKeyword("EOF") ||
        m_currentToken.type == TokenType::KwLof || checkKeyword("LOF")) {
        std::string name = m_currentToken.text;
        consume();
        return std::make_unique<VariableExprASTNode>(name);
    }

    // Fallback for unexpected token
    std::string unexp = m_currentToken.text;
    consume();
    return std::make_unique<VariableExprASTNode>(unexp);
}

// --- Procedure & Module Parsing ---

std::unique_ptr<ProcedureNode> Parser::parseProcedure(bool isPublic, bool isInline, bool isNoReturn, bool isExport) {
    auto procNode = std::make_unique<ProcedureNode>();
    procNode->isPublic = isPublic;
    procNode->isInline = isInline;
    procNode->isNoReturn = isNoReturn;
    procNode->isExport = isExport;
    procNode->line = m_currentToken.line;
    procNode->column = m_currentToken.column;

    while (true) {
        if (m_currentToken.type == TokenType::KwPublic || checkKeyword("Public")) {
            consume();
            procNode->isPublic = true;
        } else if (m_currentToken.type == TokenType::KwPrivate || checkKeyword("Private")) {
            consume();
            procNode->isPublic = false;
        } else if (m_currentToken.type == TokenType::KwDeclare || checkKeyword("Declare")) {
            consume();
            procNode->isDeclare = true;
        } else if (m_currentToken.type == TokenType::KwUnsafe || checkKeyword("Unsafe")) {
            consume();
            procNode->isUnsafe = true;
        } else {
            break;
        }
    }

    if (m_currentToken.type == TokenType::KwSub || checkKeyword("Sub")) {
        consume();
        procNode->isFunction = false;
    } else if (m_currentToken.type == TokenType::KwFunction || checkKeyword("Function")) {
        consume();
        procNode->isFunction = true;
    } else if (m_currentToken.type == TokenType::KwProperty || checkKeyword("Property")) {
        consume();
        if (m_currentToken.type == TokenType::KwGet || checkKeyword("Get")) {
            consume();
            procNode->propertyKind = ProcedureNode::PropertyKind::Get;
            procNode->isFunction = true;
        } else if (m_currentToken.type == TokenType::KwLet || checkKeyword("Let")) {
            consume();
            procNode->propertyKind = ProcedureNode::PropertyKind::Let;
            procNode->isFunction = false;
        } else if (m_currentToken.type == TokenType::KwSet || checkKeyword("Set")) {
            consume();
            procNode->propertyKind = ProcedureNode::PropertyKind::Set;
            procNode->isFunction = false;
        } else {
            throw std::runtime_error("Expected 'Get', 'Let', or 'Set' after 'Property'");
        }
    } else {
        throw std::runtime_error("Expected 'Sub', 'Function', or 'Property'");
    }

    procNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected procedure name");

    // Generic parameter definition: Function Name(Of T, U)(...)
    if (match(TokenType::LParen)) {
        if (m_currentToken.type == TokenType::KwOf || checkKeyword("Of")) {
            consume();
            do {
                procNode->genericParams.push_back(m_currentToken.text);
                expect(TokenType::Identifier, "Expected generic type parameter name");
            } while (match(TokenType::Comma));
            expect(TokenType::RParen, "Expected ')' after generic type parameters");
            expect(TokenType::LParen, "Expected '(' after generic parameter list");
        }
        // If not 'Of', the '(' is the parameter list opening paren
    } else {
        if (procNode->isDeclare) {
            if (m_currentToken.type == TokenType::KwLib || checkKeyword("Lib")) {
                consume();
                if (m_currentToken.type == TokenType::StringLiteral) {
                    procNode->libName = m_currentToken.text;
                    consume();
                } else {
                    expect(TokenType::StringLiteral, "Expected string literal after 'Lib'");
                }
            }
            if (m_currentToken.type == TokenType::KwAlias || checkKeyword("Alias")) {
                consume();
                if (m_currentToken.type == TokenType::StringLiteral) {
                    procNode->aliasName = m_currentToken.text;
                    consume();
                } else {
                    expect(TokenType::StringLiteral, "Expected string literal after 'Alias'");
                }
            }
        }
        expect(TokenType::LParen, "Expected '(' after procedure name");
    }

    if (!check(TokenType::RParen)) {

        do {
            ParameterNode param;
            if (m_currentToken.type == TokenType::KwParamArray || checkKeyword("ParamArray")) {
                consume();
                param.isParamArray = true;
                param.isOptional = true;
            } else if (m_currentToken.type == TokenType::KwOptional || checkKeyword("Optional")) {
                consume();
                param.isOptional = true;
            }

            if (m_currentToken.type == TokenType::KwByRef || checkKeyword("ByRef")) {
                consume();
                param.isByRef = true;
            } else if (m_currentToken.type == TokenType::KwByVal || checkKeyword("ByVal")) {
                consume();
                param.isByRef = false;
            }

            param.name = m_currentToken.text;
            expect(TokenType::Identifier, "Expected parameter identifier");

            // ParamArray can have empty parens: args() As Type
            if (match(TokenType::LParen)) {
                expect(TokenType::RParen, "Expected ')' after ParamArray parameter name");
            }

            if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                consume();
            } else {
                expect(TokenType::KwAs, "Expected 'As' after parameter name");
            }

            param.type = parseTypeSpec();

            if (match(TokenType::Equal)) {
                param.defaultValue = parseExpression();
            }

            procNode->parameters.push_back(std::move(param));
        } while (match(TokenType::Comma));
    }

    expect(TokenType::RParen, "Expected ')' after parameter list");

    if (procNode->isFunction) {
        if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
            consume();
        } else {
            expect(TokenType::KwAs, "Expected 'As' for Function return type");
        }
        procNode->returnType = parseTypeSpec();
    }

    if (procNode->isDeclare) {
        return procNode;
    }

    // Parse Procedure Body until 'End Sub' or 'End Function'
    procNode->body = parseStatementBlock({"End"});

    if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
        consume();
        if (procNode->propertyKind != ProcedureNode::PropertyKind::None) {
            if (m_currentToken.type == TokenType::KwProperty || checkKeyword("Property")) {
                consume();
            }
        } else if (procNode->isFunction) {
            if (m_currentToken.type == TokenType::KwFunction || checkKeyword("Function")) {
                consume();
            }
        } else {
            if (m_currentToken.type == TokenType::KwSub || checkKeyword("Sub")) {
                consume();
            }
        }
    }

    return procNode;
}

std::unique_ptr<StructureNode> Parser::parseStructure(bool isPacked, int alignment) {
    auto structNode = std::make_unique<StructureNode>();
    structNode->isPacked = isPacked;
    structNode->alignment = alignment;

    structNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected structure name");

    // Generic parameter definition: Structure Box(Of T)
    if (match(TokenType::LParen)) {
        if (m_currentToken.type == TokenType::KwOf || checkKeyword("Of")) {
            consume();
        }
        do {
            structNode->genericParams.push_back(m_currentToken.text);
            expect(TokenType::Identifier, "Expected generic parameter identifier");
        } while (match(TokenType::Comma));
        expect(TokenType::RParen, "Expected ')' after generic parameters");
    }


    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwStructure || checkKeyword("Structure") ||
                m_currentToken.type == TokenType::KwType || checkKeyword("Type")) {
                consume();
            }
            break;
        }

        bool isFieldPublic = true;
        if (m_currentToken.type == TokenType::KwPublic || checkKeyword("Public")) {
            consume();
            isFieldPublic = true;
        } else if (m_currentToken.type == TokenType::KwPrivate || checkKeyword("Private")) {
            consume();
            isFieldPublic = false;
        } else if (m_currentToken.type == TokenType::KwDim || checkKeyword("Dim")) {
            consume();
            isFieldPublic = true;
        }

        StructureField field;
        field.isPublic = isFieldPublic;
        field.name = m_currentToken.text;
        expect(TokenType::Identifier, "Expected structure field name");

        bool isArray = false;
        size_t arraySize = 0;
        std::vector<size_t> dimensions;

        if (match(TokenType::LParen)) {
            isArray = true;
            do {
                size_t dim = 0;
                if (m_currentToken.type == TokenType::NumberLiteral) {
                    try {
                        std::string numText = m_currentToken.text;
                        if (numText.size() >= 2 && (numText[0] == '&' && (numText[1] == 'H' || numText[1] == 'h'))) {
                            dim = std::stoull(numText.substr(2), nullptr, 16);
                        } else {
                            dim = std::stoull(numText, nullptr, 10);
                        }
                    } catch (...) {
                        dim = 0;
                    }
                    consume();
                }
                dimensions.push_back(dim);
            } while (match(TokenType::Comma));

            if (!dimensions.empty()) {
                arraySize = dimensions[0];
                for (size_t i = 1; i < dimensions.size(); ++i) {
                    arraySize *= dimensions[i];
                }
            }
            expect(TokenType::RParen, "Expected ')' after array dimension");
        }

        if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
            consume();
        } else {
            expect(TokenType::KwAs, "Expected 'As' after field name");
        }

        field.type = parseTypeSpec();
        field.type.isArray = isArray;
        field.type.arraySize = arraySize;
        field.type.dimensions = dimensions;
        structNode->fields.push_back(field);
    }

    return structNode;
}

std::unique_ptr<StructureNode> Parser::parseUnion(bool isPacked, int alignment) {
    auto unionNode = std::make_unique<StructureNode>();
    unionNode->isUnion = true;
    unionNode->isPacked = isPacked;
    unionNode->alignment = alignment;

    unionNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected union name");

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwUnion || checkKeyword("Union")) {
                consume();
            }
            break;
        }

        bool isFieldPublic = true;
        if (m_currentToken.type == TokenType::KwPublic || checkKeyword("Public")) {
            consume();
            isFieldPublic = true;
        } else if (m_currentToken.type == TokenType::KwPrivate || checkKeyword("Private")) {
            consume();
            isFieldPublic = false;
        } else if (m_currentToken.type == TokenType::KwDim || checkKeyword("Dim")) {
            consume();
            isFieldPublic = true;
        }

        StructureField field;
        field.isPublic = isFieldPublic;
        field.name = m_currentToken.text;
        expect(TokenType::Identifier, "Expected union field name");

        bool isArray = false;
        size_t arraySize = 0;
        std::vector<size_t> dimensions;

        if (match(TokenType::LParen)) {
            isArray = true;
            do {
                size_t dim = 0;
                if (m_currentToken.type == TokenType::NumberLiteral) {
                    try {
                        std::string numText = m_currentToken.text;
                        if (numText.size() >= 2 && (numText[0] == '&' && (numText[1] == 'H' || numText[1] == 'h'))) {
                            dim = std::stoull(numText.substr(2), nullptr, 16);
                        } else {
                            dim = std::stoull(numText, nullptr, 10);
                        }
                    } catch (...) {
                        dim = 0;
                    }
                    consume();
                }
                dimensions.push_back(dim);
            } while (match(TokenType::Comma));

            if (!dimensions.empty()) {
                arraySize = dimensions[0];
                for (size_t i = 1; i < dimensions.size(); ++i) {
                    arraySize *= dimensions[i];
                }
            }
            expect(TokenType::RParen, "Expected ')' after array dimension");
        }

        if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
            consume();
        } else {
            expect(TokenType::KwAs, "Expected 'As' after field name");
        }

        field.type = parseTypeSpec();
        field.type.isArray = isArray;
        field.type.arraySize = arraySize;
        field.type.dimensions = dimensions;
        unionNode->fields.push_back(field);
    }

    return unionNode;
}

std::unique_ptr<EnumNode> Parser::parseEnum(bool isPublic) {
    auto enumNode = std::make_unique<EnumNode>();
    enumNode->isPublic = isPublic;

    enumNode->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected enum name");

    int64_t nextValue = 0;
    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwEnum || checkKeyword("Enum")) {
                consume();
            }
            break;
        }

        EnumMember member;
        member.name = m_currentToken.text;
        expect(TokenType::Identifier, "Expected enum member name");

        if (match(TokenType::Equal)) {
            member.hasExplicitValue = true;
            bool isNeg = match(TokenType::Minus);
            if (m_currentToken.type == TokenType::NumberLiteral) {
                std::string numText = m_currentToken.text;
                int64_t val = 0;
                try {
                    if (numText.size() >= 2 && numText[0] == '&' && (numText[1] == 'H' || numText[1] == 'h')) {
                        val = static_cast<int64_t>(std::stoull(numText.substr(2), nullptr, 16));
                    } else {
                        val = std::stoll(numText, nullptr, 10);
                    }
                } catch (...) {
                    val = 0;
                }
                member.value = isNeg ? -val : val;
                nextValue = member.value + 1;
                consume();
            } else {
                throw std::runtime_error("Expected integer constant for enum member value");
            }
        } else {
            member.value = nextValue++;
        }

        enumNode->members.push_back(member);
    }

    return enumNode;
}

std::unique_ptr<InterfaceNode> Parser::parseInterface(bool isPublic) {
    auto iface = std::make_unique<InterfaceNode>();
    iface->isPublic = isPublic;
    iface->line = m_currentToken.line;
    iface->column = m_currentToken.column;
    iface->name = m_currentToken.text;
    expect(TokenType::Identifier, "Expected interface name");

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if (m_currentToken.type == TokenType::KwInterface || checkKeyword("Interface")) {
                consume();
                break;
            }
        }

        InterfaceMethod method;
        if (m_currentToken.type == TokenType::KwSub || checkKeyword("Sub")) {
            consume();
            method.isFunction = false;
        } else if (m_currentToken.type == TokenType::KwFunction || checkKeyword("Function")) {
            consume();
            method.isFunction = true;
        } else {
            consume();
            continue;
        }

        method.name = m_currentToken.text;
        expect(TokenType::Identifier, "Expected procedure name in interface");

        if (match(TokenType::LParen)) {
            if (!check(TokenType::RParen)) {
                do {
                    ParameterNode param;
                    if (m_currentToken.type == TokenType::KwByVal || checkKeyword("ByVal")) {
                        consume();
                        param.isByRef = false;
                    } else if (m_currentToken.type == TokenType::KwByRef || checkKeyword("ByRef")) {
                        consume();
                        param.isByRef = true;
                    }
                    param.name = m_currentToken.text;
                    expect(TokenType::Identifier, "Expected parameter name in interface method");
                    if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                        consume();
                    }
                    param.type = parseTypeSpec();
                    method.parameters.push_back(std::move(param));
                } while (match(TokenType::Comma));
            }
            expect(TokenType::RParen, "Expected ')' after interface method parameters");
        }

        if (method.isFunction) {
            if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                consume();
            }
            method.returnType = parseTypeSpec();
        } else {
            method.returnType = TypeSpec{"void"};
        }

        iface->methods.push_back(std::move(method));
    }

    return iface;
}

std::unique_ptr<ModuleNode> Parser::parseModule() {
    auto moduleNode = std::make_unique<ModuleNode>();

    if (m_currentToken.type == TokenType::KwModule || checkKeyword("Module")) {
        consume();
        moduleNode->isClass = false;
    } else if (m_currentToken.type == TokenType::KwClass || checkKeyword("Class")) {
        consume();
        moduleNode->isClass = true;
    } else if (m_currentToken.type == TokenType::KwInterface || checkKeyword("Interface")) {
        consume();
        moduleNode->isInterface = true;
    } else if (m_currentToken.type == TokenType::KwNamespace || checkKeyword("Namespace")) {
        consume();
        moduleNode->isClass = false;
    } else {
        throw std::runtime_error("Source file must begin with 'Module', 'Class', 'Interface', or 'Namespace'");
    }

    std::string modName = m_currentToken.text;
    expect(TokenType::Identifier, "Expected module or class name");
    while (match(TokenType::Dot)) {
        modName += "." + m_currentToken.text;
        expect(TokenType::Identifier, "Expected identifier after '.' in module/class name");
    }
    moduleNode->name = modName;

    while (m_currentToken.type != TokenType::Eof) {
        while (match(TokenType::Colon)) {}

        // Preprocessor Directives at module level (#Const, #If, #ElseIf, #Else, #End If)
        if (m_currentToken.type == TokenType::Hash) {
            handleDirective();
            continue;
        }

        // Check for 'End Module', 'End Class', 'End Interface', or 'End Namespace'
        if (m_currentToken.type == TokenType::KwEnd || checkKeyword("End")) {
            consume();
            if ((moduleNode->isClass && (m_currentToken.type == TokenType::KwClass || checkKeyword("Class"))) ||
                (moduleNode->isInterface && (m_currentToken.type == TokenType::KwInterface || checkKeyword("Interface"))) ||
                (!moduleNode->isClass && (m_currentToken.type == TokenType::KwModule || checkKeyword("Module") || 
                                          m_currentToken.type == TokenType::KwNamespace || checkKeyword("Namespace")))) {
                consume();
                break;
            }
        }

        // Implements InterfaceName (inside Class)
        if (m_currentToken.type == TokenType::KwImplements || checkKeyword("Implements")) {
            consume();
            std::string ifaceName = m_currentToken.text;
            expect(TokenType::Identifier, "Expected interface identifier after 'Implements'");
            while (match(TokenType::Dot)) {
                ifaceName += "." + m_currentToken.text;
                expect(TokenType::Identifier, "Expected identifier after '.' in interface name");
            }
            moduleNode->implementsInterfaces.push_back(ifaceName);
            continue;
        }

        // Interface Definition inside Module/Namespace
        if (m_currentToken.type == TokenType::KwInterface || checkKeyword("Interface")) {
            consume();
            moduleNode->members.push_back(parseInterface(true));
            continue;
        }

        // Check for attribute annotations: <Packed>, <Align(N)>, <Inline>, <NoReturn>, <Export>
        bool isPacked = false;
        int alignVal = 0;
        bool isInline = false;
        bool isNoReturn = false;
        bool isExport = false;

        while (match(TokenType::Less)) {
            do {
                if (checkKeyword("Packed")) {
                    consume();
                    isPacked = true;
                } else if (checkKeyword("Inline")) {
                    consume();
                    isInline = true;
                } else if (checkKeyword("NoReturn")) {
                    consume();
                    isNoReturn = true;
                } else if (checkKeyword("Export")) {
                    consume();
                    isExport = true;
                } else if (checkKeyword("Align")) {
                    consume();
                    if (match(TokenType::LParen)) {
                        if (m_currentToken.type == TokenType::NumberLiteral) {
                            try {
                                alignVal = std::stoi(m_currentToken.text);
                            } catch (...) {}
                            consume();
                        }
                        expect(TokenType::RParen, "Expected ')' after alignment value");
                    }
                } else {
                    consume(); // Skip unknown attribute gracefully
                }
            } while (match(TokenType::Comma));
            expect(TokenType::Greater, "Expected '>' to close attribute");
        }

        // Module / Class Level Declarations
        if (m_currentToken.type == TokenType::KwImport || checkKeyword("Import")) {
            consume();
            moduleNode->imports.push_back(parseImportStatement());
            continue;
        }

        if (checkKeyword("TypeAlias")) {
            consume();
            parseTypeAlias();
            continue;
        }

        if (m_currentToken.type == TokenType::KwStructure || checkKeyword("Structure") ||
            m_currentToken.type == TokenType::KwType || checkKeyword("Type")) {
            consume();
            moduleNode->members.push_back(parseStructure(isPacked, alignVal));
            continue;
        }

        if (m_currentToken.type == TokenType::KwUnion || checkKeyword("Union")) {
            consume();
            moduleNode->members.push_back(parseUnion(isPacked, alignVal));
            continue;
        }

        if (m_currentToken.type == TokenType::KwEnum || checkKeyword("Enum")) {
            consume();
            moduleNode->members.push_back(parseEnum(true));
            continue;
        }

        if (m_currentToken.type == TokenType::KwConst || checkKeyword("Const")) {
            consume();
            moduleNode->members.push_back(parseConstStatement(false));
            continue;
        }

        if (m_currentToken.type == TokenType::KwDim || checkKeyword("Dim")) {
            consume();
            moduleNode->members.push_back(parseDimStatement());
            continue;
        }

        // Public / Private declarations
        if (m_currentToken.type == TokenType::KwPublic || checkKeyword("Public") ||
            m_currentToken.type == TokenType::KwPrivate || checkKeyword("Private")) {
            
            bool isPub = (m_currentToken.type == TokenType::KwPublic || checkKeyword("Public"));
            consume();

            if (m_currentToken.type == TokenType::KwStructure || checkKeyword("Structure") ||
                m_currentToken.type == TokenType::KwType || checkKeyword("Type")) {
                consume();
                moduleNode->members.push_back(parseStructure(isPacked, alignVal));
                continue;
            }
            if (m_currentToken.type == TokenType::KwUnion || checkKeyword("Union")) {
                consume();
                moduleNode->members.push_back(parseUnion(isPacked, alignVal));
                continue;
            }
            if (m_currentToken.type == TokenType::KwEnum || checkKeyword("Enum")) {
                consume();
                moduleNode->members.push_back(parseEnum(isPub));
                continue;
            }
            if (m_currentToken.type == TokenType::KwConst || checkKeyword("Const")) {
                consume();
                moduleNode->members.push_back(parseConstStatement(isPub));
                continue;
            }
            if (m_currentToken.type == TokenType::KwDim || checkKeyword("Dim")) {
                consume();
                moduleNode->members.push_back(parseDimStatement());
                continue;
            }
            if (m_currentToken.type == TokenType::KwDelegate || checkKeyword("Delegate")) {
                // Skip Delegate prototype declaration for now
                while (m_currentToken.type != TokenType::Eof && m_currentToken.line == m_prevToken.line) {
                    consume();
                }
                continue;
            }

            // Variable declaration: Public/Private varName [([dims])] As Type
            if (m_currentToken.type == TokenType::Identifier &&
                !checkKeyword("Sub") && !checkKeyword("Function") &&
                !checkKeyword("Property") && !checkKeyword("Declare") &&
                !checkKeyword("Unsafe")) {
                
                auto dimNode = std::make_unique<DimStmtNode>();
                dimNode->varName = m_currentToken.text;
                consume();

                bool isArray = false;
                size_t arraySize = 0;
                std::vector<size_t> dimensions;

                if (match(TokenType::LParen)) {
                    isArray = true;
                    do {
                        size_t dim = 0;
                        if (m_currentToken.type == TokenType::NumberLiteral) {
                            try {
                                std::string numText = m_currentToken.text;
                                if (numText.size() >= 2 && (numText[0] == '&' && (numText[1] == 'H' || numText[1] == 'h'))) {
                                    dim = std::stoull(numText.substr(2), nullptr, 16);
                                } else {
                                    dim = std::stoull(numText, nullptr, 10);
                                }
                            } catch (...) {
                                dim = 0;
                            }
                            consume();
                        }
                        dimensions.push_back(dim);
                    } while (match(TokenType::Comma));

                    if (!dimensions.empty()) {
                        arraySize = dimensions[0];
                        for (size_t i = 1; i < dimensions.size(); ++i) {
                            arraySize *= dimensions[i];
                        }
                    }
                    expect(TokenType::RParen, "Expected ')' after array dimension");
                }

                if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                    consume();
                } else {
                    expect(TokenType::KwAs, "Expected 'As' in variable declaration");
                }

                dimNode->type = parseTypeSpec();
                dimNode->type.isArray = isArray;
                dimNode->type.arraySize = arraySize;
                dimNode->type.dimensions = dimensions;

                if (match(TokenType::Equal)) {
                    dimNode->initValue = parseExpression();
                }

                moduleNode->members.push_back(std::move(dimNode));
                continue;
            }

            // Procedure (Sub / Function / Property / Declare / Unsafe)
            auto proc = parseProcedure(isPub, isInline, isNoReturn, isExport);
            moduleNode->members.push_back(std::move(proc));
            continue;
        }

        if (m_currentToken.type == TokenType::KwSub || checkKeyword("Sub") ||
            m_currentToken.type == TokenType::KwFunction || checkKeyword("Function") ||
            m_currentToken.type == TokenType::KwProperty || checkKeyword("Property") ||
            m_currentToken.type == TokenType::KwUnsafe || checkKeyword("Unsafe") ||
            m_currentToken.type == TokenType::KwDeclare || checkKeyword("Declare")) {
            moduleNode->members.push_back(parseProcedure(true, isInline, isNoReturn, isExport));
            continue;
        }

        // In Class bodies: member fields can be declared as `Private buffer As ...` or `buffer As ...`
        if (moduleNode->isClass && m_currentToken.type == TokenType::Identifier) {
            std::string fieldName = m_currentToken.text;
            consume();
            if (m_currentToken.type == TokenType::KwAs || checkKeyword("As")) {
                consume();
                auto dimNode = std::make_unique<DimStmtNode>();
                dimNode->varName = fieldName;
                dimNode->type = parseTypeSpec();
                moduleNode->members.push_back(std::move(dimNode));
                continue;
            }
        }

        consume();
    }

    return moduleNode;
}

} // namespace llbc