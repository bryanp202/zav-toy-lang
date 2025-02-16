const std = @import("std");

/// Scanner import
const Scan = @import("scanner.zig");
const Scanner = Scan.Scanner;
const Token = Scan.Token;
const TokenKind = Scan.TokenKind;
/// Constant, values, and symbols import
const Symbols = @import("../symbols.zig");
const ValueKind = Symbols.ValueKind;
const Value = Symbols.Value;
const KindId = Symbols.KindId;
const ScopeKind = Symbols.ScopeKind;
/// Expression nodes import
const Expr = @import("../expr.zig");
const ExprNode = Expr.ExprNode;
const ExprUnion = Expr.ExprUnion;
/// Statement Import
const Stmt = @import("../stmt.zig");
const StmtNode = Stmt.StmtNode;
/// Modules/Program File import
const Module = @import("../module.zig");
/// Error import
const Error = @import("../error.zig");
const SyntaxError = Error.SyntaxError;

// Parser fields
const Parser = @This();
allocator: std.mem.Allocator,
scanner: *Scanner,
current: Token,
previous: Token,
had_error: bool,
panic: bool,

/// Parser initializer
pub fn init(allocator: std.mem.Allocator, scanner: *Scanner) Parser {
    // Make a new parser
    const new_parser = Parser{
        .allocator = allocator,
        .scanner = scanner,
        .current = undefined,
        .previous = undefined,
        .had_error = false,
        .panic = false,
    };
    return new_parser;
}

/// Parse until scanner returns an EOF Token
/// Report any errors encountered
pub fn parse(self: *Parser, module: *Module) void {
    // Advance
    _ = self.advance();
    // Parse
    while (!self.isAtEnd()) {
        // Parse stmt
        const stmt_node = self.global() catch {
            // Attempt to realign to next statement start
            self.globalSynchronize();
            continue;
        };
        // Try to append to module
        module.addStmt(stmt_node) catch unreachable;
    }
}

/// Return true if there was an error while parsing
pub fn hadError(self: *Parser) bool {
    return self.had_error;
}

// ********************** //
// Private helper methods //
// ********************** //
/// Returns true if rhs has a higher precedence / should be swapped
fn checkReversed(lhs: isize, rhs: isize) bool {
    if (lhs < 0) return false;
    if (rhs < 0) return true;
    return rhs > lhs;
}

/// Returns new precedence level
fn newPrecedence(precedence: isize) isize {
    return if (precedence < 0) precedence else precedence + 1;
}

/// Return true if current token is EOF
inline fn isAtEnd(self: Parser) bool {
    return self.current.kind == TokenKind.EOF;
}

/// Check if the next token matches a certain token kind and returns true if it matches
/// Does not advance
inline fn check(self: Parser, kind: TokenKind) bool {
    return self.current.kind == kind;
}

/// If not at end, move current token to previous
/// and scan a new token
fn advance(self: *Parser) Token {
    // Check if at end
    if (!self.isAtEnd()) {
        // Shift current to previous
        self.previous = self.current;
        // Scan next token
        self.current = self.scanner.nextToken();

        // Consume all error tokens
        while (true) {
            // Break if current is not an error
            if (!self.check(TokenKind.ERROR) or self.check(TokenKind.EOF)) break;
            // Report error
            self.errorAtCurrent(self.current.lexeme) catch {};
            // Scan in new token
            self.current = self.scanner.nextToken();
        }
    }
    // Return previous
    return self.previous;
}

/// Take in TokenKinds and check if current token matches any.
/// If a match is found, advance and return true, else false
fn match(self: *Parser, kinds: anytype) bool {
    // Check if current token matches any
    inline for (kinds) |kind| {
        if (self.check(kind)) {
            // Advance
            _ = self.advance();
            // Report match
            return true;
        }
    }
    return false;
}

/// Take in TokenKinds and check if current token matches any.
/// If a match is found, return true, else false
fn matchNoAdvance(self: *Parser, kinds: anytype) bool {
    // Check if current token matches any
    inline for (kinds) |kind| {
        if (self.check(kind)) {
            // Report match
            return true;
        }
    }
    return false;
}

/// Check if the next token matches a certain TokenKind and advance
/// If next token does not match, raise an error
fn consume(self: *Parser, kind: TokenKind, msg: []const u8) SyntaxError!void {
    // Check if match
    if (self.check(kind)) {
        // Consume
        _ = self.advance();
        return;
    }
    // Did not match, raise error
    return self.errorAtCurrent(msg);
}

/// Parse a kind into a KindId
fn parseKind(self: *Parser) SyntaxError!KindId {
    // Advance to next token
    const token = self.advance();
    return switch (token.kind) {
        .BOOL_TYPE => KindId.BOOL,
        .U8_TYPE => KindId.newUInt(8),
        .U16_TYPE => KindId.newUInt(16),
        .U32_TYPE => KindId.newUInt(32),
        .U64_TYPE => KindId.newUInt(64),
        .I8_TYPE => KindId.newInt(8),
        .I16_TYPE => KindId.newInt(16),
        .I32_TYPE => KindId.newInt(32),
        .I64_TYPE => KindId.newInt(64),
        .F32_TYPE => KindId.FLOAT32,
        .F64_TYPE => KindId.FLOAT64,
        //.ARRAY_TYPE => try self.parseArrayKind(),
        //.STAR => try self.parsePtrKind(),
        else => self.errorAt("Expected type"),
    };
}

// ******************* //
//   Error handling
// ******************* //

/// Display an error message to the user, set had error and enable panic mode
fn reportError(self: *Parser, token: Token, msg: []const u8) SyntaxError {
    const stderr = std.io.getStdErr().writer();

    // Error type
    var errorType = SyntaxError.InvalidExpression;
    // Only display errors when not in panic mode
    if (!self.panic) {
        // Display message
        stderr.print("[Line {d}:{d}]", .{ token.line, token.column }) catch unreachable;

        // Change message based off of token type
        if (token.kind == TokenKind.EOF) {
            _ = stderr.write(" at end") catch unreachable;
        } else if (token.kind == TokenKind.ERROR) {
            errorType = SyntaxError.UnexpectedSymbol;
        } else {
            stderr.print(" at \'{s}\'", .{token.lexeme}) catch unreachable;
        }
        // Display msg
        stderr.print(": {s}\n", .{msg}) catch unreachable;

        // Update had error and panic mode
        self.had_error = true;
        self.panic = true;
    }
    // Raise error
    return errorType;
}

/// Raise an error at the current token. Set had error to true, initialize panic mode,
/// message the user, and return a UnexpectedSymbol error
fn errorAtCurrent(self: *Parser, msg: []const u8) SyntaxError {
    return self.reportError(self.current, msg);
}

/// Raise an error at the previous token. Set had error to true, initialize panic mode,
/// message the user, and return a UnexpectedSymbol error
fn errorAt(self: *Parser, msg: []const u8) SyntaxError {
    return self.reportError(self.previous, msg);
}

/// Synchronize to start of next global statement
fn globalSynchronize(self: *Parser) void {
    // Turn of panic mode
    self.panic = false;

    // Advance until end of file or potential start of new statement
    while (self.current.kind != TokenKind.EOF) {
        if (self.matchNoAdvance(.{ TokenKind.CONST, TokenKind.VAR, TokenKind.FN })) return;
        _ = self.advance();
    }
}

/// Synchronize to start of next statement
fn synchronize(self: *Parser) void {
    // Turn of panic mode
    self.panic = false;

    // Advance until end of file or potential start of new statement
    while (self.current.kind != TokenKind.EOF) {
        // Check for semicolon
        if (self.previous.kind == TokenKind.SEMICOLON) return;
        // Check if next token is potential start of statement
        if (self.matchNoAdvance(.{
            TokenKind.LEFT_BRACE,
            TokenKind.IF,
            TokenKind.WHILE,
            TokenKind.FOR,
            TokenKind.CONST,
            TokenKind.VAR,
            TokenKind.SWITCH,
            TokenKind.CONTINUE,
            TokenKind.BREAK,
            TokenKind.RETURN,
        })) return;
        // Advance
        _ = self.advance();
    }
}

//**************************//
//      Struct for Node
//         and Height
//**************************//
const ExprResult = struct {
    expr: ExprNode,
    precedence: isize,

    pub fn init(expr: ExprNode, precedence: isize) ExprResult {
        return .{
            .expr = expr,
            .precedence = precedence,
        };
    }
};

//**************************//
//      Parse Stmts
//**************************//
/// Parse a Global level stmt
/// Global -> GlobalStmt | FunctionStmt
fn global(self: *Parser) SyntaxError!StmtNode {
    if (self.match(.{ TokenKind.CONST, TokenKind.VAR })) {
        return self.globalStmt();
    } else if (self.match(.{TokenKind.FN})) {
        return self.functionStmt();
    }
    _ = self.advance();
    return self.errorAt("Expected global variable or function declaration");
}

/// Parse a global declaration stmt
/// GlobalStmt -> ("const" | "var") (':' type)? '=' expression ';'
fn globalStmt(self: *Parser) SyntaxError!StmtNode {
    // Get mutability of this declaration
    const mutable = (self.previous.kind == .VAR);
    // Consume identifier
    try self.consume(TokenKind.IDENTIFIER, "Expected identifier name after declare statement");
    const id = self.previous;

    // Check if type declaration was included
    var kind: ?KindId = null;
    if (self.match(.{TokenKind.COLON})) {
        kind = try self.parseKind();
    }

    // Consume "="
    try self.consume(TokenKind.EQUAL, "Expected '=' after identifier in declaration");
    // Get operator
    const op = self.previous;

    // Parse expression
    const assign_expr_result = try self.expression();
    const assign_expr = assign_expr_result.expr;
    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after declaration statement");

    // Allocate new DeclareStmt
    const new_stmt = self.allocator.create(Stmt.GlobalStmt) catch unreachable;
    new_stmt.* = Stmt.GlobalStmt.init(mutable, id, kind, op, assign_expr);

    return StmtNode{ .GLOBAL = new_stmt };
}

/// Parse a function statement
/// FunctionStmt -> "fn" identifier '(' arglist? ')' type BlockStmt
/// arglist -> arg (',' arg)*
/// arg -> identifier ':' type
fn functionStmt(self: *Parser) SyntaxError!StmtNode {
    // Get op
    const op = self.previous;
    // Get name
    try self.consume(TokenKind.IDENTIFIER, "Expected function identifier");
    const name = self.previous;

    // Consume '('
    try self.consume(TokenKind.LEFT_PAREN, "Expected '(' after function identifier");
    // Parse args
    var arg_name_list = std.ArrayList(Token).init(self.allocator);
    var arg_kind_list = std.ArrayList(KindId).init(self.allocator);

    // Check if any args
    if (!self.match(.{TokenKind.RIGHT_PAREN})) {
        // Do first arg
        // Get name
        try self.consume(TokenKind.IDENTIFIER, "Expected argument identifier");
        const first_arg_name = self.previous;
        // Consume ':'
        try self.consume(TokenKind.COLON, "Expected ':' after argument identifier");
        // Get type
        const first_arg_kind = try self.parseKind();
        // Add to arg_list
        arg_name_list.append(first_arg_name) catch unreachable;
        arg_kind_list.append(first_arg_kind) catch unreachable;

        // Do sequential args
        while (!self.match(.{TokenKind.RIGHT_PAREN}) and !self.isAtEnd()) {
            // Consume ','
            try self.consume(TokenKind.COMMA, "Expected ',' after argument");

            // Get name
            try self.consume(TokenKind.IDENTIFIER, "Expected argument identifier");
            const arg_name = self.previous;
            // Consume ':'
            try self.consume(TokenKind.COLON, "Expected ':' after argument identifier");
            // Get type
            const arg_kind = try self.parseKind();

            // Add to arg_list
            arg_name_list.append(arg_name) catch unreachable;
            arg_kind_list.append(arg_kind) catch unreachable;
        }
        // Check if at end
        if (self.isAtEnd()) {
            return self.errorAt("Expected ')' after function argument list");
        }
    }

    // Parse return kind
    const return_kind = try self.parseKind();
    // Consume '{'
    try self.consume(TokenKind.LEFT_BRACE, "Expected '{' after function return type");
    // Parse body
    const body = try self.blockStmt();

    // Allocate new FunctionStmt
    const new_stmt = self.allocator.create(Stmt.FunctionStmt) catch unreachable;
    new_stmt.* = Stmt.FunctionStmt.init(
        op,
        name,
        arg_name_list.items,
        arg_kind_list.items,
        return_kind,
        body,
    );
    return StmtNode{ .FUNCTION = new_stmt };
}

/// Parse a declaration
/// Declaration -> DeclareStmt | statement
fn declaration(self: *Parser) SyntaxError!StmtNode {
    if (self.match(.{ TokenKind.CONST, TokenKind.VAR })) { // DeclareStmt
        return self.declareStmt();
    } else { // Stmt fall through
        return self.statement();
    }
}

/// Parse a declareStmt
/// DeclareStmt -> ("const"|"var") identifier (":" type)? "=" expression ";"
fn declareStmt(self: *Parser) SyntaxError!StmtNode {
    // Get mutability of this declaration
    const mutable = (self.previous.kind == .VAR);
    // Consume identifier
    try self.consume(TokenKind.IDENTIFIER, "Expected identifier name after declare statement");
    const id = self.previous;

    // Check if type declaration was included
    var kind: ?KindId = null;
    if (self.match(.{TokenKind.COLON})) {
        kind = try self.parseKind();
    }

    // Consume "="
    try self.consume(TokenKind.EQUAL, "Expected '=' after identifier in declaration");
    // Get operator
    const op = self.previous;

    // Parse expression
    const assign_expr_result = try self.expression();
    const assign_expr = assign_expr_result.expr;
    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after declaration statement");

    // Allocate new DeclareStmt
    const new_stmt = self.allocator.create(Stmt.DeclareStmt) catch unreachable;
    new_stmt.* = Stmt.DeclareStmt.init(mutable, id, kind, op, assign_expr);
    return StmtNode{ .DECLARE = new_stmt };
}

/// Parse a Stmt
/// statement -> AssignStmt | ExprStmt
fn statement(self: *Parser) SyntaxError!StmtNode {
    if (self.match(.{TokenKind.MUT})) { // MutStmt
        return self.mutStmt();
    } else if (self.match(.{TokenKind.LEFT_BRACE})) {
        return self.blockStmt();
    } else if (self.match(.{TokenKind.WHILE})) { // WhileStmt
        return self.whileStmt();
    } else if (self.match(.{TokenKind.IF})) {
        return self.ifStmt();
    } else if (self.match(.{TokenKind.BREAK})) {
        return self.breakStmt();
    } else if (self.match(.{TokenKind.CONTINUE})) {
        return self.continueStmt();
    } else { // ExprStmt fall through
        return self.exprStmt();
    }
}

/// Parse a WhileStmt
/// whileStmt -> "while" '(' expression ')' statement ("continue" ':' statement)?
fn whileStmt(self: *Parser) SyntaxError!StmtNode {
    // Store while keyword
    const op = self.previous;

    // Consume '('
    try self.consume(TokenKind.LEFT_PAREN, "Expected '(' before while conditional");
    // Get conditional expr
    const conditional_result = try self.expression();
    const conditional = conditional_result.expr;
    // Consume ')'
    try self.consume(TokenKind.RIGHT_PAREN, "Expected ')' after while conditional");

    // Parse body
    const body = try self.statement();

    // Check for loop stmt
    var loop_stmt: ?StmtNode = null;
    if (self.match(.{TokenKind.LOOP})) {
        // Consume ':'
        try self.consume(TokenKind.COLON, "Expected ':' after loop keyword");
        // Try to parse the statement
        loop_stmt = try self.statement();
    }

    // Make new stmt node
    const new_stmt = self.allocator.create(Stmt.WhileStmt) catch unreachable;
    new_stmt.* = Stmt.WhileStmt.init(op, conditional, body, loop_stmt);
    // Return new stmt node
    return StmtNode{ .WHILE = new_stmt };
}

/// Parses an if stmt
/// IfStmt -> "if" '(' expression ')' statement ("else" statement)?
fn ifStmt(self: *Parser) SyntaxError!StmtNode {
    // Get the if token
    const op = self.previous;

    // Consume '('
    try self.consume(TokenKind.LEFT_PAREN, "Expected '(' before if statement conditional");
    // Parse conditional
    const conditional_result = try self.expression();
    const conditional = conditional_result.expr;
    // Consume ')'
    try self.consume(TokenKind.RIGHT_PAREN, "Expected ')' after if statement conditional");

    // Parse then branch
    const then_branch = try self.statement();

    // Check for else
    var else_branch: ?StmtNode = null;
    if (self.match(.{TokenKind.ELSE})) {
        else_branch = try self.statement();
    }

    // Make new stmt node
    const new_stmt = self.allocator.create(Stmt.IfStmt) catch unreachable;
    new_stmt.* = Stmt.IfStmt.init(op, conditional, then_branch, else_branch);
    // Return new stmt node
    return StmtNode{ .IF = new_stmt };
}

/// Parses a BlockStmt
/// BlockStmt -> '{' statement? '}'
fn blockStmt(self: *Parser) SyntaxError!StmtNode {
    // Make list for body statements
    var stmt_list = std.ArrayList(StmtNode).init(self.allocator);

    // Parse until next '}'
    while (!self.isAtEnd() and !self.check(TokenKind.RIGHT_BRACE)) {
        const stmt = self.declaration() catch {
            // Attempt to synch
            self.synchronize();
            continue;
        };
        stmt_list.append(stmt) catch unreachable;
    }
    // Consume '}'
    try self.consume(TokenKind.RIGHT_BRACE, "Unclosed block statement");

    // Make new stmt node
    const new_stmt = self.allocator.create(Stmt.BlockStmt) catch unreachable;
    new_stmt.* = Stmt.BlockStmt.init(stmt_list.items);
    // Return new stmt node
    return StmtNode{ .BLOCK = new_stmt };
}

/// Parse an MutateStmt
/// MutateStmt -> "mut" identifier "=" expression ";"
fn mutStmt(self: *Parser) SyntaxError!StmtNode {
    // Get id_expr
    const id_expr_result = try self.expression();
    const id_expr = id_expr_result.expr;

    // Consume (+-*/%)? '='
    if (!self.match(.{
        TokenKind.EQUAL,
        TokenKind.PLUS_EQUAL,
        TokenKind.MINUS_EQUAL,
        TokenKind.STAR_EQUAL,
        TokenKind.SLASH_EQUAL,
        TokenKind.PERCENT_EQUAL,
    })) {
        return self.errorAtCurrent("Expected a mutation operator ('=', '+=', '-=', '*=', '/=', or '%=')");
    }
    // Get operator
    const op = self.previous;

    // Parse Expression
    const assign_expr_result = try self.expression();
    const assign_expr = assign_expr_result.expr;
    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after mutation statement");

    // Make new stmt node
    const new_stmt = self.allocator.create(Stmt.MutStmt) catch unreachable;
    new_stmt.* = Stmt.MutStmt.init(id_expr, op, assign_expr);
    // Return new node
    return StmtNode{ .MUTATE = new_stmt };
}

/// Parse an ExprStmt
/// ExprStm -> expression ";"
fn exprStmt(self: *Parser) SyntaxError!StmtNode {
    // Parse expression
    const expr_result = try self.expression();
    // Unwrap expressions
    const expr = expr_result.expr;

    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after expression statement");
    // Allocate memory for new statement
    const new_stmt = self.allocator.create(Stmt.ExprStmt) catch unreachable;
    new_stmt.* = Stmt.ExprStmt.init(expr);
    // Return new node
    return StmtNode{ .EXPRESSION = new_stmt };
}

/// Parse a break stmt
/// BreakStmt -> "break" ';'
fn breakStmt(self: *Parser) SyntaxError!StmtNode {
    // Get keyword
    const op = self.previous;
    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after break statement");

    // Allocate memory for new statement
    const new_stmt = self.allocator.create(Stmt.BreakStmt) catch unreachable;
    new_stmt.* = Stmt.BreakStmt.init(op);
    // Return new node
    return StmtNode{ .BREAK = new_stmt };
}

/// Parse a break stmt
/// ContinueStmt -> "continue" ';'
fn continueStmt(self: *Parser) SyntaxError!StmtNode {
    // Get keyword
    const op = self.previous;
    // Consume ';'
    try self.consume(TokenKind.SEMICOLON, "Expected ';' after continue statement");

    // Allocate memory for new statement
    const new_stmt = self.allocator.create(Stmt.ContinueStmt) catch unreachable;
    new_stmt.* = Stmt.ContinueStmt.init(op);
    // Return new node
    return StmtNode{ .CONTINUE = new_stmt };
}

//**************************//
//      Parse Exprs
//**************************//

/// Parse an expression
/// expr -> term
fn expression(self: *Parser) SyntaxError!ExprResult {
    return self.if_expr();
}

/// Parse an If Expression
fn if_expr(self: *Parser) SyntaxError!ExprResult {
    // Get lhs
    const expr_result = try self.logic_or();
    var expr = expr_result.expr;
    // Upwrap precedence
    const precendence = expr_result.precedence;
    // Check for '?'
    if (self.match(.{TokenKind.QUESTION_MARK})) {
        // Extract if token
        const if_token = self.previous;

        // Get then branch
        const then_branch = try self.if_expr();
        // Inwrap condition expr
        const then_expr = then_branch.expr;

        // Consume ':'
        try self.consume(TokenKind.COLON, "Expected ':' after conditional then branch");

        // Get then branch
        const else_branch = try self.if_expr();
        // Inwrap condition expr
        const else_expr = else_branch.expr;

        // Make new inner expression
        const new_expr = self.allocator.create(Expr.IfExpr) catch unreachable;
        new_expr.* = Expr.IfExpr.init(if_token, expr, then_expr, else_expr);
        // Get precedence
        expr = ExprNode.init(ExprUnion{ .IF = new_expr });
    }
    // Wrap and return
    return ExprResult.init(expr, precendence);
}

/// Parse an and statement
/// and -> compare ("and" compare)*
fn logic_or(self: *Parser) SyntaxError!ExprResult {
    // Get lhs
    const lhs = try self.logic_and();
    // Unwrap expr
    var expr = lhs.expr;
    // Unwrap precedence
    var precedence = lhs.precedence;

    // While still 'and'
    while (self.match(.{TokenKind.OR})) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const rhs = try self.logic_and();

        // Make new inner expression
        const new_expr = self.allocator.create(Expr.OrExpr) catch unreachable;
        new_expr.* = Expr.OrExpr.init(expr, rhs.expr, operator);

        // Check if precedence needs to be swapped to rhs
        if (checkReversed(precedence, rhs.precedence)) {
            precedence = rhs.precedence;
        }

        expr = ExprNode.init(ExprUnion{ .OR = new_expr });
    }
    // Wrap and return
    return ExprResult.init(expr, precedence);
}

/// Parse an and statement
/// and -> compare ("and" compare)*
fn logic_and(self: *Parser) SyntaxError!ExprResult {
    // Get lhs
    const lhs = try self.compare();
    // Unwrap expr
    var expr = lhs.expr;
    // Unwrap precedence
    var precedence = lhs.precedence;

    // While still 'and'
    while (self.match(.{TokenKind.AND})) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const rhs = try self.compare();

        // Make new inner expression
        const new_expr = self.allocator.create(Expr.AndExpr) catch unreachable;
        new_expr.* = Expr.AndExpr.init(expr, rhs.expr, operator);

        // Check if precedence needs to be swapped to rhs
        if (checkReversed(precedence, rhs.precedence)) {
            precedence = rhs.precedence;
        }

        expr = ExprNode.init(ExprUnion{ .AND = new_expr });
    }
    // Wrap and return
    return ExprResult.init(expr, precedence);
}

/// Parse a compare statement
/// compare -> term (("<"|">"|"<="|">="|"=="|"!=") term)*
fn compare(self: *Parser) SyntaxError!ExprResult {
    const lhs = try self.term();
    // Extract expression
    var expr = lhs.expr;
    // Extract precedence
    var precedence = lhs.precedence;

    // While still >,<,>=,<=
    while (self.match(.{
        TokenKind.GREATER,
        TokenKind.GREATER_EQUAL,
        TokenKind.LESS,
        TokenKind.LESS_EQUAL,
        TokenKind.EQUAL_EQUAL,
        TokenKind.EXCLAMATION_EQUAL,
    })) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const rhs = try self.term();

        // Make new inner expression, with operator
        const new_expr = self.allocator.create(Expr.CompareExpr) catch unreachable;

        // Check if reversed or not
        if (checkReversed(precedence, rhs.precedence)) {
            // Rhs is bigger, swap lh and rh sides
            precedence = rhs.precedence;
            new_expr.* = Expr.CompareExpr.init(rhs.expr, expr, operator, true);
        } else {
            // Lhs is bigger, do not swap
            new_expr.* = Expr.CompareExpr.init(expr, rhs.expr, operator, false);
        }
        // Update expr
        expr = ExprNode.init(ExprUnion{ .COMPARE = new_expr });
        // Update precedence
        precedence = newPrecedence(precedence);
    }
    // Wrap and return
    return ExprResult.init(expr, precedence);
}

/// Parse an addition or subtraction statement
/// term -> factor (("-"|"+") factor)*
fn term(self: *Parser) SyntaxError!ExprResult {
    const lhs = try self.factor();
    // Extract expression
    var expr = lhs.expr;
    // Extract precedence
    var precedence = lhs.precedence;

    // While there are still '+' or '-' tokens
    while (self.match(.{ TokenKind.PLUS, TokenKind.MINUS })) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const rhs = try self.factor();

        // Make new inner expression, with operator
        const new_expr = self.allocator.create(Expr.ArithExpr) catch unreachable;

        // Check if reversed or not
        if (checkReversed(precedence, rhs.precedence)) {
            // Rhs is bigger, swap lh and rh sides
            precedence = rhs.precedence;
            new_expr.* = Expr.ArithExpr.init(rhs.expr, expr, operator, true);
        } else {
            // Lhs is bigger, do not swap
            new_expr.* = Expr.ArithExpr.init(expr, rhs.expr, operator, false);
        }
        // Update expr
        expr = ExprNode.init(ExprUnion{ .ARITH = new_expr });
        // Update precedence
        precedence = newPrecedence(precedence);
    }
    // Wrap and return
    return ExprResult.init(expr, precedence);
}

/// Parse a multiplication or division statement
/// factor -> unary (("*"|"/"|"%") unary)*
fn factor(self: *Parser) SyntaxError!ExprResult {
    const lhs = try self.unary();
    // Extract expression
    var expr = lhs.expr;
    // Extract precedence
    var precedence = lhs.precedence;

    // While there are still '/' or '*' or '%' tokens
    while (self.match(.{ TokenKind.SLASH, TokenKind.STAR, TokenKind.PERCENT })) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const rhs = try self.unary();

        // Make new inner expression, with operator
        const new_expr = self.allocator.create(Expr.ArithExpr) catch unreachable;

        // Check if reversed or not
        if (checkReversed(precedence, rhs.precedence)) {
            // Rhs is bigger, swap lh and rh sides
            precedence = rhs.precedence;
            new_expr.* = Expr.ArithExpr.init(rhs.expr, expr, operator, true);
        } else {
            // Lhs is bigger, do not swap
            new_expr.* = Expr.ArithExpr.init(expr, rhs.expr, operator, false);
        }
        // Update expr
        expr = ExprNode.init(ExprUnion{ .ARITH = new_expr });
        // Update precedence
        precedence = newPrecedence(precedence);
    }
    // Wrap and return
    return ExprResult.init(expr, precedence);
}

/// Parse a unary expression
/// unary -> ("-"|"!") (unary | literal)
fn unary(self: *Parser) SyntaxError!ExprResult {
    // Recurse until no more '+' or '!'
    if (self.match(.{ TokenKind.MINUS, TokenKind.EXCLAMATION })) {
        // Get operator
        const operator = self.previous;
        // Parse rhs
        const operand = try self.unary();

        // Make new inner expression, with operator
        const new_expr = self.allocator.create(Expr.UnaryExpr) catch unreachable;
        new_expr.* = Expr.UnaryExpr.init(operand.expr, operator);
        const node = ExprNode.init(ExprUnion{ .UNARY = new_expr });
        // Wrap in ExprResult
        return ExprResult.init(node, operand.precedence);
    }
    // Fall through to Access/call/index
    return self.access();
}

/// Helper function to "access"
/// Parse a user function call expression
/// call -> identifier '(' expression (',' expression)* ')'
fn call(self: *Parser, expr: ExprNode, operator: Token, precedence: *isize) SyntaxError!ExprNode {
    // Make call args list
    var arg_list = std.ArrayList(ExprNode).init(self.allocator);

    // Check if next token is ')'
    if (!self.match(.{TokenKind.RIGHT_PAREN})) {
        // Parse first arg
        const first_arg_result = try self.expression();
        const first_arg = first_arg_result.expr;
        // Add to list
        arg_list.append(first_arg) catch unreachable;

        // Until ')' or end of file
        while (!self.match(.{TokenKind.RIGHT_PAREN}) or self.isAtEnd()) {
            // Consume ','
            try self.consume(TokenKind.COMMA, "Expected ',' after function call argument");
            // Parse first arg
            const arg_result = try self.expression();
            const arg = arg_result.expr;
            // Add to list
            arg_list.append(arg) catch unreachable;
        }

        // Check if at end
        if (self.isAtEnd()) {
            return self.errorAt("Unclosed function call argument list");
        }
    }
    // Set precedence to -1
    precedence.* = -1;
    // Make new expression
    const new_expr = self.allocator.create(Expr.CallExpr) catch unreachable;
    // Make new call expression
    new_expr.* = Expr.CallExpr.init(expr, operator, arg_list.items);
    const node = ExprNode.init(ExprUnion{ .CALL = new_expr });
    return node;
}

/// Helper function to "access"
/// Parse a index expression
/// index -> "[" U(INT) "]"
fn index(self: *Parser, expr: ExprNode, operator: Token, precedence: *isize) SyntaxError!ExprNode {
    // Parse number in square brackets
    const rhs = try self.expression();

    // Consume "]"
    try self.consume(TokenKind.RIGHT_SQUARE, "Expected ']' after index expression");

    // Create a new IndexExpr
    const new_expr = self.allocator.create(Expr.IndexExpr) catch unreachable;

    // Check if precedence needs to be updated
    if (checkReversed(precedence.*, rhs.precedence)) {
        precedence.* = rhs.precedence;
        // And swap IndexExpr
        new_expr.* = Expr.IndexExpr.init(rhs.expr, expr, operator, true);
    } else {
        new_expr.* = Expr.IndexExpr.init(expr, rhs.expr, operator, false);
    }

    const node = ExprNode.init(ExprUnion{ .INDEX = new_expr });
    return node;
}

/// Parse an access expression
/// Access -> literal (index | call)*
/// index -> "[" U(INT) "]"
/// call -> "(" (expr ("," expr)*)? ")"
fn access(self: *Parser) SyntaxError!ExprResult {
    // Evaluate lhs
    const lhs = try self.literal();
    // Extract expr
    var expr = lhs.expr;
    // Extract precedence
    var precedence = lhs.precedence;

    // While there are "(" or "["
    while (self.match(.{ TokenKind.LEFT_PAREN, TokenKind.LEFT_SQUARE })) {
        // Get "operator"
        const operator = self.previous;

        // Parse rhs based on operator kind
        // Make new expr node and store it in expr
        expr = switch (operator.kind) {
            .LEFT_PAREN => try self.call(expr, operator, &precedence),
            .LEFT_SQUARE => try self.index(expr, operator, &precedence),
            else => unreachable,
        };
    }
    // Wrap result
    return ExprResult.init(expr, precedence);
}

/// Parse a literal value
/// ("(" expr ")") | constant | identifier | native "(" arguments? ")"
fn literal(self: *Parser) SyntaxError!ExprResult {
    // Check if this is a grouping
    if (self.match(.{TokenKind.LEFT_PAREN})) {
        // Parse new sub expression
        const expr = try self.expression();

        // Consume ')'
        try self.consume(TokenKind.RIGHT_PAREN, "Unclosed parenthesis");
        return expr;
    }
    // Store current token and advance
    const token = self.advance();
    switch (token.kind) {
        .FALSE => {
            // Make new constant expression
            const constant_expr = self.allocator.create(Expr.LiteralExpr) catch unreachable;
            // Make new value
            const value = Value.newBool(false);
            constant_expr.* = .{ .value = value, .literal = token };
            const expr = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
            // Wrap in ExprResult
            return ExprResult.init(expr, 0);
        },
        .TRUE => {
            // Make new constant expression
            const constant_expr = self.allocator.create(Expr.LiteralExpr) catch unreachable;
            // Make new value
            const value = Value.newBool(true);
            constant_expr.* = .{ .value = value, .literal = token };
            const expr = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
            // Wrap in ExprResult
            return ExprResult.init(expr, 0);
        },
        .INTEGER => {
            // Make new constant expression
            const constant_expr = self.allocator.create(Expr.LiteralExpr) catch unreachable;

            // Parse lexeme
            const parsed_int = std.fmt.parseInt(i64, token.lexeme, 10) catch {
                // Try to make it unsigned
                const parsed_uint = std.fmt.parseInt(u64, token.lexeme, 10) catch {
                    // Cannot be parsed into i64 or u64
                    return self.reportError(token, "Integer cannot be parsed into i64 or u64");
                };

                // Make u64
                const value = Value.newUInt(parsed_uint, 64);
                constant_expr.* = .{ .value = value, .literal = token };
                const node = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
                // Wrap in ExprResult
                return ExprResult.init(node, 0);
            };

            // Make new value
            const value = Value.newInt(parsed_int, 64);
            constant_expr.* = .{ .value = value, .literal = token };
            const node = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
            // Wrap in ExprResult
            return ExprResult.init(node, 0);
        },
        .FLOAT => {
            // Make new constant expression
            const constant_expr = self.allocator.create(Expr.LiteralExpr) catch unreachable;
            // Parse lexeme
            const parsed_float = std.fmt.parseFloat(f64, token.lexeme) catch unreachable;
            // Make new value
            const value = Value.newFloat64(parsed_float);
            constant_expr.* = .{ .value = value, .literal = token };
            const node = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
            // Wrap in ExprResult
            return ExprResult.init(node, 0);
        },
        .STRING => {
            // Make new constant expression
            const constant_expr = self.allocator.create(Expr.LiteralExpr) catch unreachable;
            // Make a new value without quotes

            // Make new value without quotes
            const value = Value.newStr(token.lexeme);
            constant_expr.* = .{ .value = value, .literal = token };
            const node = ExprNode.init(ExprUnion{ .LITERAL = constant_expr });
            // Wrap in ExprResult
            return ExprResult.init(node, 0);
        },
        .ARRAY_TYPE => {
            // ****************************************************** //
            // FOR NOW THROWS AN ERROR
            return self.errorAt("Do not use arrays yet please thanks");
        },
        .IDENTIFIER => {
            // Make new constant expression
            const identifier_expr = self.allocator.create(Expr.IdentifierExpr) catch unreachable;
            identifier_expr.* = .{ .id = token, .stack_offset = null };
            const node = ExprNode.init(ExprUnion{ .IDENTIFIER = identifier_expr });
            // Wrap in ExprResult
            return ExprResult.init(node, 0);
        },
        .NATIVE => {
            // Consume the '('
            try self.consume(TokenKind.LEFT_PAREN, "Expected '(' after native function");
            // Create arg list
            var arg_list = std.ArrayList(ExprNode).init(self.allocator);

            // Check if next if next is ')'
            if (!self.check(TokenKind.RIGHT_PAREN)) {
                const first_arg = try self.expression();
                arg_list.append(first_arg.expr) catch unreachable;
                // Parse until no more commas
                while (self.match(.{TokenKind.COMMA})) {
                    const next_arg = try self.expression();
                    arg_list.append(next_arg.expr) catch unreachable;
                }
            }
            // Consume ')'
            try self.consume(TokenKind.RIGHT_PAREN, "Expected ')' after arg list");

            // Make new nativeExpr
            const native_expr = self.allocator.create(Expr.NativeExpr) catch unreachable;
            native_expr.name = token;
            // "borrow" arg_list's items
            native_expr.args = arg_list.items;

            const node = ExprNode.init(ExprUnion{ .NATIVE = native_expr });
            // Wrap in ExprResult
            return ExprResult.init(node, -1);
        },
        .EOF => return self.errorAtCurrent("Expected an expression but found end of file"),
        else => return self.errorAt("Expected an expression"),
    }
}
