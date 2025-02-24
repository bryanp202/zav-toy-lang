const std = @import("std");

// Constants, types, and Symbol import
const Symbol = @import("symbols.zig");
const Value = Symbol.Value;
const KindId = Symbol.KindId;
// Token
const Token = @import("front_end/scanner.zig").Token;
// Expr
const Expr = @import("expr.zig");
const ExprNode = Expr.ExprNode;

pub const StmtNode = union(enum) {
    GLOBAL: *GlobalStmt,
    MUTATE: *MutStmt,
    DECLARE: *DeclareStmt,
    EXPRESSION: *ExprStmt,
    WHILE: *WhileStmt,
    BLOCK: *BlockStmt,
    IF: *IfStmt,
    BREAK: *BreakStmt,
    CONTINUE: *ContinueStmt,
    FUNCTION: *FunctionStmt,
    RETURN: *ReturnStmt,
    STRUCT: *StructStmt,

    /// Display a stmt
    pub fn display(self: StmtNode) void {
        // Display based off of self
        switch (self) {
            .GLOBAL => |globalStmt| {
                if (globalStmt.mutable) {
                    std.debug.print("global var {s}", .{globalStmt.id.lexeme});
                } else {
                    std.debug.print("global const {s}", .{globalStmt.id.lexeme});
                }
                // Check if type is given
                if (globalStmt.kind) |kind| {
                    std.debug.print(": {any}", .{kind});
                }
                std.debug.print(" = ", .{});
                if (globalStmt.expr) |expr| {
                    expr.display();
                } else {
                    std.debug.print("undefined", .{});
                }
                std.debug.print(";\n", .{});
            },
            .MUTATE => |mutStmt| {
                mutStmt.id_expr.display();
                std.debug.print(" {s} ", .{mutStmt.op.lexeme});
                mutStmt.assign_expr.display();
                std.debug.print(";\n", .{});
            },
            .DECLARE => |declareStmt| {
                if (declareStmt.mutable) {
                    std.debug.print("var {s}", .{declareStmt.id.lexeme});
                } else {
                    std.debug.print("const {s}", .{declareStmt.id.lexeme});
                }
                // Check if type is given
                if (declareStmt.kind) |kind| {
                    std.debug.print(": {any}", .{kind});
                }
                std.debug.print(" = ", .{});
                if (declareStmt.expr) |expr| {
                    expr.display();
                } else {
                    std.debug.print("undefined", .{});
                }
                std.debug.print(";\n", .{});
            },
            .EXPRESSION => |exprStmt| {
                exprStmt.expr.display();
                std.debug.print(";\n", .{});
            },
            .WHILE => |whileStmt| {
                std.debug.print("while(", .{});
                whileStmt.conditional.display();
                std.debug.print(") ", .{});
                whileStmt.body.display();
                if (whileStmt.loop_stmt) |loop_stmt| {
                    std.debug.print(" loop: ", .{});
                    loop_stmt.display();
                }
            },
            .IF => |ifStmt| {
                std.debug.print("if(", .{});
                ifStmt.conditional.display();
                std.debug.print(")", .{});
                ifStmt.then_branch.display();
                if (ifStmt.else_branch) |else_branch| {
                    std.debug.print("else ", .{});
                    else_branch.display();
                }
            },
            .BLOCK => |blockStmt| {
                std.debug.print("{{\n", .{});
                for (blockStmt.statements) |stmt| {
                    stmt.display();
                }
                std.debug.print("}}\n", .{});
            },
            .BREAK => {
                std.debug.print("break;\n", .{});
            },
            .CONTINUE => {
                std.debug.print("continue;\n", .{});
            },
            .FUNCTION => |funcStmt| {
                std.debug.print("fn {s} (\n", .{funcStmt.name.lexeme});
                // Print args
                for (funcStmt.arg_names, funcStmt.arg_kinds) |name, kind| {
                    std.debug.print("    {s}: {any},\n", .{ name.lexeme, kind });
                }
                std.debug.print(") {any} ", .{funcStmt.return_kind});
                funcStmt.body.display();
            },
            .RETURN => |returnStmt| {
                std.debug.print("return", .{});
                if (returnStmt.expr) |expr| {
                    std.debug.print(" ", .{});
                    expr.display();
                }
                std.debug.print(";\n", .{});
            },
            .STRUCT => |structStmt| {
                std.debug.print("struct {s} {{\n", .{structStmt.id.lexeme});
                // Print Fields
                for (structStmt.field_names, structStmt.field_kinds) |name, kind| {
                    std.debug.print("    {s}: {any},\n", .{ name.lexeme, kind });
                }
                std.debug.print("}}\n", .{});
            },
        }
    }
};

// ************** //
//   Stmt Structs //
// ************** //
/// Used to store an MutExpr
/// MutStmt -> identifier "=" expression ";"
pub const MutStmt = struct {
    id_expr: ExprNode,
    op: Token,
    assign_expr: ExprNode,
    id_kind: KindId,

    /// Initialize an AssignStmt with an exprnode
    pub fn init(id_expr: ExprNode, op: Token, assign_expr: ExprNode) MutStmt {
        return MutStmt{
            .id_expr = id_expr,
            .op = op,
            .assign_expr = assign_expr,
            .id_kind = undefined,
        };
    }
};

/// Used to store an GlobalStmt
/// GlobalStmt -> ("const"|"var") identifier (":" type)? "=" expression ";"
pub const GlobalStmt = struct {
    mutable: bool,
    id: Token,
    kind: ?KindId,
    op: Token,
    expr: ?ExprNode,

    /// Initialize a GlobalStmt with an mutablity, identifier token, optional kind, and expr
    pub fn init(mutable: bool, id: Token, kind: ?KindId, op: Token, expr: ?ExprNode) GlobalStmt {
        return GlobalStmt{
            .mutable = mutable,
            .id = id,
            .kind = kind,
            .op = op,
            .expr = expr,
        };
    }
};

/// Used to store a function stmt
/// FunctionStmt -> "fn" identifier '(' arglist? ')' type BlockStmt
/// arglist -> arg (',' arg)*
/// arg -> identifier ':' type
pub const FunctionStmt = struct {
    /// Used to store an argument
    pub const Arg = struct {
        name: Token,
        kind: KindId,
    };
    // Fields
    op: Token,
    name: Token,
    arg_names: []Token,
    arg_kinds: []KindId,
    locals_size: u64,
    return_kind: KindId,
    body: StmtNode,

    /// Iniitalize a Function Statement
    pub fn init(op: Token, name: Token, arg_names: []Token, arg_kinds: []KindId, return_kind: KindId, body: StmtNode) FunctionStmt {
        return FunctionStmt{
            .op = op,
            .name = name,
            .arg_names = arg_names,
            .arg_kinds = arg_kinds,
            .locals_size = undefined,
            .return_kind = return_kind,
            .body = body,
        };
    }
};

/// Used to create a new KindId for a struct
/// StructStmt -> "struct" identifier '{' fieldlist '}'
/// FieldList -> (Field ';')+
/// Field -> identifier ':' KindId
pub const StructStmt = struct {
    id: Token,
    field_names: []Token,
    field_kinds: []KindId,

    /// Initialize a structstmt
    pub fn init(id: Token, field_names: []Token, field_kinds: []KindId) StructStmt {
        return StructStmt{
            .id = id,
            .field_names = field_names,
            .field_kinds = field_kinds,
        };
    }
};

/// Used to store an DeclareStmt
/// DeclareStmt -> ("const"|"var") identifier (":" type)? "=" expression ";"
pub const DeclareStmt = struct {
    mutable: bool,
    id: Token,
    kind: ?KindId,
    op: Token,
    expr: ?ExprNode,
    stack_offset: u64,

    /// Initialize a DeclareStmt with an mutablity, identifier token, optional kind, and expr
    pub fn init(mutable: bool, id: Token, kind: ?KindId, op: Token, expr: ?ExprNode) DeclareStmt {
        return DeclareStmt{
            .mutable = mutable,
            .id = id,
            .kind = kind,
            .op = op,
            .expr = expr,
            .stack_offset = undefined,
        };
    }
};

/// Used to store an ExprStmt
/// exprstmt -> expression ";"
pub const ExprStmt = struct {
    expr: ExprNode,

    /// Initialize an expr stmt with an exprnode
    pub fn init(expr: ExprNode) ExprStmt {
        return ExprStmt{ .expr = expr };
    }
};

/// Used to store a WhileStmt
/// whilestmt -> "while" '(' expression ')' statement ("loop: " statemnt)?
pub const WhileStmt = struct {
    op: Token,
    conditional: ExprNode,
    body: StmtNode,
    loop_stmt: ?StmtNode,

    /// Initialize an expr stmt for while loop
    pub fn init(op: Token, conditional: ExprNode, body: StmtNode, loop_stmt: ?StmtNode) WhileStmt {
        return WhileStmt{
            .op = op,
            .conditional = conditional,
            .body = body,
            .loop_stmt = loop_stmt,
        };
    }
};

/// Used to store an IfStmt
/// ifstmt -> "if" '(' expression ')' statement ("else" statement)?
pub const IfStmt = struct {
    op: Token,
    conditional: ExprNode,
    then_branch: StmtNode,
    else_branch: ?StmtNode,

    /// Initialize an expr stmt for while loop
    pub fn init(op: Token, conditional: ExprNode, then_branch: StmtNode, else_branch: ?StmtNode) IfStmt {
        return IfStmt{
            .op = op,
            .conditional = conditional,
            .then_branch = then_branch,
            .else_branch = else_branch,
        };
    }
};

/// Used to store a blockstmt
/// blockstmt -> '{' statement? '}'
pub const BlockStmt = struct {
    statements: []StmtNode,

    /// Initialize a block stmt
    pub fn init(statements: []StmtNode) BlockStmt {
        return BlockStmt{ .statements = statements };
    }
};

/// Used to store a continue stmt
/// continuestmt -> "continue" ';'
pub const ContinueStmt = struct {
    op: Token,

    /// Initialize a continue stmt
    pub fn init(op: Token) ContinueStmt {
        return ContinueStmt{ .op = op };
    }
};

/// Used to store a break stmt
/// breakstmt -> "break" ';'
pub const BreakStmt = struct {
    op: Token,

    /// Initialize a BreakStmt
    pub fn init(op: Token) BreakStmt {
        return BreakStmt{ .op = op };
    }
};

/// Used to store a return stmt
/// returnStmt -> "return" expression? ';'
pub const ReturnStmt = struct {
    op: Token,
    expr: ?ExprNode,

    /// Initialize a ReturnStmt
    pub fn init(op: Token, expr: ?ExprNode) ReturnStmt {
        return ReturnStmt{
            .op = op,
            .expr = expr,
        };
    }
};
