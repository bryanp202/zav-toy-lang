const std = @import("std");

// Error import
const Error = @import("error.zig");
const ScopeError = Error.ScopeError;
// Natives Table
const NativesTable = @import("natives.zig");

// *********************** //
//*** STM type Classes  ***//
// *********************** //

/// Used to store the scoping and naming information of a source program
pub const SymbolTableManager = struct {
    allocator: std.mem.Allocator,
    // Symbol Resolution
    scopes: std.ArrayList(*Scope),
    next_scope: u16,
    active_scope: *Scope,
    /// Constant Resolution
    constants: std.AutoHashMap([48]u8, ConstantData),
    /// Stores memory offset for next global
    next_address: u64,
    /// Stores the count of constants, used for name generation
    constant_count: u64,
    /// Used to resolve native functions
    natives_table: NativesTable,

    /// Init a STM
    pub fn init(allocator: std.mem.Allocator) SymbolTableManager {
        // Make global scope
        const global = allocator.create(Scope) catch unreachable;
        global.* = Scope.init(allocator, null);

        // Make scopes stack
        var scopes = std.ArrayList(*Scope).init(allocator);
        scopes.append(global) catch unreachable;

        // Make constants map
        const const_map = std.AutoHashMap([48]u8, ConstantData).init(allocator);

        // Make a natives table
        const natives_table = NativesTable.init(allocator);

        // Return a new STM
        return SymbolTableManager{
            .allocator = allocator,
            .scopes = scopes,
            .next_scope = 1,
            .active_scope = global,
            .next_address = 0,
            .constants = const_map,
            .constant_count = 0,
            .natives_table = natives_table,
        };
    }
    /// Deinit a STM
    pub fn deinit(self: *SymbolTableManager) void {
        // Deinitialize all scopes
        for (self.scopes.items) |scope| {
            scope.deinit();
            self.allocator.destroy(scope);
        }
        // Deinit scopes stack
        self.scopes.deinit();

        // Deinit constants in constants map
        var const_iter = self.constants.iterator();
        while (const_iter.next()) |constant| {
            // Deinit constant
            constant.value_ptr.deinit(self.allocator);
        }
        self.constants.deinit();
        // Deinit natives
        self.natives_table.deinit(self.allocator);
    }

    /// Reset the active scope stack and scope counter
    pub fn resetStack(self: *SymbolTableManager) void {
        // Set bottom scope to active_scope
        self.active_scope = self.scopes.items[0];
        // Reset counter
        self.next_scope = 1;
    }

    /// Create a new scope, add it to scopes stack,
    /// and then push it to the top of the active scopes stack
    pub fn addScope(self: *SymbolTableManager) void {
        // Make new scope
        const new_scope = self.allocator.create(Scope) catch unreachable;
        new_scope.* = Scope.init(self.allocator, self.active_scope);
        // Set to active scope
        self.active_scope = new_scope;
        // Add to scopes stack
        self.scopes.append(new_scope) catch unreachable;

        // Increment current scope counter
        self.next_scope += 1;
    }

    /// Push the next scope onto the active scope stack
    pub fn pushScope(self: *SymbolTableManager) void {
        // Put next scope as active scope
        self.active_scope = self.scopes.items[self.current];

        // Increment counter
        self.next_scope += 1;
    }

    /// Pop the current active scope from the active scope stack
    pub fn popScope(self: *SymbolTableManager) void {
        // Pop scope
        self.active_scope = self.active_scope.enclosing.?;
    }

    /// Add a new symbol, with all of its attributes, and assign it with a null memory location
    pub fn declareSymbol(
        self: *SymbolTableManager,
        name: []const u8,
        kind: KindId,
        scope: ScopeKind,
        dcl_line: u64,
        is_mutable: bool,
    ) !void {
        // Calculate the size of the kind
        const size = kind.size();

        // Else let the local scope calculate the local scope
        try self.active_scope.declareSymbol(name, kind, scope, dcl_line, is_mutable, size);
    }

    /// Add a new symbol to the top scope on the stack, assign it a memory location
    /// if it has not been assigned one. Global scope variables will use a static memory location
    /// and Local scope variables use a relative stack location
    pub fn getSymbol(self: *SymbolTableManager, name: []const u8) !*Symbol {
        // Get symbol, starting at active_scope
        return self.active_scope.getSymbol(name, &self.next_address);
    }

    /// Try to put a new Value in the constants table marked as not used,
    /// but if there is a pre-existing constant mark it as used
    pub fn addConstant(self: *SymbolTableManager, constant: Value) void {
        // Convert to a string
        const val_as_str = ValueAndStr{ .value = constant };

        // Attempt to add the value into the constant table
        const getOrPut = self.constants.getOrPut(val_as_str.str) catch unreachable;
        // Check if not found
        if (!getOrPut.found_existing) {
            // Pre-calculate the size of this value
            const size = switch (constant.kind) {
                .UINT => constant.as.uint.size(),
                .INT => constant.as.int.size(),
                .FLOAT => constant.as.float.size(),
                .STRING => constant.as.string.data.len,
                .BOOL => @sizeOf(bool),
                .ARRAY => constant.as.array.size(),
            };
            // Add the constant marked as unused
            getOrPut.value_ptr.* = ConstantData.init(constant, size);
        }
    }

    /// Get the name of a constant, assigning it one if it is not already named
    pub fn getConstantId(self: *SymbolTableManager, constant: Value) []const u8 {
        const val_as_str = ValueAndStr{ .value = constant };
        // Get the constant, returning null if it was not found
        const constPtr = self.constants.getPtr(val_as_str.str).?;

        // Check if constant has been assigned a number
        if (constPtr.name == null) {
            // Alloc new name string
            const new_name = std.fmt.allocPrint(self.allocator, "C{d}", .{self.constant_count}) catch unreachable;
            // Mark constant with new name
            constPtr.name = new_name;
            // Increment constant_count
            self.constant_count += 1;
        }
        // Return the const id
        return constPtr.name.?;
    }

    const ValueAndStr = extern union { value: Value, str: [48]u8 };

    // Helper Methods //
};

// *********************** //
//** Scope type Classes ***//
// *********************** //

/// Used to store a lexical scope, such as a function or global scope
pub const Scope = struct {
    enclosing: ?*Scope,
    symbols: std.StringHashMap(Symbol),
    next_address: u64,

    /// Initialize a Scope
    pub fn init(allocator: std.mem.Allocator, enclosing: ?*Scope) Scope {
        const table = std.StringHashMap(Symbol).init(allocator);
        return Scope{
            .enclosing = enclosing,
            .symbols = table,
            .next_address = 0,
        };
    }
    /// Deinitialize a scope
    pub fn deinit(self: *Scope) void {
        // Free KindId for all values in the table
        var symbol_iter = self.symbols.valueIterator();
        while (symbol_iter.next()) |symbol| {
            // Deinit KindId
            symbol.kind.deinit(self.symbols.allocator);
        }
        // Deinit the table
        self.symbols.deinit();
    }

    /// Add a new symbol, providing all of its attributes and a null address
    pub fn declareSymbol(
        self: *Scope,
        name: []const u8,
        kind: KindId,
        scope: ScopeKind,
        dcl_line: u64,
        is_mutable: bool,
        size: u64,
    ) ScopeError!void {
        // Check if in table
        const getOrPut = self.symbols.getOrPut(name) catch unreachable;
        // Check if it is already in table
        if (getOrPut.found_existing) {
            // Free the KindId
            kind.deinit(self.symbols.allocator);
            // Throw error
            return ScopeError.DuplicateDeclaration;
        }

        // Add symbol to the table
        const new_symbol = Symbol.init(name, kind, scope, dcl_line, is_mutable, size);
        getOrPut.value_ptr.* = new_symbol;
    }

    /// Try to get a symbol based off of a name
    pub fn getSymbol(self: *Scope, name: []const u8, global_next_address: *u64) ScopeError!*Symbol {
        // Check this and all enclosing scopes for a declared symbol as name
        var curr: ?*Scope = self;
        while (curr) |enclosing| : (curr = enclosing.enclosing) {
            const maybeSymbol = enclosing.symbols.getPtr(name);
            // Check if found symbol
            if (maybeSymbol) |sym| {
                // Check if it has an address
                if (sym.mem_loc != null) {
                    return sym;
                } else {
                    // Calculate relative memory location if symbol is local
                    var location: u64 = undefined;
                    if (sym.scope == ScopeKind.LOCAL) {
                        location = self.next_address;
                        // Increment next address
                        self.next_address += sym.size;
                    } else {
                        // Use global address and increment it
                        location = global_next_address.*;
                        global_next_address.* += sym.size;
                    }

                    // Assign it a new one
                    sym.mem_loc = location;
                    return sym;
                }
            }
        }
        return ScopeError.UndeclaredSymbol;
    }
};

// *********************** //
//***   Symbol Struct   ***//
// *********************** //

/// Used to store information about a variable/symbol
pub const Symbol = struct {
    name: []const u8,
    kind: KindId,
    scope: ScopeKind,
    dcl_line: u64,
    is_mutable: bool,
    has_mutated: bool,
    mem_loc: ?u64,
    size: u64,

    /// Make a new symbol
    pub fn init(name: []const u8, kind: KindId, scope: ScopeKind, dcl_line: u64, is_mutable: bool, size: u64) Symbol {
        return Symbol{
            .name = name,
            .kind = kind,
            .scope = scope,
            .dcl_line = dcl_line,
            .is_mutable = is_mutable,
            .has_mutated = false,
            .mem_loc = null,
            .size = size,
        };
    }
};

// *********************** //
//***  Data type Stuff  ***//
// *********************** //

// Enum for the types available in Zav
pub const Kinds = enum {
    VOID,
    BOOL,
    UINT,
    INT,
    FLOAT,
    PTR,
    ARRAY,
    FUNC,
};

/// Used to mark what type a variable is
pub const KindId = union(Kinds) {
    VOID: void,
    BOOL: void,
    UINT: UInteger,
    INT: Integer,
    FLOAT: Float,
    PTR: Pointer,
    ARRAY: Array,
    FUNC: Function,

    /// Deinit a KindId
    pub fn deinit(self: KindId, allocator: std.mem.Allocator) void {
        // Check if type needs to be destroyed
        switch (self) {
            // If non allocated types, do nothing
            .VOID, .BOOL, .UINT, .INT, .FLOAT => return,
            // If a pointer delete all children
            .PTR => |ptr| {
                // Walk the linked list of children until a terminal node is found
                var curr = ptr.child;
                var next: *KindId = undefined;
                while (true) {
                    switch (curr.*) {
                        .PTR => |pointer| {
                            next = pointer.child;
                            allocator.destroy(curr);
                            curr = next;
                        },
                        .ARRAY => |array| {
                            next = array.child;
                            allocator.destroy(curr);
                            curr = next;
                        },
                        else => {
                            allocator.destroy(curr);
                            break;
                        },
                    }
                }
            },
            // If an array, delete all children
            .ARRAY => |arr| {
                // Walk the linked list of children until a terminal node is found
                var curr = arr.child;
                var next: *KindId = undefined;
                while (true) {
                    switch (curr.*) {
                        .PTR => |pointer| {
                            next = pointer.child;
                            allocator.destroy(curr);
                            curr = next;
                        },
                        .ARRAY => |array| {
                            next = array.child;
                            allocator.destroy(curr);
                            curr = next;
                        },
                        else => {
                            allocator.destroy(curr);
                            break;
                        },
                    }
                }
            },
            // If function, delete all arg types and return type
            .FUNC => |func| {
                // Check if any args
                if (func.arg_kinds) |args| {
                    // Deinit args
                    for (args) |arg| {
                        arg.deinit(allocator);
                    }
                    // Deinit args array
                    allocator.free(args);
                }

                // Deinit return
                func.ret_kind.deinit(allocator);
                allocator.destroy(func.ret_kind);
            },
        }
    }

    /// Init a new void
    pub fn newVoid() KindId {
        return KindId.VOID;
    }
    /// Init a new boolean
    pub fn newBool() KindId {
        return KindId.BOOL;
    }
    /// Init a new unsigned integer
    pub fn newUInt(bits: u16) KindId {
        const uint = UInteger{
            .bits = bits,
        };
        return KindId{
            .UINT = uint,
        };
    }
    /// Init a new integer
    pub fn newInt(bits: u16) KindId {
        const int = Integer{
            .bits = bits,
        };
        return KindId{
            .INT = int,
        };
    }
    /// Init a new float
    pub fn newFloat(bits: u16) KindId {
        const float = Float{
            .bits = bits,
        };
        return KindId{
            .FLOAT = float,
        };
    }
    /// Init a new pointer
    pub fn newPtr(allocator: std.mem.Allocator, child_kind: KindId, levels: u16) KindId {
        // Dynamically allocate the child KindId tag
        const child_ptr = allocator.create(KindId) catch unreachable;
        child_ptr.* = child_kind;
        // Make new pointer
        const ptr = Pointer{
            .child = child_ptr,
            .levels = levels,
        };
        return KindId{
            .PTR = ptr,
        };
    }
    /// Init a new array kindid
    pub fn newArr(allocator: std.mem.Allocator, child_kind: KindId, length: u64) KindId {
        // Dynamically allocate the child KindId tag
        const child_ptr = allocator.create(KindId) catch unreachable;
        child_ptr.* = child_kind;
        // Make new array
        const arr = Array{
            .child = child_ptr,
            .length = length,
        };
        return KindId{
            .ARRAY = arr,
        };
    }
    /// Init a new Function kindid
    pub fn newFunc(allocator: std.mem.Allocator, arg_kinds: ?[]KindId, ret_kind: KindId) KindId {
        // Dynamically allocate the child KindId tag
        const ret_ptr = allocator.create(KindId) catch unreachable;
        ret_ptr.* = ret_kind;
        // Make new array
        const func = Function{
            .arg_kinds = arg_kinds,
            .ret_kind = ret_ptr,
        };
        return KindId{
            .FUNC = func,
        };
    }

    /// Return if this kindid is the same as another
    pub fn equal(self: KindId, other: KindId) bool {
        return switch (self) {
            .VOID => return other == .VOID,
            .BOOL => return other == .BOOL,
            .UINT => return other == .UINT and self.UINT.bits == other.UINT.bits,
            .INT => return other == .INT and self.INT.bits == other.INT.bits,
            .FLOAT => return other == .FLOAT and self.FLOAT.bits == other.FLOAT.bits,
            .PTR => |ptr| return other == .PTR and ptr.equal(other.PTR),
            .ARRAY => |arr| return other == .ARRAY and arr.equal(other.ARRAY),
            .FUNC => |func| return other == .FUNC and func.equal(other.FUNC),
        };
    }

    /// Return the size of the Kind
    pub fn size(self: KindId) u64 {
        return switch (self) {
            .VOID => 0,
            .BOOL => 1,
            .UINT => |uint| uint.size(),
            .INT => |int| int.size(),
            .FLOAT => |float| float.size(),
            .PTR => 8,
            .ARRAY => |arr| arr.size(),
            .FUNC => 8,
        };
    }
};

/// Used to mark what kind of scope a variable has
pub const ScopeKind = enum {
    LOCAL,
    GLOBAL,
};

// *********************** //
//*** Data type Classes ***//
// *********************** //

/// Integer type data
const UInteger = struct {
    bits: u16,

    /// Calculate the size of this type in bytes
    pub fn size(self: UInteger) u64 {
        const bytes = std.math.divCeil(u64, self.bits, 8) catch unreachable;
        return bytes;
    }
};

/// Integer type data
const Integer = struct {
    bits: u16,

    /// Calculate the size of this type in bytes
    pub fn size(self: Integer) u64 {
        const bytes = std.math.divCeil(u64, self.bits, 8) catch unreachable;
        return bytes;
    }
};

/// Float Type data
const Float = struct {
    bits: u16,

    /// Calculate the size of this type in bytes
    pub fn size(self: Float) u64 {
        const bytes = std.math.divCeil(u64, self.bits, 8) catch unreachable;
        return bytes;
    }
};

/// Pointer Type data
const Pointer = struct {
    child: *KindId,
    levels: u16,

    /// Returns true if this pointer is the same as another pointer
    pub fn equal(self: Pointer, other: Pointer) bool {
        return self.child.equal(other.child.*) and self.levels == other.levels;
    }
};

/// Array Type data
const Array = struct {
    child: *KindId,
    length: u64,

    /// Returns true if this array is the same as another array
    pub fn equal(self: Array, other: Array) bool {
        return self.child.equal(other.child.*) and self.length == other.length;
    }

    /// Calculate the size of this type in bytes
    pub fn size(self: Array) u64 {
        const element_size = self.child.size();
        const bytes = element_size * self.length;
        return bytes;
    }
};

/// Function Type data
const Function = struct {
    arg_kinds: ?[]KindId,
    ret_kind: *KindId,

    /// Returns true if this func is the same as another func
    pub fn equal(self: Function, other: Function) bool {
        // Check if any args
        if (self.arg_kinds == null) {
            if (other.arg_kinds == null) {
                return true;
            } else {
                return false;
            }
        }
        // Check arg count
        if (self.arg_kinds.?.len != other.arg_kinds.?.len) {
            return false;
        }
        // Check arg types
        for (self.arg_kinds.?, other.arg_kinds.?) |self_arg, other_arg| {
            if (!self_arg.equal(other_arg)) {
                return false;
            }
        }

        // Check return types
        if (!self.ret_kind.equal(other.ret_kind.*)) {
            return false;
        }
        // Everything matches
        return true;
    }
};

// *********************** //
//***Values/Const Structs**//
// *********************** //

/// Used to store the constant and if it was used
const ConstantData = struct {
    data: Value,
    size: u64,
    name: ?[]const u8,

    pub fn init(value: Value, size: u64) ConstantData {
        return ConstantData{
            .data = value,
            .size = size,
            .name = null,
        };
    }

    pub fn deinit(self: *ConstantData, allocator: std.mem.Allocator) void {
        // Free name if it has been allocated
        if (self.name) |name_slice| allocator.free(name_slice);
        // Free Value struct
        self.data.deinit(allocator);
    }
};

/// Used to determine the type of a literal value
pub const ValueKind = enum(u8) {
    BOOL,
    UINT,
    INT,
    FLOAT,
    STRING,
    ARRAY,
};

/// Slice simulation
pub fn LiteralSlice(T: type) type {
    return extern struct {
        ptr: [*]const T,
        len: usize,

        /// Init a LiteralSlice from a zig slice
        pub fn init(zig_slice: []const T) @This() {
            return .{
                .ptr = zig_slice.ptr,
                .len = zig_slice.len,
            };
        }

        /// Return a zig slice version of this LiteralSlice
        pub fn slice(self: @This()) []const T {
            var zig_slice: []const T = undefined;
            zig_slice.len = self.len;
            zig_slice.ptr = self.ptr;
            return zig_slice;
        }
    };
}

/// Unsigned Integer literal storage struct
const UIntegerLiteral = extern struct {
    data: u64,
    bits: u16,

    /// Calculate the size of an integer literal
    pub fn size(self: UIntegerLiteral) usize {
        return std.math.divCeil(usize, self.bits, 8) catch unreachable;
    }
};

/// Integer literal storage struct
const IntegerLiteral = extern struct {
    data: i64,
    bits: u16,

    /// Calculate the size of an integer literal
    pub fn size(self: IntegerLiteral) usize {
        return std.math.divCeil(usize, self.bits, 8) catch unreachable;
    }
};

/// Floating point literal storage struct
const FloatLiteral = extern struct {
    data: f64,
    bits: u16,

    // Calculate the size of a flaot literal
    pub fn size(self: FloatLiteral) usize {
        return std.math.divCeil(usize, self.bits, 8) catch unreachable;
    }
};

/// String literal storage struct
const StringLiteral = extern struct {
    data: LiteralSlice(u8),
};

/// Array Literal storage struct
const ArrayLiteral = extern struct {
    kind: *KindId,
    dimensions: LiteralSlice(usize),
    data: LiteralSlice(Value),

    pub fn size(self: ArrayLiteral) usize {
        // Calculate size of LiteralKind
        var self_size: usize = switch (self.kind.*) {
            .UINT => self.data.ptr[0].as.uint.size(),
            .INT => self.data.ptr[0].as.int.size(),
            .FLOAT => self.data.ptr[0].as.float.size(),
            .BOOL => @sizeOf(bool),
            else => unreachable,
        };
        // Multiply by dimensions
        for (self.dimensions.slice()) |dim| {
            self_size *= dim;
        }
        // Multiply and return
        return self_size;
    }
};

/// Used to store a literal value
pub const Value = extern struct {
    kind: ValueKind,
    as: extern union {
        EMPTY: [6]u64,
        boolean: bool,
        uint: UIntegerLiteral,
        int: IntegerLiteral,
        float: FloatLiteral,
        string: StringLiteral,
        array: ArrayLiteral,
    },

    /// Deinit a Value struct instance
    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        if (self.kind == ValueKind.ARRAY) {
            allocator.free(self.as.array.data.slice());
            allocator.free(self.as.array.dimensions.slice());
            self.as.array.kind.deinit(allocator);
        }
    }

    ///Init a new unsigned integer value
    pub fn newUInt(value: u64, bits: u16) Value {
        var val = Value{ .kind = ValueKind.UINT, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        val.as.uint.bits = bits;
        val.as.uint.data = value;
        return val;
    }
    /// Init a new value as an integer
    pub fn newInt(value: i64, bits: u16) Value {
        var val = Value{ .kind = ValueKind.INT, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        val.as.int.bits = bits;
        val.as.int.data = value;
        return val;
    }
    /// Init a new value as a boolean
    pub fn newBool(value: bool) Value {
        var val = Value{ .kind = ValueKind.BOOL, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        val.as.boolean = value;
        return val;
    }
    /// Init a new value as a float
    pub fn newFloat(value: f64, bits: u16) Value {
        var val = Value{ .kind = ValueKind.FLOAT, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        val.as.float.bits = bits;
        val.as.float.data = value;
        return val;
    }
    /// Init a new value as a string
    pub fn newStr(data: []const u8) Value {
        var val = Value{ .kind = ValueKind.STRING, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        const str_slice = LiteralSlice(u8).init(data);
        val.as.string.data = str_slice;
        return val;
    }
    /// Init a new value as an array
    pub fn newArr(kind: *KindId, dimensions: []const usize, data: []const Value) Value {
        var val = Value{ .kind = ValueKind.ARRAY, .as = .{ .EMPTY = [_]u64{0} ** 6 } };
        const dim_slice = LiteralSlice(usize).init(dimensions);
        const data_slice = LiteralSlice(Value).init(data);
        val.as.array.data = data_slice;
        val.as.array.dimensions = dim_slice;
        val.as.array.kind = kind;
        return val;
    }
};
