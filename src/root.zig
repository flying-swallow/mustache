//! Pure-Zig mustache template engine.
//!
//! Port of the mustache implementation from facil.io (`mustache_parser.h`
//! and `fiobj_mustache.c`, MIT, Boaz Segev 2018-2019), rendering directly
//! against plain Zig values through comptime-generated accessors.
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
pub const Context = @import("context.zig").Context;
const render_mod = @import("render.zig");

/// Error set of the streaming `render`.
pub const RenderError = render_mod.Error;
/// Error set of `renderAlloc` / `Mustache.build`.
pub const RenderAllocError = error{TooDeep} || Allocator.Error;

pub const Mustache = struct {
    allocator: Allocator,
    template: parser.Template,

    pub const Error = parser.LoadError;
    pub const BuildError = RenderAllocError;

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
    /// Partials referenced by the template render as the empty string
    /// (use `init` with `partials` or an `io` to support them).
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
        return renderAlloc(allocator, &self.template, data);
    }

    /// Renders the template against `data`, streaming into `writer`.
    pub fn render(self: *const Mustache, data: anytype, writer: *std.Io.Writer) RenderError!void {
        return render_mod.render(&self.template, data, writer);
    }
};

/// Renders an already-compiled `template` against `data` (any renderable Zig
/// value), streaming into `writer`. Nothing is flushed; the caller owns the
/// writer's buffering. Works with both runtime-compiled templates
/// (`parser.load`) and comptime-compiled ones (`comptimeTemplate`).
pub fn render(
    template: *const parser.Template,
    data: anytype,
    writer: *std.Io.Writer,
) RenderError!void {
    return render_mod.render(template, data, writer);
}

/// Renders an already-compiled `template` against `data`. Returns the
/// rendered text; the caller owns it and frees it with `allocator.free`.
pub fn renderAlloc(
    allocator: Allocator,
    template: *const parser.Template,
    data: anytype,
) RenderAllocError![]const u8 {
    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, template.size_hint);
    defer aw.deinit();
    render_mod.render(template, data, &aw.writer) catch |err| switch (err) {
        error.TooDeep => return error.TooDeep,
        // An Allocating writer only fails when it runs out of memory.
        error.WriteFailed => return error.OutOfMemory,
    };
    return aw.toOwnedSlice();
}

/// Arguments for compiling a template at comptime. Only in-memory sources are
/// supported (the filesystem is unreachable at comptime); load file contents
/// via `@embedFile`.
pub const ComptimeArgs = struct {
    /// Template contents.
    data: []const u8,
    /// Names the (virtual) root template, enabling recursive partials that
    /// reference it.
    filename: []const u8 = "",
    /// Named in-memory partials.
    partials: []const parser.Partial = &.{},
};

/// Compiles a template at compile time into a const-backed `parser.Template`,
/// with zero runtime parsing cost and no allocation for the template itself.
/// Render it with `render` or `renderAlloc`. Any parse failure is a compile
/// error.
///
/// ```zig
/// const tmpl = comptime mustache.comptimeTemplate(.{ .data = "Hello {{name}}!" });
/// const out = try mustache.renderAlloc(alloc, &tmpl, .{ .name = "World" });
/// defer alloc.free(out);
/// ```
pub fn comptimeTemplate(comptime opts: ComptimeArgs) parser.Template {
    return @import("comptime_parse.zig").parse(opts.data, opts.filename, opts.partials);
}

/// A type wrapper around a comptime-compiled template, mirroring the runtime
/// `Mustache` ergonomics without any allocation or `deinit` for parsing.
///
/// ```zig
/// const T = mustache.Comptime(.{ .data = "Hello {{name}}!" });
/// const out = try T.build(alloc, .{ .name = "World" });
/// defer alloc.free(out);
/// ```
pub fn Comptime(comptime opts: ComptimeArgs) type {
    return struct {
        /// The compiled template, available as a compile-time constant.
        pub const template = comptimeTemplate(opts);

        /// Renders the template against `data` (a struct); caller frees.
        pub fn build(allocator: Allocator, data: anytype) RenderAllocError![]const u8 {
            return renderAlloc(allocator, &template, data);
        }

        /// Renders the template against `data`, streaming into `writer`.
        pub fn render(data: anytype, writer: *std.Io.Writer) RenderError!void {
            return render_mod.render(&template, data, writer);
        }
    };
}
