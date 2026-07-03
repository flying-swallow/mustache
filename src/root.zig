//! Pure-Zig mustache template engine.
//!
//! Port of the mustache implementation from facil.io (`mustache_parser.h`
//! and `fiobj_mustache.c`, MIT, Boaz Segev 2018-2019), with the FIOBJ object
//! system replaced by a native value tree.
//!
//! ```zig
//! var m = try Mustache.fromData(allocator, "Hello {{name}}!");
//! defer m.deinit();
//! const rendered = try m.build(allocator, .{ .name = "World" });
//! defer allocator.free(rendered);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const parser = @import("parser.zig");
pub const render = @import("render.zig");
pub const Value = render.Value;

pub const Mustache = struct {
    allocator: Allocator,
    template: parser.Template,

    pub const Error = parser.LoadError;
    pub const BuildError = render.RenderError;

    /// Load arguments used when creating a new `Mustache` instance.
    pub const LoadArgs = struct {
        /// Required for `filename`-based templates and for loading partial
        /// templates from the filesystem.
        io: ?std.Io = null,

        /// Filename. This enables partial templates on the filesystem.
        filename: ?[]const u8 = null,

        /// String data, used as the template contents if set. `filename`
        /// then only names the template (allowing recursive partials).
        data: ?[]const u8 = null,

        /// Named in-memory partials, resolved before the filesystem.
        partials: []const parser.Partial = &.{},
    };

    pub const Partial = parser.Partial;

    /// Compiles a template; `deinit()` frees it.
    pub fn init(allocator: Allocator, args: LoadArgs) Error!Mustache {
        return .{
            .allocator = allocator,
            .template = try parser.load(allocator, args.io, args.filename, args.data, args.partials),
        };
    }

    /// Compiles a template from in-memory data; `deinit()` frees it.
    /// Partials referenced by the template fail with `error.FileNotFound`
    /// (use `init` with an `io` to support them).
    pub fn fromData(allocator: Allocator, data: []const u8) Error!Mustache {
        return init(allocator, .{ .data = data });
    }

    /// Compiles a template from a file; `deinit()` frees it.
    pub fn fromFile(allocator: Allocator, io: std.Io, filename: []const u8) Error!Mustache {
        return init(allocator, .{ .io = io, .filename = filename });
    }

    pub fn deinit(self: *Mustache) void {
        self.template.deinit(self.allocator);
        self.* = undefined;
    }

    /// Renders the template against `data` (a struct). Returns the rendered
    /// text; the caller owns it and frees it with `allocator.free`.
    pub fn build(self: *const Mustache, allocator: Allocator, data: anytype) BuildError![]const u8 {
        if (@typeInfo(@TypeOf(data)) != .@"struct") {
            @compileError("No struct: '" ++ @typeName(@TypeOf(data)) ++ "'");
        }
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const root = try valueify(arena_state.allocator(), data);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try render.render(&self.template, &root, allocator, &out);
        return out.toOwnedSlice(allocator);
    }
};

/// Converts any Zig value into a `Value` tree allocated in `arena`. Strings
/// are duplicated, so the result does not alias the input.
pub fn valueify(arena: Allocator, value: anytype) Allocator.Error!Value {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .float, .comptime_float => return .{ .float = value },
        .comptime_int => return .{ .int = value },
        .int => {
            if (std.math.cast(i64, value)) |n| return .{ .int = n };
            return .{ .string = try std.fmt.allocPrint(arena, "{d}", .{value}) };
        },
        .bool => return .{ .bool = value },
        .null => return .null,
        .optional => {
            if (value) |payload| return valueify(arena, payload);
            return .null;
        },
        .@"enum" => return .{ .int = @intFromEnum(value) },
        .@"union" => |info| {
            if (info.tag_type) |UnionTagType| {
                inline for (info.field_names) |field_name| {
                    if (value == @field(UnionTagType, field_name)) {
                        return valueify(arena, @field(value, field_name));
                    }
                }
                unreachable;
            }
            @compileError("Unable to valueify untagged union '" ++ @typeName(T) ++ "'");
        },
        .@"struct" => |S| {
            if (S.is_tuple) {
                const array = try arena.alloc(Value, S.field_names.len);
                inline for (0..S.field_names.len) |i| {
                    array[i] = try valueify(arena, value[i]);
                }
                return .{ .array = array };
            }
            var map: std.StringHashMapUnmanaged(Value) = .empty;
            comptime var field_count = 0;
            comptime for (S.field_types) |field_type| {
                if (field_type != void) field_count += 1;
            };
            try map.ensureTotalCapacity(arena, field_count);
            inline for (S.field_names, S.field_types) |field_name, field_type| {
                if (field_type != void) {
                    map.putAssumeCapacity(field_name, try valueify(arena, @field(value, field_name)));
                }
            }
            return .{ .object = map };
        },
        .error_set => return .{ .string = @errorName(value) },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => {
                    const Slice = []const std.meta.Elem(ptr_info.child);
                    return valueify(arena, @as(Slice, value));
                },
                else => return valueify(arena, value.*),
            },
            .slice => {
                if (ptr_info.child == u8 and std.unicode.utf8ValidateSlice(value)) {
                    return .{ .string = try arena.dupe(u8, value) };
                }
                const array = try arena.alloc(Value, value.len);
                for (value, array) |item, *slot| slot.* = try valueify(arena, item);
                return .{ .array = array };
            },
            else => @compileError("Unable to valueify type '" ++ @typeName(T) ++ "'"),
        },
        .array => return valueify(arena, &value),
        .vector => |info| {
            const array: [info.len]info.child = value;
            return valueify(arena, &array);
        },
        else => @compileError("Unable to valueify type '" ++ @typeName(T) ++ "'"),
    }
}

test {
    _ = @import("tests.zig");
    _ = @import("mustachejs_tests.zig");
}
