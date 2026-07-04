//! Compile-time mustache template compiler.
//!
//! A comptime-only analog of the runtime `Loader` in `parser.zig`: it runs the
//! same parse algorithm but over fixed comptime arrays instead of allocator-
//! backed `std.ArrayList`s (Zig comptime has no working heap allocator, and
//! `std.ArrayList(T)`'s byte->T reinterpret cast is illegal at comptime). It
//! also supports only in-memory templates and in-memory partials — the
//! filesystem is unreachable at comptime — so the whole `loadFile` filesystem
//! branch is dropped. The produced `parser.Template` is const-backed and feeds
//! the existing (runtime) renderer unchanged.

const std = @import("std");
const parser = @import("parser.zig");
const context = @import("context.zig");

const Op = parser.Op;
const Instruction = parser.Instruction;
const Template = parser.Template;
const Segment = parser.Segment;
const PathSeg = parser.PathSeg;
const Frame = parser.Frame;
const Partial = parser.Partial;
const NESTING_LIMIT = parser.NESTING_LIMIT;
const NO_NAME = parser.NO_NAME;
const DELIMITER_MAX = parser.DELIMITER_MAX;
const LoadError = parser.LoadError;
const trim = parser.trim;

/// A comptime loader with fixed-capacity storage. Instantiated as a
/// `comptime var` by `parse`; every method mutates in place through it.
fn ComptimeLoader(comptime inst_cap: usize, comptime data_cap: usize, comptime seg_cap: usize) type {
    return struct {
        const Self = @This();

        // Filled with defined defaults (not `undefined`) so the whole array can
        // be copied out at comptime without reading uninitialized elements.
        insts: [inst_cap]Instruction = @splat(.{ .op = .write_text }),
        inst_len: u32 = 0,
        bytes: [data_cap]u8 = @splat(0),
        data_len: u32 = 0,
        segs: [seg_cap]Segment = undefined,
        seg_len: u32 = 0,
        // Every path segment is >= 1 byte, so segment count <= byte count.
        path_segs: [data_cap]PathSeg = @splat(.{ .hash = 0, .pos = 0, .len = 0 }),
        path_seg_len: u32 = 0,
        stack: [NESTING_LIMIT]Frame = undefined,
        /// Top of `stack`; 0 means empty (frame 0 is never used).
        index: u16 = 0,
        /// Instruction index of the currently active `padding_push` (0 = none).
        padding: u32 = 0,
        partials: []const Partial = &.{},

        fn pushInstruction(l: *Self, inst: Instruction) LoadError!void {
            if (l.inst_len >= inst_cap)
                @compileError("mustache comptime: instruction buffer overflow (report this template)");
            l.insts[l.inst_len] = inst;
            l.inst_len += 1;
        }

        fn appendData(l: *Self, bytes: []const u8) void {
            if (l.data_len + bytes.len > data_cap)
                @compileError("mustache comptime: data buffer overflow (report this template)");
            for (bytes) |b| {
                l.bytes[l.data_len] = b;
                l.data_len += 1;
            }
        }

        fn pushSegment(l: *Self, seg: Segment) void {
            if (l.seg_len >= seg_cap)
                @compileError("mustache comptime: segment buffer overflow (report this template)");
            l.segs[l.seg_len] = seg;
            l.seg_len += 1;
        }

        /// Splits the name `bytes[b..e]` on '.' and appends a pre-hashed
        /// `PathSeg` per segment; returns the (start, count) run for the
        /// `write_path` instruction. Mirrors `Loader.appendPathSegs`.
        fn appendPathSegs(l: *Self, b: u32, e: u32) struct { start: u32, count: u32 } {
            const start: u32 = l.path_seg_len;
            const name = l.bytes[b..e];
            if (name.len == 0 or (name.len == 1 and name[0] == '.'))
                return .{ .start = start, .count = 0 };
            var seg_pos: u32 = b;
            var rest: []const u8 = name;
            while (true) {
                const dot = std.mem.indexOfScalar(u8, rest, '.');
                const seg_len: u32 = if (dot) |d| @intCast(d) else @intCast(rest.len);
                if (l.path_seg_len >= data_cap)
                    @compileError("mustache comptime: path segment buffer overflow (report this template)");
                l.path_segs[l.path_seg_len] = .{
                    .hash = context.fieldHash(rest[0..seg_len]),
                    .pos = seg_pos,
                    .len = seg_len,
                };
                l.path_seg_len += 1;
                if (dot) |d| {
                    rest = rest[d + 1 ..];
                    seg_pos += seg_len + 1;
                } else break;
            }
            return .{ .start = start, .count = l.path_seg_len - start };
        }

        /// Emits text as `write_text` instructions, splitting at newlines and
        /// interleaving `padding_write` (see the runtime loader for details).
        fn pushTextInstructions(l: *Self, pos_arg: u32, len_arg: u32) LoadError!void {
            var pos = pos_arg;
            var len = len_arg;
            while (len > 0) {
                const nl = std.mem.indexOfScalarPos(u8, l.bytes[0 .. pos + len], pos, '\n') orelse break;
                const line_len: u32 = @intCast(nl + 1 - pos);
                try l.pushInstruction(.{ .op = .write_text, .name_pos = pos, .name_len = line_len });
                try l.pushInstruction(.{ .op = .padding_write });
                pos += line_len;
                len -= line_len;
            }
            if (len == 0) return;
            try l.pushInstruction(.{ .op = .write_text, .name_pos = pos, .name_len = len });
        }

        /// Registers template contents as a new segment and pushes a parser
        /// frame for it. Comptime slices never move, so no name dup is needed.
        fn loadData(l: *Self, name: []const u8, contents: []const u8) LoadError!void {
            var path_len: usize = name.len;
            while (path_len > 0) {
                path_len -= 1;
                if (name[path_len] == '/' or name[path_len] == '\\') {
                    path_len += 1;
                    break;
                }
            }
            l.pushSegment(.{
                .filename = name,
                .path_len = @intCast(path_len),
                .inst_start = l.inst_len,
            });
            const data_start: u32 = l.data_len;
            l.appendData(contents);
            try l.pushInstruction(.{ .op = .section_start });
            if (l.index + 1 >= NESTING_LIMIT) return error.TooDeep;
            l.index += 1;
            l.stack[l.index] = .{
                .segment = @intCast(l.seg_len - 1),
                .data_start = data_start,
                .data_pos = data_start,
                .data_end = l.data_len,
                .open_sections = 0,
                .del_start = .{ '{', '{', 0, 0 },
                .del_start_len = 2,
                .del_end = .{ '}', '}', 0, 0 },
                .del_end_len = 2,
            };
        }

        /// Returns the `section_start` instruction index of an already-loaded
        /// template, or null.
        fn fileInstStart(l: *Self, path: []const u8) ?u32 {
            for (l.segs[0..l.seg_len]) |seg| {
                if (std.mem.eql(u8, seg.filename, path)) return seg.inst_start;
            }
            return null;
        }

        /// Loads a partial template by name — in-memory only. In-memory
        /// partials are tried first (with `section_goto` dedup), then the name
        /// may refer to the virtual root (recursive templates); anything else
        /// fails with `error.FileNotFound` (which the partial tag turns into
        /// an empty render, per the mustache spec).
        fn loadFile(l: *Self, name: []const u8) LoadError!usize {
            if (name.len == 0) return error.FileNameTooShort;
            if (name.len >= 8192) return error.FileNameTooLong;

            for (l.partials) |p| {
                if (!std.mem.eql(u8, p.name, name)) continue;
                if (p.data.len == 0) return 0;
                if (l.fileInstStart(name)) |inst_start| {
                    try l.pushInstruction(.{
                        .op = .section_goto,
                        .len = inst_start,
                        .end = l.inst_len,
                    });
                    return 0;
                }
                try l.loadData(name, p.data);
                return p.data.len;
            }

            // Not an in-memory partial: the name may refer to the (virtual)
            // root template, which enables recursive templates.
            if (l.seg_len > 0) {
                const root = l.segs[0];
                if (std.mem.eql(u8, root.filename, name)) {
                    try l.pushInstruction(.{
                        .op = .section_goto,
                        .len = 0,
                        .end = l.inst_len,
                    });
                    return 0;
                }
            }
            return error.FileNotFound;
        }

        /// For a standalone tag: skips the following newline and trims the
        /// line's leading whitespace from the preceding `write_text`.
        fn standAloneAdjust(l: *Self, stand_alone: u32) void {
            if (stand_alone == 0) return;
            const f = &l.stack[l.index];
            if (f.data_pos < f.data_end and l.bytes[f.data_pos] == '\r') f.data_pos += 1;
            f.data_pos += 1;
            const pad_len = stand_alone >> 1;
            if (l.inst_len == 0) return;
            const last = &l.insts[l.inst_len - 1];
            if (last.op != .write_text) return;
            if (last.name_len <= pad_len) {
                l.inst_len -= 1;
            } else {
                last.name_len -= pad_len;
            }
        }

        /// Parses every template on the loader stack until it is empty.
        fn parse(l: *Self) LoadError!void {
            while (l.index != 0) {
                while (l.stack[l.index].data_pos < l.stack[l.index].data_end) {
                    try l.parseTag();
                }
                try l.closeTemplate();
                l.index -= 1;
            }
        }

        /// Parses text up to and including the next tag of the top template.
        fn parseTag(l: *Self) LoadError!void {
            const data = l.bytes[0..l.data_len];
            const f = l.stack[l.index]; // by value; mutations go through l.stack
            const start_pos = f.data_pos;
            const del_start = f.del_start[0..f.del_start_len];
            const del_end = f.del_end[0..f.del_end_len];

            const tag_start: u32 = @intCast(std.mem.indexOfPos(u8, data[0..f.data_end], start_pos, del_start) orelse {
                // No tags left; the rest is text.
                try l.pushTextInstructions(start_pos, f.data_end - start_pos);
                l.stack[l.index].data_pos = f.data_end;
                return;
            });
            if (tag_start != start_pos)
                try l.pushTextInstructions(start_pos, tag_start - start_pos);

            const beg: u32 = tag_start + f.del_start_len;
            const end: u32 = @intCast(std.mem.indexOfPos(u8, data[0..f.data_end], beg, del_end) orelse
                return error.ClosureMismatch);
            l.stack[l.index].data_pos = end + f.del_end_len;

            // Standalone tag detection.
            var stand_alone: u32 = 0;
            var stand_alone_pos: u32 = 0;
            const after = end + f.del_end_len;
            if (after >= f.data_end or data[after] == '\n' or
                (data[after] == '\r' and after + 1 < f.data_end and data[after + 1] == '\n'))
            {
                var pad: i64 = @as(i64, tag_start) - 1;
                while (pad >= start_pos and (data[@intCast(pad)] == ' ' or data[@intCast(pad)] == '\t'))
                    pad -= 1;
                if (pad < f.data_start or data[@intCast(pad)] == '\n') {
                    pad += 1;
                    stand_alone_pos = @intCast(pad);
                    stand_alone = ((tag_start - stand_alone_pos) << 1) | 1;
                }
            }

            if (beg == end) {
                // Empty tag; emit an (unresolvable) empty-named path (0 segments).
                try l.pushInstruction(.{ .op = .write_path, .name_pos = beg, .name_len = 0 });
                return;
            }

            switch (data[beg]) {
                '!' => {
                    // Comment.
                    l.standAloneAdjust(stand_alone);
                },
                '=' => {
                    // Delimiter change: {{=<start> <end>=}}.
                    l.standAloneAdjust(stand_alone);
                    var b = beg + 1;
                    var e = end;
                    if (e == b or data[e - 1] != '=') return error.ClosureMismatch;
                    e -= 1;
                    trim(data, &b, &e);
                    var div = b;
                    while (div < e and !std.ascii.isWhitespace(data[div])) div += 1;
                    if (div == e or div == b) return error.ClosureMismatch;
                    if (div - b > DELIMITER_MAX) return error.DelimiterTooLong;
                    const frame = &l.stack[l.index];
                    frame.del_start_len = @intCast(div - b);
                    @memcpy(frame.del_start[0..frame.del_start_len], data[b..div]);
                    while (div < e and std.ascii.isWhitespace(data[div])) div += 1;
                    if (div == e) return error.ClosureMismatch;
                    if (e - div > DELIMITER_MAX) return error.DelimiterTooLong;
                    frame.del_end_len = @intCast(e - div);
                    @memcpy(frame.del_end[0..frame.del_end_len], data[div..e]);
                },
                '#', '^' => |sigil| {
                    // Section start (or inverted section start).
                    l.standAloneAdjust(stand_alone);
                    var b = beg + 1;
                    var e = end;
                    trim(data, &b, &e);
                    const frame = &l.stack[l.index];
                    frame.open_sections += 1;
                    if (frame.open_sections >= NESTING_LIMIT) return error.TooDeep;
                    try l.pushInstruction(.{
                        .op = if (sigil == '#') .section_start else .section_start_inv,
                        .name_pos = b,
                        .name_len = e - b,
                        .offset = frame.data_pos - b,
                    });
                },
                '>' => {
                    // Partial template.
                    l.standAloneAdjust(stand_alone);
                    const pad_len = stand_alone >> 1;
                    if (pad_len > 0) {
                        try l.pushInstruction(.{
                            .op = .padding_push,
                            .name_pos = stand_alone_pos,
                            .name_len = pad_len,
                            .end = l.padding,
                        });
                        l.padding = l.inst_len - 1;
                    }
                    var b = beg + 1;
                    var e = end;
                    trim(data, &b, &e);
                    // Per the mustache spec, a partial that cannot be resolved
                    // renders as the empty string.
                    const loaded = l.loadFile(data[b..e]) catch |err| switch (err) {
                        error.FileNotFound => 0,
                        else => return err,
                    };
                    if (pad_len > 0) {
                        if (loaded > 0) {
                            // Initial padding, written when the partial starts.
                            try l.pushInstruction(.{
                                .op = .write_text,
                                .name_pos = stand_alone_pos,
                                .name_len = pad_len,
                            });
                        } else {
                            try l.pushInstruction(.{ .op = .padding_pop });
                        }
                    }
                },
                '/' => {
                    // Section end: find the matching open section backwards.
                    l.standAloneAdjust(stand_alone);
                    var b = beg + 1;
                    var e = end;
                    trim(data, &b, &e);
                    if (l.stack[l.index].open_sections == 0) return error.ClosureMismatch;
                    const insts = l.insts[0..l.inst_len];
                    var pos: u32 = @intCast(insts.len);
                    var nested: u32 = 0;
                    while (pos > 0) {
                        pos -= 1;
                        switch (insts[pos].op) {
                            .section_end => nested += 1,
                            .section_start, .section_start_inv => {
                                if (nested > 0) {
                                    nested -= 1;
                                    continue;
                                }
                                if (insts[pos].name_pos == NO_NAME or
                                    insts[pos].name_len != e - b or
                                    !std.mem.eql(u8, data[b..e], data[insts[pos].name_pos..][0..insts[pos].name_len]))
                                {
                                    return error.ClosureMismatch;
                                }
                                insts[pos].end = @intCast(insts.len);
                                insts[pos].len = tag_start - (insts[pos].name_pos + insts[pos].offset);
                                try l.pushInstruction(.{
                                    .op = .section_end,
                                    .end = insts[pos].end,
                                    .len = insts[pos].len,
                                    .name_pos = insts[pos].name_pos,
                                    .name_len = insts[pos].name_len,
                                    .offset = insts[pos].offset,
                                });
                                l.stack[l.index].open_sections -= 1;
                                return;
                            },
                            else => {},
                        }
                    }
                    return error.ClosureMismatch;
                },
                else => |sigil| {
                    // Argument: {{name}} (escaped), {{{name}}}, {{& name}}
                    // (unescaped); ':' and '<' sigils are skipped but escaped.
                    var b = beg;
                    var e = end;
                    const escaped = sigil != '{' and sigil != '&';
                    if (sigil == '{') {
                        // A '}}}' closing: consume the extra '}'.
                        const frame = &l.stack[l.index];
                        if (frame.data_pos < frame.data_end and
                            data[frame.data_pos] == '}' and
                            f.del_end[0] == '}' and f.del_end[f.del_end_len - 1] == '}')
                        {
                            frame.data_pos += 1;
                        }
                    }
                    if (sigil == '{' or sigil == '&' or sigil == ':' or sigil == '<') b += 1;
                    trim(data, &b, &e);
                    // With custom delimiters the closing '}' of '{name}' is part
                    // of the tag body (with '}}' delimiters it was consumed above).
                    if (sigil == '{' and e > b and data[e - 1] == '}') {
                        e -= 1;
                        trim(data, &b, &e);
                    }
                    // Classify once, at parse time, so the render hot path never
                    // scans for '.': a non-empty name with no dot is a simple key
                    // (fast field lookup by hash); everything else — dotted, the
                    // implicit `{{.}}`, and empty tags — is a `write_path`.
                    if (e > b and std.mem.indexOfScalar(u8, data[b..e], '.') == null) {
                        try l.pushInstruction(.{
                            .op = if (escaped) .write_arg else .write_arg_unescaped,
                            .name_pos = b,
                            .name_len = e - b,
                            // `offset` is unused by simple-key instructions; carry
                            // the tag name's hash for the renderer's fast lookup.
                            .offset = context.fieldHash(data[b..e]),
                        });
                    } else {
                        const segs = l.appendPathSegs(b, e);
                        try l.pushInstruction(.{
                            .op = if (escaped) .write_path else .write_path_unescaped,
                            .name_pos = b,
                            .name_len = e - b,
                            .offset = segs.start,
                            .len = segs.count,
                        });
                    }
                },
            }
        }

        /// Finishes the top template: validates section closure, patches the
        /// template's `section_start`, and appends its `section_end`.
        fn closeTemplate(l: *Self) LoadError!void {
            const f = l.stack[l.index];
            if (f.open_sections != 0) return error.ClosureMismatch;
            var trailing_padding_write = false;
            if (l.inst_len > 0 and l.insts[l.inst_len - 1].op == .padding_write) {
                l.inst_len -= 1;
                trailing_padding_write = true;
            }
            const seg = l.segs[f.segment];
            l.insts[seg.inst_start].end = l.inst_len;
            try l.pushInstruction(.{ .op = .section_end });
            if (l.padding != 0 and l.padding + 1 == seg.inst_start) {
                l.padding = l.insts[l.padding].end;
                try l.pushInstruction(.{ .op = .padding_pop });
            }
            if (trailing_padding_write)
                try l.pushInstruction(.{ .op = .padding_write });
        }
    };
}

fn partialsLen(comptime partials: []const Partial) usize {
    var n: usize = 0;
    for (partials) |p| n += p.data.len;
    return n;
}

/// Compiles a template at comptime into a const-backed `Template`. Supports
/// in-memory `data` and in-memory `partials` only; `filename` names the
/// (virtual) root so recursive partials that reference it resolve. Any parse
/// failure becomes a `@compileError`.
pub fn parse(
    comptime data: []const u8,
    comptime filename: []const u8,
    comptime partials: []const Partial,
) Template {
    // `insts`/`bytes` below are standalone container-level `const` array
    // declarations, so taking their address yields a static, runtime-usable
    // pointer (the same promotion the renderer relies on). Values placed in
    // *struct fields* would instead become comptime fields, whose addresses
    // are not available at runtime — hence `raw` is only read (to size and
    // fill the two array decls), never addressed.
    const S = struct {
        const raw = blk: {
            const total = data.len + partialsLen(partials);
            const data_cap = total;
            const inst_cap = 2 * total + 4 * (partials.len + 1) + 2 * NESTING_LIMIT;
            const seg_cap = partials.len + 1;
            @setEvalBranchQuota(@max(100_000, total * 200));

            var l: ComptimeLoader(inst_cap, data_cap, seg_cap) = .{ .partials = partials };
            l.loadData(filename, data) catch |e| @compileError("mustache comptime load: " ++ @errorName(e));
            l.parse() catch |e| @compileError("mustache comptime parse: " ++ @errorName(e));
            break :blk .{
                .insts = l.insts,
                .il = l.inst_len,
                .bytes = l.bytes,
                .dl = l.data_len,
                .path_segs = l.path_segs,
                .psl = l.path_seg_len,
            };
        };
        const insts = blk: {
            var t: [raw.il]Instruction = undefined;
            for (0..raw.il) |i| t[i] = raw.insts[i];
            break :blk t;
        };
        const bytes = blk: {
            var t: [raw.dl]u8 = undefined;
            for (0..raw.dl) |i| t[i] = raw.bytes[i];
            break :blk t;
        };
        const path_segs = blk: {
            var t: [raw.psl]PathSeg = undefined;
            for (0..raw.psl) |i| t[i] = raw.path_segs[i];
            break :blk t;
        };
    };
    return .{
        .instructions = &S.insts,
        .data = &S.bytes,
        .path_segs = &S.path_segs,
        .size_hint = parser.sizeHint(&S.insts),
    };
}
