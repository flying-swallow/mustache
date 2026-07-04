//! Type-erased, comptime-generated data contexts for the renderer.
//!
//! A `Context` is a fat pointer (value pointer plus a vtable generated at
//! comptime for the value's concrete type) that views the user's data in
//! place — no intermediate tree, no allocation, no copies. Structs are
//! objects, tuples/slices/arrays/vectors are arrays, u8 sequences are
//! strings (no UTF-8 validation — bytes pass through verbatim), and
//! ints/floats/bools/enums/error values are scalars.
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
        /// Writes the value's text form (nothing for null and composites),
        /// HTML-escaping if requested.
        write: *const fn (*const anyopaque, *Writer, bool) Writer.Error!void,
        /// Hot-path combination of `getHash` + `write`: resolves the object
        /// key whose name hashes to `hash` (a precomputed, trusted
        /// `fieldHash`) and writes its text directly, skipping the
        /// intermediate `Context`. Returns true if the key was present (even
        /// a present-but-null value that writes nothing), false if it is not
        /// a key of this object. Non-objects and missing keys return false,
        /// mirroring `getHash`.
        getWrite: *const fn (*const anyopaque, u32, *Writer, bool) Writer.Error!bool,
        /// Object (struct) key lookup, dispatched on a precomputed
        /// `hash == fieldHash(key)`, which is trusted without a byte compare;
        /// null for non-objects / missing keys.
        getHash: *const fn (*const anyopaque, u32) ?Context,
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

    /// Key lookup with a precomputed hash; see `VTable.getHash`.
    pub fn getKeyHash(c: Context, hash: u32) ?Context {
        return c.vtable.getHash(c.ptr, hash);
    }

    /// Combined key lookup and write; see `VTable.getWrite`.
    pub fn getKeyWrite(c: Context, hash: u32, w: *Writer, escape: bool) Writer.Error!bool {
        return c.vtable.getWrite(c.ptr, hash, w, escape);
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
    .write = struct {
        fn f(_: *const anyopaque, _: *Writer, _: bool) Writer.Error!void {}
    }.f,
    .getWrite = struct {
        fn f(_: *const anyopaque, _: u32, _: *Writer, _: bool) Writer.Error!bool {
            return false;
        }
    }.f,
    .getHash = struct {
        fn f(_: *const anyopaque, _: u32) ?Context {
            return null;
        }
    }.f,
};

/// Wyhash (truncated to 32-bit) over `name`. The interpolation fast path
/// pre-hashes tag names at parse time (stored in `Instruction.offset`) and
/// dispatches field lookup by comparing against `comptime fieldHash(field_name)`;
/// both sides must agree, so they share this one function (Wyhash yields the
/// same value at comptime and runtime). A hash match is trusted without a
/// byte compare, so lookup relies on the hash being collision-free across an
/// object's field names.
pub fn fieldHash(name: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, name));
}

/// Whether a struct field of type `F` can be written directly by `writeValue`
/// without building a `Context` — i.e. it is a leaf that needs no optional /
/// union / pointer-to-one unwrapping. Kept in lockstep with `writeValue` and
/// the scalar prongs of `Impl.writeFn`.
pub fn directlyWritable(comptime F: type) bool {
    return switch (@typeInfo(F)) {
        .array => |a| a.child == u8,
        .pointer => |p| p.size == .slice and p.child == u8,
        .int, .float, .bool, .@"enum", .error_set => true,
        else => false,
    };
}

/// Monomorphic counterpart to `Context.init(ptr).write(...)` for the leaf
/// types `directlyWritable` admits: writes a struct field of comptime-known
/// type `F` with no vtable dispatch and no intermediate `Context`. Behaviour
/// must match the corresponding prong of `Impl.writeFn`.
pub fn writeValue(comptime F: type, ptr: *const F, w: *Writer, escape: bool) Writer.Error!void {
    switch (@typeInfo(F)) {
        .array => try writeString(w, ptr, escape), // child == u8
        .pointer => try writeString(w, ptr.*, escape), // slice, child == u8
        .int => try w.print("{d}", .{ptr.*}),
        .float => try w.print("{d}", .{ptr.*}),
        .bool => try w.writeAll(if (ptr.*) "true" else "false"),
        .@"enum" => try w.print("{d}", .{@intFromEnum(ptr.*)}),
        .error_set => try writeString(w, @errorName(ptr.*), escape),
        else => comptime unreachable,
    }
}

/// Shared struct field-scan + write, used by both the type-erased
/// `Impl.getWriteFn` vtable entry and the monomorphic static renderer
/// (`render.zig`). Finds the field of `T` whose name hashes to `hash` (a
/// precomputed, trusted `fieldHash`) and writes it: leaf fields go straight
/// through `writeValue` (no `Context`, no second dispatch); optionals /
/// unions / pointers-to-one / nested objects / packed and comptime fields
/// fall back to the general `get` + `write` path so behaviour is identical
/// to `getKeyHash(...).?.write(...)`. Returns true iff `hash` names a field of
/// `T` (even a present-but-null one that writes nothing).
pub fn writeField(comptime T: type, ptr: *const T, hash: u32, w: *Writer, escape: bool) Writer.Error!bool {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (comptime info.is_tuple) return false;
            inline for (info.field_names, info.field_types, info.field_attrs) |name, F, attrs| {
                if (comptime F != void) {
                    if (hash == (comptime fieldHash(name))) {
                        if (comptime !attrs.@"comptime" and info.layout != .@"packed" and directlyWritable(F)) {
                            try writeValue(F, &@field(ptr.*, name), w, escape);
                        } else {
                            // getHashFn matches the same field, so `.?` holds.
                            try Impl(T).getHashFn(@ptrCast(ptr), hash).?.write(w, escape);
                        }
                        return true;
                    }
                }
            }
            return false;
        },
        else => return false,
    }
}

/// Generates the vtable for a concrete (already-unwrapped) type `T`.
fn Impl(comptime T: type) type {
    return struct {
        pub const vtable: Context.VTable = .{
            .count = countFn,
            .element = elementFn,
            .write = writeFn,
            .getWrite = getWriteFn,
            .getHash = getHashFn,
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
                // A u8 sequence is a string: truthy iff non-empty.
                .array => |info| return if (comptime info.child == u8)
                    @intFromBool(self(ptr).len != 0)
                else
                    info.len,
                .pointer => |info| return if (comptime info.child == u8)
                    @intFromBool(self(ptr).len != 0)
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
                // A section over a string keeps the string itself as context.
                .array => |info| {
                    if (comptime info.child == u8) return selfContext(ptr);
                    const s = self(ptr);
                    return if (i < info.len) Context.init(&s[i]) else null;
                },
                .pointer => |info| {
                    if (comptime info.child == u8) return selfContext(ptr);
                    const s = self(ptr).*;
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

        /// Object key lookup; `hash` is a precomputed, trusted `fieldHash`
        /// (see `VTable.getHash`).
        fn getHashFn(ptr: *const anyopaque, hash: u32) ?Context {
            switch (@typeInfo(T)) {
                .@"struct" => |info| {
                    if (comptime info.is_tuple) return null;
                    inline for (info.field_names, info.field_types, info.field_attrs) |name, F, attrs| {
                        // void fields are not keys.
                        if (comptime F != void) {
                            if (hash == (comptime fieldHash(name))) {
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

        /// Hot-path field lookup + write; the shared `writeField` does the work
        /// (also called directly, without this vtable hop, by the static
        /// renderer in `render.zig`).
        fn getWriteFn(ptr: *const anyopaque, hash: u32, w: *Writer, escape: bool) Writer.Error!bool {
            return writeField(T, self(ptr), hash, w, escape);
        }

        fn writeFn(ptr: *const anyopaque, w: *Writer, escape: bool) Writer.Error!void {
            switch (@typeInfo(T)) {
                // Composite values have no text form (the C version
                // serialized them as JSON; not supported).
                .@"struct", .vector => {},
                .array => |info| if (comptime info.child == u8)
                    try writeString(w, self(ptr), escape),
                .pointer => |info| if (comptime info.child == u8)
                    try writeString(w, self(ptr).*, escape),
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
            .write = writeFn,
            .getWrite = getWriteFn,
            .getHash = getHashFn,
        };

        fn self(ptr: *const anyopaque) *const Parent {
            return @ptrCast(@alignCast(ptr));
        }

        /// Packed / by-value fields are never the render hot path, so this just
        /// defers to the general `getHashFn` + `write`.
        fn getWriteFn(ptr: *const anyopaque, hash: u32, w: *Writer, escape: bool) Writer.Error!bool {
            if (getHashFn(ptr, hash)) |c| {
                try c.write(w, escape);
                return true;
            }
            return false;
        }

        /// Field lookup over a packed / by-value struct; `hash` is a
        /// precomputed, trusted `fieldHash` (see `VTable.getHash`).
        fn getHashFn(ptr: *const anyopaque, hash: u32) ?Context {
            switch (@typeInfo(F)) {
                .@"struct" => |info| {
                    if (comptime info.is_tuple) return null;
                    inline for (info.field_names, info.field_types) |name, FF| {
                        if (comptime FF != void) {
                            if (hash == (comptime fieldHash(name))) {
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

        fn countFn(ptr: *const anyopaque) usize {
            const v = load(self(ptr));
            return Impl(F).vtable.count(@ptrCast(&v));
        }

        fn elementFn(ptr: *const anyopaque, _: usize) ?Context {
            // A section over a scalar keeps the value itself as context.
            return .{ .ptr = ptr, .vtable = &vtable };
        }

        fn writeFn(ptr: *const anyopaque, w: *Writer, escape: bool) Writer.Error!void {
            const v = load(self(ptr));
            return Impl(F).vtable.write(@ptrCast(&v), w, escape);
        }
    };
}

/// Vector width for the escape scan (0 disables the vector path on targets
/// without usable SIMD registers).
const escape_vec_len = std.simd.suggestVectorLength(u8) orelse 0;

fn writeString(w: *Writer, s: []const u8, escape: bool) Writer.Error!void {
    if (!escape) return w.writeAll(s);
    // Copy runs of non-escaped bytes in bulk, emitting an entity only at each
    // byte that needs escaping. Whole vector-width chunks are pre-screened
    // with SIMD compares folded into a single `@reduce` test — escapes are
    // rare, so most chunks are skipped at ~one branch per chunk. Chunks with
    // a hit and the sub-vector tail go byte-at-a-time through the flag table.
    // (Combining the compares as vectors and reducing once is deliberate: a
    // per-compare movemask/`@bitCast`-to-int is cheap on x86 but expands to a
    // multi-instruction sequence on NEON, and benched slower than the scalar
    // loop.)
    var start: usize = 0;
    var i: usize = 0;
    if (comptime escape_vec_len > 0) {
        const n = escape_vec_len;
        const V = @Vector(n, u8);
        while (i + n <= s.len) : (i += n) {
            const chunk: V = s[i..][0..n].*;
            var hits = @intFromBool(chunk == @as(V, @splat(@as(u8, html_escape_chars[0]))));
            inline for (html_escape_chars[1..]) |c|
                hits |= @intFromBool(chunk == @as(V, @splat(@as(u8, c))));
            if (@reduce(.Or, hits) == 0) continue;
            for (i..i + n) |j| {
                if (html_escape_flags[s[j]]) {
                    if (j > start) try w.writeAll(s[start..j]);
                    try w.writeAll(htmlEntity(s[j]));
                    start = j + 1;
                }
            }
        }
    }
    while (i < s.len) : (i += 1) {
        if (html_escape_flags[s[i]]) {
            if (i > start) try w.writeAll(s[start..i]);
            try w.writeAll(htmlEntity(s[i]));
            start = i + 1;
        }
    }
    if (start < s.len) try w.writeAll(s[start..]);
}

/// mustache.js's `entityMap` keys: the HTML metacharacters plus backtick, '='
/// and '/'.
const html_escape_chars = "&<>\"'`=/";

/// `html_escape_flags[c]` is true iff byte `c` must be escaped.
const html_escape_flags: [256]bool = blk: {
    var table: [256]bool = @splat(false);
    for (html_escape_chars) |c| table[c] = true;
    break :blk table;
};

/// The replacement entity for an escaped byte; only called on bytes for which
/// `html_escape_flags` is set.
fn htmlEntity(c: u8) []const u8 {
    return switch (c) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&#39;",
        '`' => "&#x60;",
        '=' => "&#x3D;",
        '/' => "&#x2F;",
        else => unreachable,
    };
}
