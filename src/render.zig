//! Mustache template renderer.
//!
//! Port of facil.io's `mustache_parser.h` build phase and the FIOBJ callback
//! layer from `fiobj_mustache.c` (MIT, Boaz Segev 2018-2019), with the FIOBJ
//! object tree replaced by type-erased `Context` views over the user's data
//! (see `context.zig`).

const std = @import("std");
const parser = @import("parser.zig");
const context = @import("context.zig");
const Template = parser.Template;
const Instruction = parser.Instruction;
const Context = context.Context;

pub const Error = error{TooDeep} || std.Io.Writer.Error;

const RenderFrame = struct {
    context: Context,
    /// The section's resolved value, cached when the section is entered.
    section: ?Context,
    /// Instruction index of the section's `section_start`.
    start: u32,
    /// Instruction index of the matching `section_end`.
    end: u32,
    /// Current loop iteration.
    idx: usize,
    /// Number of iterations to perform.
    count: usize,
};

/// Renders a compiled template against `data` (any renderable Zig value),
/// streaming into `out`. Nothing is flushed; the caller owns the writer's
/// buffering.
///
/// The instruction array behaves like machine code that can loop (sections)
/// and jump (reused partials), so this is a small VM with an explicit frame
/// stack rather than recursion.
pub fn render(template: *const Template, data: anytype, out: *std.Io.Writer) Error!void {
    const root: Context = if (comptime context.isComptimeOnly(@TypeOf(data)))
        comptime context.comptimeValue(data)
    else
        Context.init(&data);

    const insts = template.instructions;
    const bytes = template.data;
    var r: Renderer = .{
        .insts = insts,
        .data = bytes,
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
            .write_text => try out.writeAll(bytes[inst.name_pos..][0..inst.name_len]),
            .write_arg => try r.writeArg(bytes[inst.name_pos..][0..inst.name_len], true),
            .write_arg_unescaped => try r.writeArg(bytes[inst.name_pos..][0..inst.name_len], false),
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
                    const name = bytes[inst.name_pos..][0..inst.name_len];
                    frame.section = r.findValue(name);
                    // Truthiness matches mustache.js: '', 0 and NaN are falsy.
                    var count: usize = if (frame.section) |v| v.count() else 0;
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
    out: *std.Io.Writer,
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
                // element for array sections) becomes the context. An
                // inverted section over an empty array still runs once;
                // there is no element (`element` returns null), so the
                // parent context (already in `frame.context`) stays active.
                if (frame.section) |v| {
                    if (v.element(frame.idx)) |elem| frame.context = elem;
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
    /// towards the root). Dotted names split strictly at every dot (per the
    /// mustache spec they are never literal keys): the head resolves against
    /// the section tree and each remaining segment descends one object level.
    fn findValue(r: *const Renderer, name: []const u8) ?Context {
        // Implicit iterator: `{{.}}` resolves to the current context itself.
        if (name.len == 1 and name[0] == '.') return r.frames[r.index].context;
        const first_dot = std.mem.indexOfScalar(u8, name, '.') orelse return r.lookupTree(name);
        var current = r.lookupTree(name[0..first_dot]) orelse return null;
        var rest = name[first_dot + 1 ..];
        while (std.mem.indexOfScalar(u8, rest, '.')) |dot| {
            current = current.getKey(rest[0..dot]) orelse return null;
            rest = rest[dot + 1 ..];
        }
        return current.getKey(rest);
    }

    /// Searches the frame stack from the current section towards the root,
    /// skipping repeated contexts, for an object containing `name`.
    fn lookupTree(r: *const Renderer, name: []const u8) ?Context {
        var i = r.index;
        var previous: ?Context = null;
        while (true) : (i -= 1) {
            const ctx = r.frames[i].context;
            const repeated = if (previous) |p| ctx.eql(p) else false;
            if (!repeated) {
                if (ctx.getKey(name)) |v| return v;
                previous = ctx;
            }
            if (i == 0) return null;
        }
    }

    fn writePadding(r: *Renderer) std.Io.Writer.Error!void {
        var i = r.padding;
        while (i != 0) : (i = r.insts[i].end) {
            const inst = r.insts[i];
            try r.out.writeAll(r.data[inst.name_pos..][0..inst.name_len]);
        }
    }

    /// Resolves an argument and writes its value as text. Padding (partial
    /// indentation) is never injected here: per the mustache spec,
    /// indentation applies to the partial's own lines, not to lines inside
    /// interpolated values.
    fn writeArg(r: *Renderer, name: []const u8, escape: bool) std.Io.Writer.Error!void {
        const v = r.findValue(name) orelse return;
        try v.write(r.out, escape);
    }
};
