//! Mustache template renderer.
//!
//! Port of facil.io's `mustache_parser.h` build phase and the FIOBJ callback
//! layer from `fiobj_mustache.c` (MIT, Boaz Segev 2018-2019), with the FIOBJ
//! object tree replaced by `Value`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const Template = parser.Template;
const Instruction = parser.Instruction;

/// Dynamic value tree that templates are rendered against.
pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: []const Value,
    object: std.StringHashMapUnmanaged(Value),
};

pub const RenderError = error{TooDeep} || Allocator.Error;

const RenderFrame = struct {
    context: *const Value,
    /// The section's resolved value, cached when the section is entered.
    section: ?*const Value,
    /// Instruction index of the section's `section_start`.
    start: u32,
    /// Instruction index of the matching `section_end`.
    end: u32,
    /// Current loop iteration.
    idx: u32,
    /// Number of iterations to perform.
    count: u32,
};

/// Renders a compiled template against `root`, appending to `out`.
///
/// The instruction array behaves like machine code that can loop (sections)
/// and jump (reused partials), so this is a small VM with an explicit frame
/// stack rather than recursion.
pub fn render(
    template: *const Template,
    root: *const Value,
    gpa: Allocator,
    out: *std.ArrayList(u8),
) RenderError!void {
    const insts = template.instructions;
    const data = template.data;
    var r: Renderer = .{
        .insts = insts,
        .data = data,
        .gpa = gpa,
        .out = out,
    };
    r.frames[0] = .{
        .context = root,
        .section = null,
        .start = 0,
        .end = insts[0].end,
        .idx = 0,
        .count = 0,
    };

    var pos: u32 = 0;
    while (pos < insts.len) : (pos += 1) {
        const inst = insts[pos];
        switch (inst.op) {
            .write_text => try r.writeRaw(data[inst.name_pos..][0..inst.name_len]),
            .write_arg => try r.writeArg(data[inst.name_pos..][0..inst.name_len], true),
            .write_arg_unescaped => try r.writeArg(data[inst.name_pos..][0..inst.name_len], false),
            .section_goto, .section_start, .section_start_inv => {
                if (r.index + 1 >= parser.NESTING_LIMIT) return error.TooDeep;
                r.index += 1;
                const frame = &r.frames[r.index];
                frame.* = .{
                    .context = r.frames[r.index - 1].context,
                    .section = null,
                    .start = if (inst.op == .section_goto) inst.len else pos,
                    .end = inst.end,
                    .idx = 0,
                    .count = 1,
                };
                if (inst.name_pos != parser.NO_NAME) {
                    const name = data[inst.name_pos..][0..inst.name_len];
                    frame.section = r.findValue(name);
                    // Truthiness matches mustache.js: '', 0 and NaN are falsy.
                    var count: u32 = if (frame.section) |v| switch (v.*) {
                        .null => 0,
                        .bool => |b| @intFromBool(b),
                        .array => |a| @intCast(a.len),
                        .int => |n| @intFromBool(n != 0),
                        .float => |n| @intFromBool(n != 0 and !std.math.isNan(n)),
                        .string => |s| @intFromBool(s.len != 0),
                        .object => 1,
                    } else 0;
                    if (inst.op == .section_start_inv) count = @intFromBool(count == 0);
                    frame.count = count;
                }
                pos = r.sectionEnd();
            },
            .section_end => pos = r.sectionEnd(),
            .padding_push => r.padding = pos,
            .padding_pop => r.padding = insts[r.padding].end,
            .padding_write => try r.writePadding(),
        }
    }
}

const Renderer = struct {
    insts: []const Instruction,
    data: []const u8,
    gpa: Allocator,
    out: *std.ArrayList(u8),
    frames: [parser.NESTING_LIMIT]RenderFrame = undefined,
    index: usize = 0,
    /// Instruction index of the active `padding_push` (0 = none).
    padding: u32 = 0,

    /// Shared continuation of the section instructions: either (re-)enters
    /// the section body or jumps past its end. Returns the new instruction
    /// position (the main loop still adds 1).
    fn sectionEnd(r: *Renderer) u32 {
        const frame = &r.frames[r.index];
        if (frame.idx < frame.count) {
            var pos = frame.start;
            frame.context = r.frames[r.index - 1].context;
            const start_inst = r.insts[pos];
            if (start_inst.name_pos != parser.NO_NAME) {
                // Entering a named section: the section's value (an array
                // element for array sections) becomes the context. Inverted
                // sections over a missing key keep the parent context (the C
                // version aborted rendering here, against the mustache spec).
                if (frame.section) |v| {
                    frame.context = switch (v.*) {
                        // An inverted section over an empty array still runs
                        // once; there is no element, so the parent context
                        // (already in `frame.context`) stays active.
                        .array => |a| if (frame.idx < a.len) &a[frame.idx] else frame.context,
                        else => v,
                    };
                }
            }
            if (start_inst.op == .section_goto) pos += 1;
            frame.idx += 1;
            return pos;
        }
        r.index -= 1;
        return frame.end;
    }

    /// Looks up `name` in the current section and its parents (walking
    /// towards the root), then falls back to dot notation: the head resolves
    /// against the section tree and the rest descends into nested objects,
    /// preferring the longest literal key at each step.
    fn findValue(r: *const Renderer, name: []const u8) ?*const Value {
        // Implicit iterator: `{{.}}` resolves to the current context itself.
        if (name.len == 1 and name[0] == '.') return r.frames[r.index].context;
        if (r.lookupTree(name)) |v| return v;
        const first_dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
        var current = r.lookupTree(name[0..first_dot]) orelse return null;
        var rest = name[first_dot + 1 ..];
        while (true) {
            if (getKey(current, rest)) |v| return v;
            const dot = std.mem.indexOfScalar(u8, rest, '.') orelse return null;
            current = getKey(current, rest[0..dot]) orelse return null;
            rest = rest[dot + 1 ..];
        }
    }

    /// Searches the frame stack from the current section towards the root,
    /// skipping repeated contexts, for an object containing `name`.
    fn lookupTree(r: *const Renderer, name: []const u8) ?*const Value {
        var i = r.index;
        var previous: ?*const Value = null;
        while (true) : (i -= 1) {
            const context = r.frames[i].context;
            if (context != previous) {
                if (getKey(context, name)) |v| return v;
                previous = context;
            }
            if (i == 0) return null;
        }
    }

    fn writeRaw(r: *Renderer, text: []const u8) Allocator.Error!void {
        try r.out.appendSlice(r.gpa, text);
    }

    fn writePadding(r: *Renderer) Allocator.Error!void {
        var i = r.padding;
        while (i != 0) : (i = r.insts[i].end) {
            const inst = r.insts[i];
            try r.writeRaw(r.data[inst.name_pos..][0..inst.name_len]);
        }
    }

    /// Resolves an argument and writes its value as text.
    fn writeArg(r: *Renderer, name: []const u8, escape: bool) Allocator.Error!void {
        const v = r.findValue(name) orelse return;
        // Large enough for any f64 in decimal notation.
        var buf: [1024]u8 = undefined;
        const text: []const u8 = switch (v.*) {
            .null => return,
            .string => |s| s,
            .int => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable,
            .float => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable,
            .bool => |b| if (b) "true" else "false",
            // Composite values have no text form (the C version serialized
            // them as JSON; templates that rely on that are not supported).
            .array, .object => return,
        };
        if (text.len == 0) return;
        try r.writeText(text, escape);
    }

    /// Writes text to the output, HTML-escaping if requested and repeating
    /// the active padding after every newline (so multi-line values inside
    /// indented partials stay aligned).
    fn writeText(r: *Renderer, text: []const u8, escape: bool) Allocator.Error!void {
        if (escape) {
            for (text) |c| {
                if (c == '\n' and r.padding != 0) {
                    try r.out.append(r.gpa, '\n');
                    try r.writePadding();
                } else {
                    try r.out.appendSlice(r.gpa, html_escape_table[c]);
                }
            }
            return;
        }
        var rest = text;
        while (std.mem.indexOfScalar(u8, rest, '\n')) |nl| {
            try r.out.appendSlice(r.gpa, rest[0 .. nl + 1]);
            try r.writePadding();
            rest = rest[nl + 1 ..];
        }
        if (rest.len > 0) try r.out.appendSlice(r.gpa, rest);
    }
};

fn getKey(v: *const Value, key: []const u8) ?*const Value {
    if (v.* != .object) return null;
    return v.object.getPtr(key);
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
