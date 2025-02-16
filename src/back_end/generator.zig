const std = @import("std");
// Imports
// Tokens and TokenKind
const Scan = @import("../front_end/scanner.zig");
const Token = Scan.Token;
const TokenKind = Scan.TokenKind;
// STM, Symbols, types, and constants
const Symbols = @import("../symbols.zig");
const STM = Symbols.SymbolTableManager;
const Value = Symbols.Value;
const KindId = Symbols.KindId;
const Symbol = Symbols.Symbol;
// Error
const Error = @import("../error.zig");
const GenerationError = Error.GenerationError;
// Expr
const Expr = @import("../expr.zig");
const ExprNode = Expr.ExprNode;
// Stmt Import
const Stmt = @import("../stmt.zig");
const StmtNode = Stmt.StmtNode;
// Module import
const Module = @import("../module.zig");
// Register Stack
const Registers = @import("register_stack.zig");
const RegisterStack = Registers.RegisterStack;
const Register = Registers.Register;

// Writer Type stuff
const BaseWriterType = @typeInfo(@TypeOf(std.fs.File.writer)).Fn.return_type orelse void;
const BufferedWriterType = std.io.BufferedWriter(4096, BaseWriterType);
const WriterType = @typeInfo(@TypeOf(BufferedWriterType.writer)).Fn.return_type orelse void;

// Useful Constants
const DWORD_IMIN: i64 = -0x80000000;
const DWORD_IMAX: i64 = 0x7FFFFFFF;
const DWORD_UMAX: u64 = 0xFFFFFFFF;
// Register names for cpu 64 bit
const cpu_reg_names = [_][]const u8{ "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15" };
// Alternate sized cpu register names
pub const cpu_reg_names_32bit = [_][]const u8{ "esi", "edi", "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d" };
pub const cpu_reg_names_16bit = [_][]const u8{ "si", "di", "r8w", "r9w", "r10w", "r11w", "r12w", "r13w", "r14w", "r15w" };
pub const cpu_reg_names_8bit = [_][]const u8{ "sil", "dil", "r8b", "r9b", "r10b", "r11b", "r12b", "r13b", "r14b", "r15b" };
// Floating point
const sse_reg_names = [_][]const u8{ "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7" };

/// Used to turn an AST into assembly
const Generator = @This();
// Fields
file: std.fs.File,
buffered_writer_ptr: *BufferedWriterType,
writer: WriterType,
stm: *STM,

// Label counters
/// Used in the generation of if statement labels
label_count: usize,
/// Used for break statements jump point
break_label: usize,
/// Used for continue statements jump point
continue_label: usize,

// Register count
cpu_reg_stack: RegisterStack(cpu_reg_names),
sse_reg_stack: RegisterStack(sse_reg_names),

pub fn open(allocator: std.mem.Allocator, stm: *STM, path: []const u8) !Generator {
    const file = try std.fs.cwd().createFile(path, .{ .read = true });
    const base_writer_ptr = allocator.create(BaseWriterType) catch unreachable;
    const buffered_writer_ptr = allocator.create(BufferedWriterType) catch unreachable;
    base_writer_ptr.* = file.writer();
    buffered_writer_ptr.* = std.io.bufferedWriter(base_writer_ptr.*);
    var writer = buffered_writer_ptr.*.writer();

    // Set up file header
    const header =
        \\default rel
        \\extern printf
        \\extern QueryPerformanceCounter
        \\global main
        \\section .text
        \\main:
        \\    ; Setup clock
        \\    push rax
        \\    mov rcx, rsp
        \\    call QueryPerformanceCounter
        \\    pop qword [@CLOCK_START]
        \\
        \\    ; Global Declarations
        \\
    ;
    _ = try writer.write(header);

    return .{
        .file = file,
        .buffered_writer_ptr = buffered_writer_ptr,
        .writer = writer,
        .stm = stm,
        .label_count = 0,
        .break_label = undefined,
        .continue_label = undefined,
        .cpu_reg_stack = RegisterStack(cpu_reg_names).init(),
        .sse_reg_stack = RegisterStack(sse_reg_names).init(),
    };
}

pub fn close(self: Generator) GenerationError!void {
    // Write end of file
    try self.write(
        \\    
        \\;-------------------------;
        \\;         Natives         ;
        \\;-------------------------;
        \\
    );

    // Write native functions source
    var native_func = self.stm.natives_table.natives_table.iterator();
    // Go through each
    while (native_func.next()) |native| {
        if (native.value_ptr.used and native.value_ptr.inline_gen == null) {
            _ = try self.write(native.value_ptr.source);
        }
    }

    // Write .data section
    try self.write(
        \\
        \\section .data
        \\    ; Native Constants ;
        \\    @SS_SIGN_BIT: dq 0x80000000, 0, 0, 0
        \\    @SD_SIGN_BIT: dq 0x8000000000000000, 0, 0, 0
        \\
    );
    // Write native data
    // Write native functions source
    native_func = self.stm.natives_table.natives_table.iterator();
    // Go through each
    while (native_func.next()) |native| {
        if (native.value_ptr.used) {
            if (native.value_ptr.data) |data| {
                try self.print("{s}", .{data});
            }
        }
    }

    // Write the program defined constants section
    try self.write("\n    ; Program Constants ;\n");
    var const_iter = self.stm.constants.iterator();
    while (const_iter.next()) |entry| {
        // Extract entry
        const constant = entry.value_ptr;
        const maybeName = constant.name;
        // See if it has been used, look for name
        if (maybeName) |name| {
            // Get the real value
            const real_value = constant.data;
            // Determine how to write to data section
            switch (real_value.kind) {
                .FLOAT32 => {
                    const float = real_value.as.float32;
                    try self.print("    {s}: dd {e}\n", .{ name, float });
                },
                .FLOAT64 => {
                    const float = real_value.as.float64;
                    try self.print("    {s}: dq {e}\n", .{ name, float });
                },
                .STRING => {
                    const string = real_value.as.string.data.slice();
                    const extracted_str = string[1 .. string.len - 1];
                    try self.print("    {s}: db `{s}`, 0\n", .{ name, extracted_str });
                },
                else => unreachable,
            }
        }
    }

    // Write global variables to bss section
    try self.write("\nsection .bss\n    @CLOCK_START: resb 8\n\n    ; Program Globals ;\n");
    // Reset scope stack
    self.stm.resetStack();
    var global_iter = self.stm.active_scope.symbols.iterator();
    // Write each variable to the file
    while (global_iter.next()) |global_entry| {
        // Extract global
        const global = global_entry.value_ptr;
        // Write to file if not function
        if (global.kind != .FUNC) {
            try self.print("    _{s}: resb {d}\n", .{ global.name, global.size });
        }
    }

    // Flush buffer
    self.buffered_writer_ptr.*.flush() catch return GenerationError.FailedToWrite;
    // Close file
    self.file.close();
}

/// Walk the ast, generating ASM
pub fn genModule(self: *Generator, module: Module) GenerationError!void {
    // Reset STM stack
    self.stm.resetStack();

    // Generate all statements in the module
    for (module.globalSlice()) |global| {
        try self.visitGlobalStmt(global.GLOBAL.*);
    }

    // Get stack size of main
    const main_symbol = self.stm.getSymbol("main") catch unreachable;
    const stack_size = main_symbol.kind.FUNC.stack_offset;

    // Set up main call
    try self.write("\n    push rbp\n    mov rbp, rsp\n");

    // Offset stack for locals
    try self.print("    sub rsp, {d} ; Set up main locals\n", .{stack_size});
    // Write jump to _main
    try self.write("    call _main\n");
    // Clear mains locals
    try self.print("    add rsp, {d} ; Clean up main locals\n", .{stack_size});
    // Write exit
    try self.write("    mov rcx, rax\n    leave\n    ret\n\n");

    // Generate all functions in the module
    for (module.functionSlice()) |function| {
        try self.visitFunctionStmt(function.FUNCTION.*);
    }
}

// ********************** //
// Private helper methods //
// ********************** //

/// Returns the realigned next address for the stack
fn realignStack(next_address: u64, size: u64) u64 {
    // Get allignment of data size
    const alignment: u64 = @min(size, 8);
    const offset = next_address & (alignment - 1);

    // Check if needs to be realigned
    if (offset != 0) {
        return next_address + (alignment - offset);
    }
    // Is already aligned
    return next_address;
}

/// Return the keyword such as "byte", "dword" for a given KindId size
fn getSizeKeyword(size: u64) []const u8 {
    return switch (size) {
        1 => "byte",
        2 => "word",
        4 => "dword",
        else => "qword",
    };
}

/// Return the properly sized name for a cpu register
fn getSizedCPUReg(index: usize, size: u64) []const u8 {
    return switch (size) {
        1 => Generator.cpu_reg_names_8bit[index],
        2 => Generator.cpu_reg_names_16bit[index],
        4 => Generator.cpu_reg_names_32bit[index],
        else => Generator.cpu_reg_names[index],
    };
}

/// Helper methods, uses the writer to output to the asm file
pub inline fn write(self: Generator, msg: []const u8) GenerationError!void {
    _ = self.writer.write(msg) catch return GenerationError.FailedToWrite;
}
/// Helper methods, uses the writer to output to the asm file
/// Takes in fmt and things to put in
pub inline fn print(self: Generator, fmt: []const u8, data: anytype) GenerationError!void {
    self.writer.print(fmt, data) catch return GenerationError.FailedToWrite;
}

/// Get the current cpu register name
pub fn getCurrCPUReg(self: *Generator) Register {
    return self.cpu_reg_stack.current();
}

/// Get the current sse register name
pub fn getCurrSSEReg(self: *Generator) Register {
    return self.sse_reg_stack.current();
}

/// Get the next cpu register name.
/// Increment the cpu register 'stack', throwing an error if no more registers
pub fn getNextCPUReg(self: *Generator) GenerationError!Register {
    return self.cpu_reg_stack.loadNew();
}

/// Get the next sse register name.
/// Increment the sse register 'stack', throwing an error if no more registers
pub fn getNextSSEReg(self: *Generator) GenerationError!Register {
    return self.sse_reg_stack.loadNew();
}

/// Pop the current cpu register
pub fn popCPUReg(self: *Generator) Register {
    return self.cpu_reg_stack.pop();
}

/// Push a register onto the cpu register stack
pub fn pushCPUReg(self: *Generator, reg: Register) void {
    return self.cpu_reg_stack.push(reg);
}

/// Push a register onto the sse register stack
pub fn pushSSEReg(self: *Generator, reg: Register) void {
    return self.sse_reg_stack.push(reg);
}

/// Pop the current sse register
pub fn popSSEReg(self: *Generator) Register {
    return self.sse_reg_stack.pop();
}

/// Store all active cpu registers onto the stack.
/// Useful to use before function calls
fn storeCPUReg(self: *Generator) GenerationError!usize {
    // Store register count
    const reg_count = self.cpu_reg_stack.count;

    for (reg_count) |_| {
        const reg = self.popCPUReg();
        try self.print("    push {s}\n", .{reg.name});
    }
    // Return count
    return reg_count;
}

/// Store all active sse registers onto the stack.
/// Useful to use before function calls
fn storeSSEReg(self: *Generator) GenerationError!usize {
    // Store register count
    const reg_count = self.sse_reg_stack.count;

    for (reg_count) |_| {
        const reg = self.popSSEReg();
        try self.print("    sub rsp, 8\n movq [rsp], {s}\n", .{reg.name});
    }
    // Return count
    return reg_count;
}

/// Pop all stored cpu registers from the stack.
/// Used after storeCPUReg
fn restoreCPUReg(self: *Generator, reg_count: usize) GenerationError!void {
    for (0..reg_count) |_| {
        const reg = try self.getNextCPUReg();
        try self.print("    pop {s}\n", .{reg.name});
    }
}

/// Pop all stored sse registers from the stack.
/// Used after storeCPUReg
fn restoreSSEReg(self: *Generator, reg_count: usize) GenerationError!void {
    for (0..reg_count) |_| {
        const reg = try self.getNextSSEReg();
        try self.print("    movq {s}, [rsp]\n    add rsp, 8\n", .{reg.name});
    }
}

// ********************** //
// Stmt anaylsis  methods //
// ********************** //
/// Determine the type of stmt and call appropriate helper function
fn genStmt(self: *Generator, stmt: StmtNode) GenerationError!void {
    // Determine kind of stmt
    switch (stmt) {
        .EXPRESSION => |exprStmt| try self.visitExprStmt(exprStmt.*),
        .DECLARE => |declareStmt| try self.visitDeclareStmt(declareStmt.*),
        .MUTATE => |mutStmt| try self.visitMutateStmt(mutStmt.*),
        .WHILE => |whileStmt| try self.visitWhileStmt(whileStmt.*),
        .IF => |ifStmt| try self.visitIfStmt(ifStmt.*),
        .BLOCK => |blockStmt| try self.visitBlockStmt(blockStmt.*),
        .BREAK => |breakStmt| try self.visitBreakStmt(breakStmt.*),
        .CONTINUE => |continueStmt| try self.visitContinueStmt(continueStmt.*),
        else => unreachable,
    }
}

/// Generate the asm for a global declare stmt
fn visitGlobalStmt(self: *Generator, globalStmt: Stmt.GlobalStmt) GenerationError!void {
    // Get the symbol
    const identifier = self.stm.getSymbol(globalStmt.id.lexeme) catch unreachable;
    // Generate expression
    try self.genExpr(globalStmt.expr);

    // Pop register based on result type
    const result_kind = globalStmt.expr.result_kind;
    if (result_kind == .FLOAT32) {
        const reg = self.popSSEReg();
        try self.print("    movss [_{s}], {s} ; Declare identifier\n", .{ identifier.name, reg.name });
    } else if (result_kind == .FLOAT64) {
        const reg = self.popSSEReg();
        try self.print("    movsd [_{s}], {s} ; Declare identifier\n", .{ identifier.name, reg.name });
    } else {
        // Get size and size keyword
        const size = globalStmt.kind.?.size_runtime();
        // Get register
        const reg = self.popCPUReg();
        // Get properly sized register
        const sized_reg = getSizedCPUReg(reg.index, size);

        // Write assignment
        try self.print("    mov [_{s}], {s} ; Declare identifier\n", .{ identifier.name, sized_reg });
    }
}

/// Generate the asm for a function declaration
fn visitFunctionStmt(self: *Generator, functionStmt: Stmt.FunctionStmt) GenerationError!void {
    // Enter scope
    self.stm.pushScope();

    // Write the functions label
    try self.print("\n_{s}:\n", .{functionStmt.name.lexeme});
    // Push rbp and move rsp to rbp
    try self.write("    push rbp\n    mov rbp, rsp\n");

    // Generate body
    try self.genStmt(functionStmt.body);

    // Generate default return and rbp pop
    _ = try self.write("    pop rbp\n    xor ecx, ecx\n    ret\n");

    // Exit scope
    self.stm.popScope();
}

/// Generate the asm for a declare stmt
fn visitDeclareStmt(self: *Generator, declareStmt: Stmt.DeclareStmt) GenerationError!void {
    // Generate expression
    try self.genExpr(declareStmt.expr);
    // Get stack offset
    const offset = declareStmt.stack_offset + 16;

    // Pop register based on result type
    const result_kind = declareStmt.expr.result_kind;
    if (result_kind == .FLOAT32) {
        const reg = self.popSSEReg();
        try self.print("    movss [rbp + {d}], {s} ; Declare identifier\n", .{ offset, reg.name });
    } else if (result_kind == .FLOAT64) {
        const reg = self.popSSEReg();
        try self.print("    movsd [rbp + {d}], {s} ; Declare identifier\n", .{ offset, reg.name });
    } else {
        // Get size and size keyword
        const size = declareStmt.kind.?.size_runtime();
        // Get register
        const reg = self.popCPUReg();
        // Get properly sized register
        const sized_reg = getSizedCPUReg(reg.index, size);

        // Write assignment
        try self.print("    mov [rbp + {d}], {s} ; Declare identifier\n", .{ offset, sized_reg });
    }
}

/// Generate the asm for a block stmt
fn visitBlockStmt(self: *Generator, blockStmt: Stmt.BlockStmt) GenerationError!void {
    // Push scope
    self.stm.pushScope();
    // Generate each statement
    for (blockStmt.statements) |stmt| {
        try self.genStmt(stmt);
    }
    // Pop scope
    self.stm.popScope();
}

/// Generate the asm for an expr stmt
fn visitExprStmt(self: *Generator, exprStmt: Stmt.ExprStmt) GenerationError!void {
    // Generate the stored exprnode
    try self.genExpr(exprStmt.expr);
    // Pop last register, based on if float or not
    if (exprStmt.expr.result_kind == .FLOAT32 or exprStmt.expr.result_kind == .FLOAT64) {
        _ = self.popSSEReg();
    } else {
        _ = self.popCPUReg();
    }
}

/// Generate the asm for a mutate stmt
fn visitMutateStmt(self: *Generator, mutStmt: Stmt.MutStmt) GenerationError!void {
    // Generate the assignment expression
    try self.genExpr(mutStmt.assign_expr);
    // Generate the id expression
    try self.genIDExpr(mutStmt.id_expr);

    // Pop id of the stack
    const id_reg = self.popCPUReg();
    // Check if result is a float or not
    if (mutStmt.id_kind == .FLOAT32) {
        // Get register
        const expr_reg = self.popSSEReg();
        // Write assignemnt
        try self.print("    movss [{s}], {s} ; Mutate\n", .{ id_reg.name, expr_reg.name });
    } else if (mutStmt.id_kind == .FLOAT64) {
        // Get register
        const expr_reg = self.popSSEReg();
        // Write assignemnt
        try self.print("    movsd [{s}], {s} ; Mutate\n", .{ id_reg.name, expr_reg.name });
    } else {
        // Get register
        const expr_reg = self.popCPUReg();
        // Write assignemnt
        try self.print("    mov [{s}], {s} ; Mutate\n", .{ id_reg.name, expr_reg.name });
    }
}

/// Generate the asm for a while loop
fn visitWhileStmt(self: *Generator, whileStmt: Stmt.WhileStmt) GenerationError!void {
    // Store old break label
    const old_break_label = self.break_label;
    // Get new label for end/outside of loop
    const exit_label = self.label_count;
    self.label_count += 1;
    // Update break label
    self.break_label = exit_label;

    // Generate the conditional once to jump over the loop if
    try self.genExpr(whileStmt.conditional);
    // Pop the value
    const jump_over_cond_reg = self.popCPUReg();
    // Generate conditional jump over
    try self.print(
        "    test {s}, {s} ; Exit check\n    jz .L{d}\n",
        .{ jump_over_cond_reg.name, jump_over_cond_reg.name, exit_label },
    );

    // Generate start of loop label
    const start_label = self.label_count;
    self.label_count += 1;
    try self.print(".L{d}:\n", .{start_label});

    // Store old continue label
    const old_cont_label = self.continue_label;
    // Generate the continue label
    const cont_label = self.label_count;
    self.label_count += 1;
    // Update cont label
    self.continue_label = cont_label;

    // Generate body
    try self.genStmt(whileStmt.body);

    // Write label for continue statements
    try self.print(".L{d}:\n", .{self.continue_label});
    // Check for loop stmt
    if (whileStmt.loop_stmt) |loop_stmt| {
        // Generate it
        try self.genStmt(loop_stmt);
    }

    // Write conditional again
    try self.genExpr(whileStmt.conditional);
    // Pop the value
    const body_cond_reg = self.popCPUReg();
    // Generate conditional jump over
    try self.print(
        "    test {s}, {s} ; Loop check\n    jnz .L{d}\n",
        .{ body_cond_reg.name, body_cond_reg.name, start_label },
    );

    // Generate exit label
    try self.print(".L{d}:\n", .{exit_label});
    // Set break label and continue label to old on
    self.break_label = old_break_label;
    self.continue_label = old_cont_label;
}

/// Generate an if statement
fn visitIfStmt(self: *Generator, ifStmt: Stmt.IfStmt) GenerationError!void {
    // Generate conditional
    try self.genExpr(ifStmt.conditional);

    // Get end of then branch label
    const else_label = self.label_count;
    self.label_count += 1;

    // Pop conditional register
    const cond_reg = self.popCPUReg();
    // Write jump over then branch check
    try self.print("    test {s}, {s}\n    jz .L{d}\n", .{ cond_reg.name, cond_reg.name, else_label });
    // Generate then branch
    try self.genStmt(ifStmt.then_branch);

    // Check for else branch
    if (ifStmt.else_branch) |else_branch| {
        // Get label for jump over else branch
        const if_end_label = self.label_count;
        self.label_count += 1;

        // Generate jump to end
        try self.print("    jmp .L{d}\n", .{if_end_label});
        // Generate then branch skip label
        try self.print(".L{d}:\n", .{else_label});

        // Generate else branch
        try self.genStmt(else_branch);
        // Write end of if label
        try self.print(".L{d}:\n", .{if_end_label});
    } else {
        // Generate then branch skip label
        try self.print(".L{d}:\n", .{else_label});
    }
}

/// Generate the jump for a break stmt
fn visitBreakStmt(self: *Generator, breakStmt: Stmt.BreakStmt) GenerationError!void {
    _ = breakStmt;
    // Write jump
    try self.print("    jmp .L{d}\n", .{self.break_label});
}

/// Generate the jump for a continue stmt
fn visitContinueStmt(self: *Generator, continueStmt: Stmt.ContinueStmt) GenerationError!void {
    _ = continueStmt;
    // Write jump
    try self.print("    jmp .L{d}\n", .{self.continue_label});
}

// ********************** //
// Expr anaylsis  methods //
// ********************** //

/// Generate asm for the lhs of a mutate expression
fn genIDExpr(self: *Generator, node: ExprNode) GenerationError!void {
    // Determine the type of expr and analysis it
    switch (node.expr) {
        .IDENTIFIER => |idExpr| try self.visitIdentifierExprID(idExpr),
        .INDEX => |indexExpr| try self.visitIndexExprID(indexExpr),
        else => unreachable,
    }
}

/// Generate asm for an ExprNode
fn genExpr(self: *Generator, node: ExprNode) GenerationError!void {
    // Get result kind
    const result_kind = node.result_kind;
    // Determine the type of expr and analysis it
    switch (node.expr) {
        .IDENTIFIER => |idExpr| try self.visitIdentifierExpr(idExpr, result_kind),
        .LITERAL => |litExpr| try self.visitLiteralExpr(litExpr),
        .NATIVE => |nativeExpr| try self.visitNativeExpr(nativeExpr, result_kind),
        .CALL => |callExpr| try self.visitCallExpr(callExpr, result_kind),
        .CONVERSION => |convExpr| try self.visitConvExpr(convExpr, result_kind),
        .INDEX => |indexExpr| try self.visitIndexExpr(indexExpr, result_kind),
        .UNARY => |unaryExpr| try self.visitUnaryExpr(unaryExpr),
        .ARITH => |arithExpr| try self.visitArithExpr(arithExpr),
        .COMPARE => |compareExpr| try self.visitCompareExpr(compareExpr),
        .AND => |andExpr| try self.visitAndExpr(andExpr),
        .OR => |orExpr| try self.visitOrExpr(orExpr),
        .IF => |ifExpr| try self.visitIfExpr(ifExpr, result_kind),
        //else => unreachable,
    }
}

/// Generate the asm for an IdentifierExpr but for the lhs of an assignment
fn visitIdentifierExprID(self: *Generator, idExpr: *Expr.IdentifierExpr) GenerationError!void {
    // Get register to store pointer in
    const reg = try self.getNextCPUReg();
    // Get pointer to the identifier
    const id_name = idExpr.id.lexeme;

    // Check if stack offset
    if (idExpr.stack_offset) |offset| {
        // Write as local
        try self.print("    lea {s}, [rbp+{d}] ; Get Local\n", .{ reg.name, offset + 16 });
    } else {
        // Write as global
        try self.print("    lea {s}, [_{s}] ; Get Global\n", .{ reg.name, id_name });
    }
}

/// Generate asm for an IDExpr
fn visitIdentifierExpr(self: *Generator, idExpr: *Expr.IdentifierExpr, result_kind: KindId) GenerationError!void {
    // Get size of kind
    const kind_size = result_kind.size_runtime();
    // Get keyword based on size
    const size_keyword = getSizeKeyword(kind_size);

    // Check if stack offset
    if (idExpr.stack_offset) |stack_offset| {
        const offset = stack_offset + 16;
        // Generate as local
        if (result_kind == .FLOAT32) {
            const reg = try self.getNextSSEReg();
            // Mov normally
            try self.print(
                "    movss {s}, {s} [rbp+{d}] ; Get Local\n",
                .{ reg.name, size_keyword, offset },
            );
        } else if (result_kind == .FLOAT64) {
            const reg = try self.getNextSSEReg();
            // Mov normally
            try self.print(
                "    movsd {s}, {s} [rbp+{d}] ; Get Local\n",
                .{ reg.name, size_keyword, offset },
            );
        } else {
            const reg = try self.getNextCPUReg();
            // Check if size is 64 bit
            if (kind_size == 8) {
                // Mov normally
                try self.print(
                    "    mov {s}, {s} [rbp+{d}] ; Get Local\n",
                    .{ reg.name, size_keyword, offset },
                );
            } else {
                // Check if unsigned
                if (result_kind == .INT) {
                    // Move and extend sign bit
                    try self.print(
                        "    movsx {s}, {s} [rbp+{d}] ; Get Local\n",
                        .{ reg.name, size_keyword, offset },
                    );
                } else {
                    // Move and zero top
                    try self.print(
                        "    movzx {s}, {s} [rbp+{d}] ; Get Local\n",
                        .{ reg.name, size_keyword, offset },
                    );
                }
            }
        }
    } else {
        if (result_kind == .FUNC) {
            const reg = try self.getNextCPUReg();
            // Write function pointer load
            try self.print("    lea {s}, [_{s}] ; Get Function\n", .{ reg.name, idExpr.id.lexeme });
        } else if (result_kind == .FLOAT32) {
            const reg = try self.getNextSSEReg();
            // Mov normally
            try self.print(
                "    movss {s}, {s} [_{s}] ; Get Global\n",
                .{ reg.name, size_keyword, idExpr.id.lexeme },
            );
        } else if (result_kind == .FLOAT64) {
            const reg = try self.getNextSSEReg();
            // Mov normally
            try self.print(
                "    movsd {s}, {s} [_{s}] ; Get Global\n",
                .{ reg.name, size_keyword, idExpr.id.lexeme },
            );
        } else {
            const reg = try self.getNextCPUReg();
            // Check if size is 64 bit
            if (kind_size == 8) {
                // Mov normally
                try self.print(
                    "    mov {s}, {s} [_{s}] ; Get Global\n",
                    .{ reg.name, size_keyword, idExpr.id.lexeme },
                );
            } else {
                // Check if unsigned
                if (result_kind == .INT) {
                    // Move and extend sign bit
                    try self.print(
                        "    movsx {s}, {s} [_{s}] ; Get Global\n",
                        .{ reg.name, size_keyword, idExpr.id.lexeme },
                    );
                } else {
                    // Move and zero top
                    try self.print(
                        "    movzx {s}, {s} [_{s}] ; Get Global\n",
                        .{ reg.name, size_keyword, idExpr.id.lexeme },
                    );
                }
            }
        }
    }
}

/// Generate asm for a LiteralExpr
fn visitLiteralExpr(self: *Generator, litExpr: *Expr.LiteralExpr) GenerationError!void {
    // Determine Value kind
    switch (litExpr.value.kind) {
        .BOOL => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            // Extract the real data from union
            const lit_val: u16 = if (litExpr.value.as.boolean) 1 else 0;
            try self.print("    mov {s}, {d} ; Load BOOL\n", .{ reg.name, lit_val });
        },
        .UINT => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            // Extract the real data from union
            const lit_val = litExpr.value.as.uint.data;
            try self.print("    mov {s}, {d} ; Load UINT\n", .{ reg.name, lit_val });
        },
        .INT => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            // Extract the real data from union
            const lit_val = litExpr.value.as.int.data;
            try self.print("    mov {s}, {d} ; Load INT\n", .{ reg.name, lit_val });
        },
        .FLOAT32 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            // Get the constants name
            const lit_name = self.stm.getConstantId(litExpr.value);
            try self.print("    movss {s}, [{s}] ; Load F32\n", .{ reg.name, lit_name });
        },
        .FLOAT64 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            // Get the constants name
            const lit_name = self.stm.getConstantId(litExpr.value);
            try self.print("    movsd {s}, [{s}] ; Load F64\n", .{ reg.name, lit_name });
        },
        .STRING => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            // Get the constants name
            const lit_name = self.stm.getConstantId(litExpr.value);
            try self.print("    lea {s}, [{s}]\n", .{ reg.name, lit_name });
        },
        else => unreachable,
    }
}

/// Generate asm for a native expr call
fn visitNativeExpr(self: *Generator, nativeExpr: *Expr.NativeExpr, result_kind: KindId) GenerationError!void {
    // Preserve current registers
    const cpu_reg_count = try self.storeCPUReg();
    const sse_reg_count = try self.storeSSEReg();

    // Holds active args
    var args: []ExprNode = undefined;
    args.len = 0;
    // Get natives name
    const native_name = nativeExpr.name.lexeme[1..];
    // Extract arguments
    const total_args = nativeExpr.args;

    // Remove any comptime only args
    const ct_arg_count = self.stm.natives_table.getComptimeArgCount(native_name);
    // Slice to remove args
    args = total_args[ct_arg_count..total_args.len];

    // Make space for all args
    const args_size = args.len * 8;
    if (args_size > 0) {
        try self.print("    sub rsp, {d}\n", .{args_size});
    }

    // Generate each arg
    for (args, 0..) |arg, count| {
        // Generate the arg expression
        try self.genExpr(arg);

        // Calculate stack position
        const stack_pos = count * 8;

        // Push onto the stack
        switch (arg.result_kind) {
            .BOOL => {
                // Get register and pop
                const reg = self.popCPUReg();
                // Insert arg based on size
                try self.print(
                    "    movzx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                    .{ reg.name, cpu_reg_names_8bit[reg.index], stack_pos, reg.name },
                );
            },
            .UINT => |uint| {
                // Get register and pop
                const reg = self.popCPUReg();
                // Insert arg based on size
                switch (uint.size()) {
                    1 => try self.print(
                        "    movzx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ reg.name, cpu_reg_names_8bit[reg.index], stack_pos, reg.name },
                    ),
                    2 => try self.print(
                        "    movzx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ reg.name, cpu_reg_names_16bit[reg.index], stack_pos, reg.name },
                    ),
                    4 => try self.print(
                        "    mov {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ cpu_reg_names_32bit[reg.index], cpu_reg_names_32bit[reg.index], stack_pos, reg.name },
                    ),
                    else => try self.print("    mov [rsp + {d}], {s}\n", .{ stack_pos, reg.name }),
                }
            },
            .INT => |int| {
                // Get register and pop
                const reg = self.popCPUReg();
                // Insert arg based on size
                switch (int.size()) {
                    1 => try self.print(
                        "    movsx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ reg.name, cpu_reg_names_8bit[reg.index], stack_pos, reg.name },
                    ),
                    2 => try self.print(
                        "    movsx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ reg.name, cpu_reg_names_16bit[reg.index], stack_pos, reg.name },
                    ),
                    4 => try self.print(
                        "    movsx {s}, {s}\n    mov [rsp + {d}], {s}\n",
                        .{ reg.name, cpu_reg_names_32bit[reg.index], stack_pos, reg.name },
                    ),
                    else => try self.print("    mov [rsp + {d}], {s}\n", .{ stack_pos, reg.name }),
                }
            },
            .PTR => {
                // Get register and pop
                const reg = self.popCPUReg();
                try self.print("    mov [rsp + {d}], {s}\n", .{ stack_pos, reg.name });
            },
            .FLOAT32 => {
                // Get register and pop
                const reg = self.popSSEReg();
                try self.print(
                    "    xor eax, eax\n    movss rax, {s}\n    mov [rsp + {d}], rax\n",
                    .{ reg.name, stack_pos },
                );
            },
            .FLOAT64 => {
                // Get register and pop
                const reg = self.popSSEReg();
                try self.print("    movsd [rsp + {d}], {s}\n", .{ stack_pos, reg.name });
            },
            else => unreachable,
        }
    }
    // Move first four args into registers
    if (args.len > 3) {
        // Pop two args
        _ = try self.write("    pop rcx\n    pop rdx\n    pop r8\n    pop r9\n");
    } else if (args.len == 3) {
        // Pop three args
        _ = try self.write("    pop rcx\n    pop rdx\n    pop r8\n");
    } else if (args.len == 2) {
        // Pop two args
        _ = try self.write("    pop rcx\n    pop rdx\n");
    } else if (args.len == 1) {
        // Pop one arg to proper register
        _ = try self.write("    pop rcx\n");
    }

    // Attempt to write inline
    const wrote_inline = try self.stm.natives_table.writeNativeInline(
        self,
        native_name,
        nativeExpr.arg_kinds,
    );

    // Check if inline or not
    if (!wrote_inline) {
        // Generate the call
        try self.print("    call {s}\n", .{nativeExpr.name.lexeme});

        // Get pop size
        const pop_size = if (args.len >= 4) (args.len - 4) * 8 else 0;
        // Check if pop size is greater than 0
        if (pop_size > 0) {
            try self.print("    add rsp, {d}\n", .{pop_size});
        }
    } else {
        // Get pop size
        const pop_size = if (args.len >= 4) (args.len - 4) * 8 else 0;
        // Check if pop size is greater than 0
        if (pop_size > 0) {
            try self.print("    add rsp, {d}\n", .{pop_size});
        }
    }
    // Pop registers back
    try self.restoreSSEReg(sse_reg_count);
    try self.restoreCPUReg(cpu_reg_count);
    // Put result into next register
    switch (result_kind) {
        .BOOL, .UINT, .INT, .PTR, .FUNC => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            try self.print("    mov {s}, rax\n", .{reg.name});
        },
        .FLOAT32 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            try self.print("    movq {s}, rax\n", .{reg.name});
        },
        .FLOAT64 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            try self.print("    movq {s}, rax\n", .{reg.name});
        },
        .VOID => undefined,
        else => unreachable,
    }
}

/// Generate a user defined function call
fn visitCallExpr(self: *Generator, callExpr: *Expr.CallExpr, result_kind: KindId) GenerationError!void {
    // Generate the operand
    try self.genExpr(callExpr.caller_expr);
    // Get function from STM
    const function_symbol = self.stm.getSymbol(callExpr.caller_expr.result_kind.FUNC.name) catch unreachable;
    // Get stack_size
    const stack_size = function_symbol.kind.FUNC.stack_offset;

    // Pop function pointer register
    const func_ptr_reg = self.popCPUReg();
    // Push register onto the stack
    const cpu_reg_count = try self.storeCPUReg();
    const sse_reg_count = try self.storeSSEReg();

    // Reserve stack space
    try self.print("    sub rsp, {d}\n", .{stack_size});
    // Move function ptr to top of stack
    try self.print("    push {s}\n", .{func_ptr_reg.name});

    // Store next address on the stack
    var next_address: u64 = 8;
    // Generate each argument
    for (callExpr.args) |arg| {
        // Generate arg
        try self.genExpr(arg);

        // Move onto stack based on size
        switch (arg.result_kind) {
            .BOOL => {
                // Get kind size
                const size = 1;
                // Pop cpu register
                const reg = self.popCPUReg();
                // Get sized register
                const sized_reg = getSizedCPUReg(reg.index, size);
                // Move to stack
                try self.print("    mov [rsp+{d}], {s}\n", .{ next_address, sized_reg });
                // Increment next address
                next_address += size;
            },
            .UINT => |uint| {
                // Get kind size
                const size = uint.size();
                // Check for alignment
                next_address = realignStack(next_address, size);

                // Pop cpu register
                const reg = self.popCPUReg();
                // Get sized register
                const sized_reg = getSizedCPUReg(reg.index, size);
                // Move to stack
                try self.print("    mov [rsp+{d}], {s}\n", .{ next_address, sized_reg });
                // Increment next address
                next_address += size;
            },
            .INT => |int| {
                // Get kind size
                const size = int.size();
                // Check for alignment
                next_address = realignStack(next_address, size);

                // Pop cpu register
                const reg = self.popCPUReg();
                // Get sized register
                const sized_reg = getSizedCPUReg(reg.index, size);
                // Move to stack
                try self.print("    mov [rsp+{d}], {s}\n", .{ next_address, sized_reg });
                // Increment next address
                next_address += size;
            },
            .FLOAT32 => {
                // Get kind size
                const size: u64 = 4;
                // Check for alignment
                next_address = realignStack(next_address, size);

                // Pop cpu register
                const reg = self.popSSEReg();
                // Move to stack
                try self.print("    movd [rsp+{d}], {s}\n", .{ next_address, reg.name });
                // Increment next address
                next_address += size;
            },
            .FLOAT64 => {
                // Get kind size
                const size: u64 = 8;
                // Check for alignment
                next_address = realignStack(next_address, size);

                // Pop cpu register
                const reg = self.popSSEReg();
                // Move to stack
                try self.print("    movq [rsp+{d}], {s}\n", .{ next_address, reg.name });
                // Increment next address
                next_address += size;
            },
            .PTR, .FUNC => {
                // Get kind size
                const size: u64 = 8;
                // Check for alignment
                next_address = realignStack(next_address, size);

                // Pop cpu register
                const reg = self.popCPUReg();
                // Move to stack
                try self.print("    mov [rsp+{d}], {s}\n", .{ next_address, reg.name });
                // Increment next address
                next_address += size;
            },
            else => unreachable,
        }
    }

    // Generate call
    try self.write("    pop rcx\n    call rcx\n");
    // Remove locals from stack
    try self.print("    add rsp, {d}\n", .{stack_size});

    // Restore registers
    try self.restoreSSEReg(sse_reg_count);
    try self.restoreCPUReg(cpu_reg_count);
    // Move result
    switch (result_kind) {
        .BOOL, .UINT, .INT, .PTR, .FUNC => {
            // Get a new register
            const reg = try self.getNextCPUReg();
            try self.print("    mov {s}, rax\n", .{reg.name});
        },
        .FLOAT32 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            try self.print("    movq {s}, rax\n", .{reg.name});
        },
        .FLOAT64 => {
            // Get a new register
            const reg = try self.getNextSSEReg();
            try self.print("    movq {s}, rax\n", .{reg.name});
        },
        .VOID => undefined,
        else => unreachable,
    }
}

/// Generate asm for type conversions
fn visitConvExpr(self: *Generator, convExpr: *Expr.ConversionExpr, result_kind: KindId) GenerationError!void {
    // Generate operand
    try self.genExpr(convExpr.operand);
    // Extrand operand type
    const operand_type = convExpr.operand.result_kind;
    // Generate self
    switch (operand_type) {
        // Converting FROM FLOAT32
        .FLOAT32 => {
            // Get register name
            const src_reg = self.getCurrSSEReg();

            switch (result_kind) {
                // Converting to FLOAT64
                .FLOAT64 => {
                    try self.print("    cvtss2sd {s}, {s} ; F32 to F64\n", .{ src_reg.name, src_reg.name });
                },
                else => unreachable,
            }
        },
        // Converting FROM FLOAT64
        .FLOAT64 => {
            // Get register name
            const src_reg = self.getCurrSSEReg();
            switch (result_kind) {
                // Converting to FLOAT32 from FLOAT64
                .FLOAT32 => {
                    try self.print("    cvtsd2ss {s}, {s} ; F64 to F32\n", .{ src_reg.name, src_reg.name });
                },
                else => unreachable,
            }
        },
        // Non floating point source
        .BOOL, .UINT, .INT => {
            // Get register name
            const src_reg = self.popCPUReg();
            switch (result_kind) {
                // Converting to FLOAT64
                .FLOAT32 => {
                    // Get new F64 register
                    const target_reg = try self.getNextSSEReg();
                    try self.print("    cvtsi2ss {s}, {s} ; Non-floating point to F32\n", .{ target_reg.name, src_reg.name });
                },
                // Converting to FLOAT64
                .FLOAT64 => {
                    // Get new F64 register
                    const target_reg = try self.getNextSSEReg();
                    try self.print("    cvtsi2sd {s}, {s} ; Non-floating point to F64\n", .{ target_reg.name, src_reg.name });
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

/// Generate asm for an indexExpr
fn visitIndexExprID(self: *Generator, indexExpr: *Expr.IndexExpr) GenerationError!void {
    // Generate lhs
    try self.genExpr(indexExpr.lhs);
    // Generate rhs
    try self.genExpr(indexExpr.rhs);

    // Generate index call
    var lhs_reg: Register = undefined;
    var rhs_reg: Register = undefined;
    // Get register names, checking if reversed
    if (indexExpr.reversed) {
        lhs_reg = self.popCPUReg();
        rhs_reg = self.popCPUReg();
    } else {
        rhs_reg = self.popCPUReg();
        lhs_reg = self.popCPUReg();
    }

    // Check if array
    if (indexExpr.lhs.result_kind == .ARRAY) {
        // Write array offset * child size
        const child_size = indexExpr.lhs.result_kind.ARRAY.child.size_runtime();
        try self.print("    lea {s}, [{s}+{s}*{d}] ; Array Index\n", .{ lhs_reg.name, lhs_reg.name, rhs_reg.name, child_size });
    } else {
        // LEA the address
        try self.print("    lea {s}, [{s}+{s}] ; Ptr Index\n", .{ lhs_reg.name, lhs_reg.name, rhs_reg.name });
    }

    // Push lhs_reg back onto stack
    self.pushCPUReg(lhs_reg);
}

/// Generate asm for an indexExpr
fn visitIndexExpr(self: *Generator, indexExpr: *Expr.IndexExpr, result_kind: KindId) GenerationError!void {
    // Generate lhs
    try self.genExpr(indexExpr.lhs);
    // Generate rhs
    try self.genExpr(indexExpr.rhs);

    // Generate index call
    var lhs_reg: Register = undefined;
    var rhs_reg: Register = undefined;
    // Get register names, checking if reversed
    if (indexExpr.reversed) {
        lhs_reg = self.popCPUReg();
        rhs_reg = self.popCPUReg();
    } else {
        rhs_reg = self.popCPUReg();
        lhs_reg = self.popCPUReg();
    }

    // Check if array
    if (indexExpr.lhs.result_kind == .ARRAY) {
        // Write array offset * child size
        const child_size = indexExpr.lhs.result_kind.ARRAY.child.size_runtime();
        // Check if float 32
        if (result_kind == .FLOAT32) {
            // Get floating register
            const result_reg = try self.getNextSSEReg();
            // Write index access
            try self.print(
                "    movss {s}, [{s}+{s}*{d}]\n ; Array Index",
                .{ result_reg.name, lhs_reg.name, rhs_reg.name, child_size },
            );
        } else if (result_kind == .FLOAT64) {
            // Get floating register
            const result_reg = try self.getNextSSEReg();
            // Write index access
            try self.print(
                "    movsd {s}, [{s}+{s}*{d}] ; Array Index\n",
                .{ result_reg.name, lhs_reg.name, rhs_reg.name, child_size },
            );
        } else {
            // Get the size of the result
            const size = result_kind.size_runtime();
            const size_keyword = getSizeKeyword(size);
            // Push lhs_reg back on the stack
            const result_reg = try self.getNextCPUReg();

            // If size is 8 normal, else special size keyword
            if (size == 8) {
                // Write index access
                try self.print(
                    "    mov {s}, [{s}+{s}*{d}] ; Array Index\n",
                    .{ result_reg.name, lhs_reg.name, rhs_reg.name, child_size },
                );
            } else {
                // Get operation kind
                const op_char: u8 = if (result_kind == .UINT) 'z' else 's';
                // Write index access
                try self.print(
                    "    mov{c}x {s}, {s} [{s}+{s}*{d}] ; Array Index\n",
                    .{ op_char, result_reg.name, size_keyword, lhs_reg.name, rhs_reg.name, child_size },
                );
            }
        }
    } else {
        // Check if float 32
        if (result_kind == .FLOAT32) {
            // Get floating register
            const result_reg = try self.getNextSSEReg();
            // Write index access
            try self.print("    movss {s}, [{s}+{s}] ; Ptr Index\n", .{ result_reg.name, lhs_reg.name, rhs_reg.name });
        } else if (result_kind == .FLOAT64) {
            // Get floating register
            const result_reg = try self.getNextSSEReg();
            // Write index access
            try self.print("    movsd {s}, [{s}+{s}] ; Ptr Index\n", .{ result_reg.name, lhs_reg.name, rhs_reg.name });
        } else {
            // Get the size of the result
            const size = result_kind.size_runtime();
            const size_keyword = getSizeKeyword(size);
            // Push lhs_reg back on the stack
            const result_reg = try self.getNextCPUReg();

            // If size is 8 normal, else special size keyword
            if (size == 8) {
                // Write index access
                try self.print("    mov {s}, [{s}+{s}] ; Ptr Index\n", .{ result_reg.name, lhs_reg.name, rhs_reg.name });
            } else {
                // Get operation kind
                const op_char: u8 = if (result_kind == .UINT) 'z' else 's';
                // Write index access
                try self.print("    mov{c}x {s}, {s} [{s}+{s}] ; Ptr Index\n", .{ op_char, result_reg.name, size_keyword, lhs_reg.name, rhs_reg.name });
            }
        }
    }
}

/// Generate asm for a UnaryExpr
fn visitUnaryExpr(self: *Generator, unaryExpr: *Expr.UnaryExpr) GenerationError!void {
    // Generate operand
    try self.genExpr(unaryExpr.operand);
    // Extract result_kind
    const result_kind = unaryExpr.operand.result_kind;

    // Generate self
    // Check if float or not
    switch (result_kind) {
        .FLOAT32 => {
            // Get register name
            const reg = self.getCurrSSEReg();
            switch (unaryExpr.op.kind) {
                TokenKind.MINUS => {
                    try self.print("    xorps {s}, oword [@SS_SIGN_BIT] ; F32 Negate\n", .{reg.name});
                },
                else => unreachable,
            }
        },
        .FLOAT64 => {
            // Get register name
            const reg = self.getCurrSSEReg();
            switch (unaryExpr.op.kind) {
                TokenKind.MINUS => {
                    try self.print("    xorps {s}, oword [@SD_SIGN_BIT] ; F64 Negate\n", .{reg.name});
                },
                else => unreachable,
            }
        },
        else => {
            // Get register name
            const reg = self.getCurrCPUReg();
            switch (unaryExpr.op.kind) {
                TokenKind.EXCLAMATION => try self.print("    xor {s}, 1 ; Bool not\n", .{reg.name}),
                TokenKind.MINUS => try self.print("    neg {s} ; (U)INT negate\n", .{reg.name}),
                else => unreachable,
            }
        },
    }
}

/// Generate asm for an ArithExpr
fn visitArithExpr(self: *Generator, arithExpr: *Expr.ArithExpr) GenerationError!void {
    // Generate lhs
    try self.genExpr(arithExpr.lhs);
    // Generate rhs
    try self.genExpr(arithExpr.rhs);
    // Extract result kind
    const result_kind = arithExpr.lhs.result_kind;

    // Gen self
    // Check kind
    switch (result_kind) {
        .FLOAT32, .FLOAT64 => {
            var lhs_reg: Register = undefined;
            var rhs_reg: Register = undefined;
            // Get register names, checking if reversed
            if (arithExpr.reversed) {
                lhs_reg = self.popSSEReg();
                rhs_reg = self.popSSEReg();
            } else {
                rhs_reg = self.popSSEReg();
                lhs_reg = self.popSSEReg();
            }
            // Get op char
            const op_char: u8 = if (result_kind == .FLOAT32) 's' else 'd';

            switch (arithExpr.op.kind) {
                TokenKind.PLUS => try self.print("    adds{c} {s}, {s} ; Float Add\n", .{ op_char, lhs_reg.name, rhs_reg.name }),
                TokenKind.MINUS => try self.print("    subs{c} {s}, {s} ; Float Sub\n", .{ op_char, lhs_reg.name, rhs_reg.name }),
                TokenKind.STAR => try self.print("    muls{c} {s}, {s} ; Float Mul\n", .{ op_char, lhs_reg.name, rhs_reg.name }),
                TokenKind.SLASH => try self.print("    divs{c} {s}, {s} ; Float Div\n", .{ op_char, lhs_reg.name, rhs_reg.name }),
                else => unreachable,
            }
            // Push lhs back
            self.pushSSEReg(lhs_reg);
        },
        else => {
            var lhs_reg: Register = undefined;
            var rhs_reg: Register = undefined;
            // Get register names, checking if reversed
            if (arithExpr.reversed) {
                lhs_reg = self.popCPUReg();
                rhs_reg = self.popCPUReg();
            } else {
                rhs_reg = self.popCPUReg();
                lhs_reg = self.popCPUReg();
            }

            switch (arithExpr.op.kind) {
                TokenKind.PLUS => try self.print("    add {s}, {s} ; (U)INT Add\n", .{ lhs_reg.name, rhs_reg.name }),
                TokenKind.MINUS => try self.print("    sub {s}, {s} ; (U)INT  Sub\n", .{ lhs_reg.name, rhs_reg.name }),
                TokenKind.STAR => try self.print("    imul {s}, {s} ; (U)INT Mul\n", .{ lhs_reg.name, rhs_reg.name }),
                TokenKind.SLASH => try self.print(
                    \\    mov rax, {s} ; (U)INT Div
                    \\    xor edx, edx
                    \\    idiv {s}
                    \\    mov {s}, rax
                    \\
                , .{ lhs_reg.name, rhs_reg.name, lhs_reg.name }),
                TokenKind.PERCENT => try self.print(
                    \\    mov rax, {s} ; (U)INT Mod
                    \\    xor edx, edx
                    \\    idiv {s}
                    \\    mov {s}, rdx
                    \\
                , .{ lhs_reg.name, rhs_reg.name, lhs_reg.name }),
                else => unreachable,
            }
            // Push lhs register back on the stack
            self.pushCPUReg(lhs_reg);
        },
    }
}

/// Generate asm for a compare expr
fn visitCompareExpr(self: *Generator, compareExpr: *Expr.CompareExpr) GenerationError!void {
    // Generate lhs
    try self.genExpr(compareExpr.lhs);
    // Generate rhs
    try self.genExpr(compareExpr.rhs);

    const result_kind = compareExpr.lhs.result_kind;

    // Generate compare
    switch (result_kind) {
        // Float operands
        .FLOAT32, .FLOAT64 => {
            var lhs_reg: Register = undefined;
            var rhs_reg: Register = undefined;
            // Get register names, checking if reversed
            if (compareExpr.reversed) {
                lhs_reg = self.popSSEReg();
                rhs_reg = self.popSSEReg();
            } else {
                rhs_reg = self.popSSEReg();
                lhs_reg = self.popSSEReg();
            }

            // Get op char for data size
            const op_char: u8 = if (result_kind == .FLOAT32) 's' else 'd';
            // Print common op for float compare
            try self.print("    comis{c} {s}, {s} ; Float ", .{ op_char, lhs_reg.name, rhs_reg.name });

            switch (compareExpr.op.kind) {
                .GREATER => try self.write(">\n    seta al\n"),
                .GREATER_EQUAL => try self.write(">=\n    setnb al\n"),
                .LESS => try self.write("<\n    setb al\n"),
                .LESS_EQUAL => try self.write("<=\n    setna al\n"),
                .EQUAL_EQUAL => try self.write("==\n    sete al\n"),
                .EXCLAMATION_EQUAL => try self.write("!=\n    setne al\n"),
                else => unreachable,
            }
            // Get new result register
            const result_reg = try self.getNextCPUReg();
            // Print ending common op for float compare
            try self.print("    movzx {s}, al\n", .{result_reg.name});
        },
        // Unsigned
        .UINT => {
            var lhs_reg: Register = undefined;
            var rhs_reg: Register = undefined;
            // Get register names, checking if reversed
            if (compareExpr.reversed) {
                lhs_reg = self.popCPUReg();
                rhs_reg = self.popCPUReg();
            } else {
                rhs_reg = self.popCPUReg();
                lhs_reg = self.popCPUReg();
            }

            // Print common asm for all compares
            try self.print("    cmp {s}, {s} ; UINT ", .{ lhs_reg.name, rhs_reg.name });
            switch (compareExpr.op.kind) {
                .GREATER => try self.write(">\n    seta al\n"),
                .GREATER_EQUAL => try self.write(">=\n    setae al\n"),
                .LESS => try self.write("<\n    setb al\n"),
                .LESS_EQUAL => try self.write("<=\n    setbe al\n"),
                .EQUAL_EQUAL => try self.write("==\n    sete al\n"),
                .EXCLAMATION_EQUAL => try self.write("!=\n    setne al\n"),
                else => unreachable,
            }
            // Print common asm for all compares
            try self.print("    movzx {s}, al\n", .{lhs_reg.name});
            // Push lhs back on the stack
            self.pushCPUReg(lhs_reg);
        },
        // Integer operands
        else => {
            var lhs_reg: Register = undefined;
            var rhs_reg: Register = undefined;
            // Get register names, checking if reversed
            if (compareExpr.reversed) {
                lhs_reg = self.popCPUReg();
                rhs_reg = self.popCPUReg();
            } else {
                rhs_reg = self.popCPUReg();
                lhs_reg = self.popCPUReg();
            }

            // Print common asm for all compares
            try self.print("    cmp {s}, {s} ; INT ", .{ lhs_reg.name, rhs_reg.name });
            switch (compareExpr.op.kind) {
                .GREATER => try self.write(">\n    setg al\n"),
                .GREATER_EQUAL => try self.write(">=\n    setge al\n"),
                .LESS => try self.write("<\n    setl al\n"),
                .LESS_EQUAL => try self.write("<=\n    setle al\n"),
                .EQUAL_EQUAL => try self.write("==\n    sete al\n"),
                .EXCLAMATION_EQUAL => try self.write("!=\n    setne al\n"),
                else => unreachable,
            }
            // Print common asm for all compares
            try self.print("    movzx {s}, al\n", .{lhs_reg.name});
            // Push lhs register back on the stack
            self.pushCPUReg(lhs_reg);
        },
    }
}

/// Generator asm for a logical and expression
fn visitAndExpr(self: *Generator, andExpr: *Expr.AndExpr) GenerationError!void {
    // Left side
    try self.genExpr(andExpr.lhs);
    // Pop lhs of the or
    const lhs_reg = self.popCPUReg();

    // Get label counts
    const label_c = self.label_count;
    // Increment label
    self.label_count += 1;
    // Generate check for lhs
    try self.print(
        \\    test {s}, {s} ; Logical AND
        \\    jz .L{d}
        \\
    , .{ lhs_reg.name, lhs_reg.name, label_c });

    // Right side
    try self.genExpr(andExpr.rhs);
    // Write end of or jump label
    try self.print(".L{d}:\n", .{label_c});
}

/// Generator asm for a logical or expression
fn visitOrExpr(self: *Generator, orExpr: *Expr.OrExpr) GenerationError!void {
    // Left side
    try self.genExpr(orExpr.lhs);
    // Pop lhs of the or
    const lhs_reg = self.popCPUReg();

    // Get label counts
    const label_c = self.label_count;
    // Increment label
    self.label_count += 1;
    // Generate check for lhs
    try self.print(
        \\    test {s}, {s} ; Logical OR
        \\    jnz .L{d}
        \\
    , .{ lhs_reg.name, lhs_reg.name, label_c });

    // Right side
    try self.genExpr(orExpr.rhs);
    // Write end of or jump label
    try self.print(".L{d}:\n", .{label_c});
}

/// Generate asm for an if expression
fn visitIfExpr(self: *Generator, ifExpr: *Expr.IfExpr, result_kind: KindId) GenerationError!void {
    // Evaluate the conditional
    try self.genExpr(ifExpr.conditional);

    // Get current cpu register for conditional value
    const conditional_reg = self.popCPUReg();
    // Get first label
    const label_c = self.label_count;
    // Increment it
    self.label_count += 1;
    // Write asm for jump
    try self.print(
        \\    test {s}, {s} ; If Expr
        \\    jz .L{d}
        \\
    , .{ conditional_reg.name, conditional_reg.name, label_c });

    // Generate the then branch
    try self.genExpr(ifExpr.then_branch);
    // Pop then branch register
    if (result_kind == .FLOAT32 or result_kind == .FLOAT64) {
        _ = self.popSSEReg();
    } else {
        _ = self.popCPUReg();
    }

    // Get second label
    const label_c2 = self.label_count;
    // Increment it
    self.label_count += 1;

    // Write asm for then branch jump to end and else jump label
    try self.print(
        \\    jmp .L{d}
        \\.L{d}:
        \\
    , .{ label_c2, label_c });

    // Generate the else branch
    try self.genExpr(ifExpr.else_branch);
    // Write the asm for jump to end label
    try self.print(".L{d}: ; End of If Expr\n", .{label_c2});
}
