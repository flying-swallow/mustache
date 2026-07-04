//! Type-erased, comptime-generated data contexts for the renderer.
//!
//! A `Context` is a fat pointer (value pointer plus a vtable generated at
//! comptime for the value's concrete type) that views the user's data in
//! place — no intermediate tree, no allocation, no copies. Structs are
//! objects, tuples/slices/arrays/vectors are arrays, valid-UTF-8 u8
//! sequences are strings, and ints/floats/bools/enums/error values are
//! scalars.
//!
//! Type erasure (rather than a typed context chain) is load-bearing: the
//! renderer keeps a homogeneous frame stack, and recursive partials over
//! recursive data types (`Node{children: []Node}`) would otherwise require
//! unbounded comptime type instantiation. `Impl(Node)` only refers to
//! `Impl([]const Node)` through function pointers, so instantiation
//! terminates via generic memoization.

const std = @import("std");
const Writer = std.Io.Writer;

pub const Context = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// mustache.js-compatible truthiness -> section iteration count
        /// ('', 0 and NaN are falsy; array-likes iterate their length).
        count: *const fn (*const anyopaque) usize,
        /// Context of iteration `i` of a section over this value: element `i`
        /// for array-likes (null past the end, so an inverted section over an
        /// empty array keeps the parent context), the value itself otherwise.
        element: *const fn (*const anyopaque, usize) ?Context,
        /// Object (struct) key lookup; null for non-objects / missing keys.
        get: *const fn (*const anyopaque, []const u8) ?Context,
        /// Writes the value's text form (nothing for null and composites),
        /// HTML-escaping if requested.
        write: *const fn (*const anyopaque, *Writer, bool) Writer.Error!void,
    };

    /// Identity for the renderer's repeated-context skip. The vtable pointer
    /// participates because distinct values can share an address (a struct
    /// and its first field, zero-sized values).
    pub fn eql(a: Context, b: Context) bool {
        return a.ptr == b.ptr and a.vtable == b.vtable;
    }

    pub fn count(c: Context) usize {
        return c.vtable.count(c.ptr);
    }

    pub fn element(c: Context, i: usize) ?Context {
        return c.vtable.element(c.ptr, i);
    }

    pub fn getKey(c: Context, key: []const u8) ?Context {
        return c.vtable.get(c.ptr, key);
    }

    pub fn write(c: Context, w: *Writer, escape: bool) Writer.Error!void {
        return c.vtable.write(c.ptr, w, escape);
    }

    /// Creates a context viewing `value.*`; the pointee must outlive the
    /// context. Optionals and tagged unions are unwrapped here (the context
    /// points at the payload), so a vtable only ever describes a concrete
    /// value.
    pub fn init(value: anytype) Context {
        const P = @TypeOf(value);
        const p_info = @typeInfo(P);
        if (p_info != .pointer or p_info.pointer.size != .one)
            @compileError("Context.init expects a single-item pointer, got '" ++ @typeName(P) ++ "'");
        const T = p_info.pointer.child;
        switch (@typeInfo(T)) {
            .optional => {
                if (value.*) |*payload| return init(payload);
                return null_context;
            },
            .@"union" => |info| {
                if (info.tag_type == null)
                    @compileError("unable to render untagged union '" ++ @typeName(T) ++ "'");
                switch (value.*) {
                    inline else => |*payload| return init(payload),
                }
            },
            .pointer => |info| switch (info.size) {
                .one => return init(value.*),
                .slice => return .{ .ptr = @ptrCast(value), .vtable = &Impl(T).vtable },
                else => @compileError("unable to render type '" ++ @typeName(T) ++ "'"),
            },
            .comptime_int, .comptime_float, .null, .enum_literal => @compileError(
                "comptime-only value of type '" ++ @typeName(T) ++ "' must go through comptimeValue",
            ),
            else => return .{ .ptr = @ptrCast(value), .vtable = &Impl(T).vtable },
        }
    }
};

/// Whether `T` has no runtime representation and must be rendered through
/// `comptimeValue` instead of `Context.init`.
pub fn isComptimeOnly(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .comptime_int, .comptime_float, .null, .enum_literal => true,
        else => false,
    };
}

/// Context for a comptime-only value (a comptime struct field — which every
/// field of an anonymous literal like `.{ .name = "World" }` is — or a bare
/// comptime int/float/null root): promotes the value into a container-level
/// constant, giving it a static address for the context to point at. The
/// same value always promotes to the same constant (generic instantiations
/// are memoized on `v`), so context identity stays stable across lookups.
pub fn comptimeValue(comptime v: anytype) Context {
    const F = @TypeOf(v);
    if (F == @TypeOf(null)) return null_context;
    const R = switch (@typeInfo(F)) {
        .comptime_int => if (v >= std.math.minInt(i64) and v <= std.math.maxInt(i64))
            i64
        else
            std.math.IntFittingRange(@min(v, 0), @max(v, 1)),
        .comptime_float => f64,
        .enum_literal => @compileError("unable to render an enum literal"),
        else => F,
    };
    const holder = struct {
        const promoted: R = v;
    };
    return Context.init(&holder.promoted);
}

/// The context of a null value (absent optional). It is a *found* value that
/// renders nothing and is falsy — distinct from a failed lookup, so a null
/// field shadows same-named keys in parent scopes (per mustache.js).
pub const null_context: Context = .{ .ptr = &null_value, .vtable = &null_vtable };
const null_value: u8 = 0;
const null_vtable: Context.VTable = .{
    .count = struct {
        fn f(_: *const anyopaque) usize {
            return 0;
        }
    }.f,
    // A section over null keeps the null value itself as context.
    .element = struct {
        fn f(_: *const anyopaque, _: usize) ?Context {
            return null_context;
        }
    }.f,
    .get = struct {
        fn f(_: *const anyopaque, _: []const u8) ?Context {
            return null;
        }
    }.f,
    .write = struct {
        fn f(_: *const anyopaque, _: *Writer, _: bool) Writer.Error!void {}
    }.f,
};

/// Generates the vtable for a concrete (already-unwrapped) type `T`.
fn Impl(comptime T: type) type {
    return struct {
        pub const vtable: Context.VTable = .{
            .count = countFn,
            .element = elementFn,
            .get = getFn,
            .write = writeFn,
        };

        fn self(ptr: *const anyopaque) *const T {
            return @ptrCast(@alignCast(ptr));
        }

        fn selfContext(ptr: *const anyopaque) Context {
            return .{ .ptr = ptr, .vtable = &vtable };
        }

        fn countFn(ptr: *const anyopaque) usize {
            switch (@typeInfo(T)) {
                .@"struct" => |info| return if (info.is_tuple) info.field_names.len else 1,
                .array => |info| return if (comptime info.child == u8)
                    byteCount(self(ptr))
                else
                    info.len,
                .pointer => |info| return if (comptime info.child == u8)
                    byteCount(self(ptr).*)
                else
                    self(ptr).len,
                .vector => |info| return info.len,
                .int => return @intFromBool(self(ptr).* != 0),
                .float => return @intFromBool(self(ptr).* != 0 and !std.math.isNan(self(ptr).*)),
                .bool => return @intFromBool(self(ptr).*),
                .@"enum" => return @intFromBool(@intFromEnum(self(ptr).*) != 0),
                .error_set => return 1,
                else => @compileError("unable to render type '" ++ @typeName(T) ++ "'"),
            }
        }

        fn elementFn(ptr: *const anyopaque, i: usize) ?Context {
            switch (@typeInfo(T)) {
                .@"struct" => |info| {
                    if (comptime !info.is_tuple) return selfContext(ptr);
                    const s = self(ptr);
                    inline for (0..info.field_types.len) |j| {
                        if (i == j) return tupleField(s, j);
                    }
                    return null;
                },
                .array => |info| {
                    const s = self(ptr);
                    if (comptime info.child == u8) return byteElement(s, ptr, i);
                    return if (i < info.len) Context.init(&s[i]) else null;
                },
                .pointer => |info| {
                    const s = self(ptr).*;
                    if (comptime info.child == u8) return byteElement(s, ptr, i);
                    return if (i < s.len) Context.init(&s[i]) else null;
                },
                .vector => |info| {
                    inline for (0..info.len) |j| {
                        if (i == j) {
                            const load = struct {
                                fn f(p: *const T) info.child {
                                    return p.*[j];
                                }
                            }.f;
                            return .{ .ptr = ptr, .vtable = &ByValue(T, info.child, load).vtable };
                        }
                    }
                    return null;
                },
                // A section over a scalar/object keeps the value as context.
                else => return selfContext(ptr),
            }
        }

        fn getFn(ptr: *const anyopaque, key: []const u8) ?Context {
            switch (@typeInfo(T)) {
                .@"struct" => |info| {
                    if (comptime info.is_tuple) return null;
                    inline for (info.field_names, info.field_types, info.field_attrs) |name, F, attrs| {
                        // void fields are not keys.
                        if (comptime F != void) {
                            if (std.mem.eql(u8, key, name)) {
                                if (comptime attrs.@"comptime") {
                                    // Comptime fields (all fields of anonymous
                                    // literals) have no runtime address; their
                                    // value lives in the type. `?@TypeOf(null)`
                                    // is not a legal type, so a literal-null
                                    // field bypasses `defaultValue`.
                                    if (comptime F == @TypeOf(null)) return null_context;
                                    return comptimeValue(attrs.defaultValue(F).?);
                                } else if (comptime info.layout == .@"packed") {
                                    // Packed fields are not addressable.
                                    const load = struct {
                                        fn f(p: *const T) F {
                                            return @field(p.*, name);
                                        }
                                    }.f;
                                    return .{ .ptr = ptr, .vtable = &ByValue(T, F, load).vtable };
                                } else {
                                    return Context.init(&@field(self(ptr).*, name));
                                }
                            }
                        }
                    }
                    return null;
                },
                else => return null,
            }
        }

        fn writeFn(ptr: *const anyopaque, w: *Writer, escape: bool) Writer.Error!void {
            switch (@typeInfo(T)) {
                // Composite values have no text form (the C version
                // serialized them as JSON; not supported).
                .@"struct", .vector => {},
                .array => |info| if (comptime info.child == u8)
                    try byteWrite(self(ptr), w, escape),
                .pointer => |info| if (comptime info.child == u8)
                    try byteWrite(self(ptr).*, w, escape),
                .int => try w.print("{d}", .{self(ptr).*}),
                .float => try w.print("{d}", .{self(ptr).*}),
                .bool => try w.writeAll(if (self(ptr).*) "true" else "false"),
                .@"enum" => try w.print("{d}", .{@intFromEnum(self(ptr).*)}),
                .error_set => try writeString(w, @errorName(self(ptr).*), escape),
                else => @compileError("unable to render type '" ++ @typeName(T) ++ "'"),
            }
        }

        fn tupleField(s: *const T, comptime j: usize) Context {
            const info = @typeInfo(T).@"struct";
            const F = info.field_types[j];
            if (comptime F == @TypeOf(null)) return null_context;
            if (comptime info.field_attrs[j].@"comptime")
                return comptimeValue(info.field_attrs[j].defaultValue(F).?);
            return Context.init(&s.*[j]);
        }

        /// A u8 sequence is a string when it is valid UTF-8 and an array of
        /// bytes otherwise, decided at render time.
        fn byteCount(s: []const u8) usize {
            if (std.unicode.utf8ValidateSlice(s)) return @intFromBool(s.len != 0);
            return s.len;
        }

        fn byteElement(s: []const u8, ptr: *const anyopaque, i: usize) ?Context {
            if (std.unicode.utf8ValidateSlice(s)) return selfContext(ptr);
            return if (i < s.len) Context.init(&s[i]) else null;
        }

        fn byteWrite(s: []const u8, w: *Writer, escape: bool) Writer.Error!void {
            if (!std.unicode.utf8ValidateSlice(s)) return;
            try writeString(w, s, escape);
        }
    };
}

/// Vtable for values that cannot be addressed (packed-struct fields and
/// vector elements): `load` copies the value out of the parent, whose
/// pointer stays the context's `ptr`. Only scalars and nested packed structs
/// can occur here, so `element` never needs to hand out element pointers.
fn ByValue(comptime Parent: type, comptime F: type, comptime load: fn (*const Parent) F) type {
    return struct {
        pub const vtable: Context.VTable = .{
            .count = countFn,
            .element = elementFn,
            .get = getFn,
            .write = writeFn,
        };

        fn self(ptr: *const anyopaque) *const Parent {
            return @ptrCast(@alignCast(ptr));
        }

        fn countFn(ptr: *const anyopaque) usize {
            const v = load(self(ptr));
            return Impl(F).vtable.count(@ptrCast(&v));
        }

        fn elementFn(ptr: *const anyopaque, _: usize) ?Context {
            // A section over a scalar keeps the value itself as context.
            return .{ .ptr = ptr, .vtable = &vtable };
        }

        fn getFn(ptr: *const anyopaque, key: []const u8) ?Context {
            switch (@typeInfo(F)) {
                .@"struct" => |info| {
                    if (comptime info.is_tuple) return null;
                    inline for (info.field_names, info.field_types) |name, FF| {
                        if (comptime FF != void) {
                            if (std.mem.eql(u8, key, name)) {
                                const inner = struct {
                                    fn f(p: *const Parent) FF {
                                        return @field(load(p), name);
                                    }
                                }.f;
                                return .{ .ptr = ptr, .vtable = &ByValue(Parent, FF, inner).vtable };
                            }
                        }
                    }
                    return null;
                },
                else => return null,
            }
        }

        fn writeFn(ptr: *const anyopaque, w: *Writer, escape: bool) Writer.Error!void {
            const v = load(self(ptr));
            return Impl(F).vtable.write(@ptrCast(&v), w, escape);
        }
    };
}

fn writeString(w: *Writer, s: []const u8, escape: bool) Writer.Error!void {
    if (!escape) return w.writeAll(s);
    for (s) |c| try w.writeAll(html_escape_table[c]);
}

/// The exact escape table of mustache.js's `entityMap`: the HTML
/// metacharacters plus backtick, '=' and '/' are replaced, everything else
/// passes through.
const html_escape_table: [256][]const u8 = blk: {
    @setEvalBranchQuota(10_000);
    var table: [256][]const u8 = undefined;
    for (0..256) |i| {
        table[i] = switch (i) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&#39;",
            '`' => "&#x60;",
            '=' => "&#x3D;",
            '/' => "&#x2F;",
            else => single(i),
        };
    }
    break :blk table;
};

fn single(comptime i: usize) []const u8 {
    const c = [1]u8{@intCast(i)};
    const copy = c;
    return &copy;
}
