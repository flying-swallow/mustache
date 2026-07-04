//! Mustache template compiler.
//!
//! Port of facil.io's `mustache_parser.h` load phase (MIT, Boaz Segev
//! 2018-2019). A template (and any partial templates it references) is
//! compiled into a flat instruction array plus a data buffer holding the
//! concatenated template texts. Rendering is a separate phase implemented in
//! `render.zig`.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Maximum template/section nesting depth (same limit as the C parser).
pub const NESTING_LIMIT = 82;

/// Delimiters may be at most 4 bytes long (the C limit of 5 included a NUL).
pub const DELIMITER_MAX = 4;

/// Sentinel for instructions that carry no name. The C implementation used
/// `name_pos == 0`, which was unambiguous only because position 0 always fell
/// inside a data-segment header; our data buffer holds raw template text, so
/// an explicit sentinel is needed.
pub const NO_NAME = std.math.maxInt(u32);

pub const Op = enum(u8) {
    write_text,
    write_arg,
    write_arg_unescaped,
    section_start,
    section_start_inv,
    section_end,
    section_goto,
    padding_push,
    padding_pop,
    padding_write,
};

pub const Instruction = struct {
    op: Op,
    /// Section instructions: index of the matching `section_end`.
    /// `section_goto`: its own index. `padding_push`: previous padding head.
    end: u32 = 0,
    /// Section instructions: byte length of the section body.
    /// `section_goto`: instruction index of the target `section_start`.
    len: u32 = 0,
    /// Offset into `Template.data` of the name / text / padding bytes.
    name_pos: u32 = NO_NAME,
    /// Length of the name / text / padding bytes.
    name_len: u32 = 0,
    /// Sections: distance from the name start to the section body start.
    offset: u32 = 0,
};

/// A compiled template: an instruction array plus the concatenated text of
/// the root template and every partial it pulled in.
pub const Template = struct {
    instructions: []const Instruction,
    data: []const u8,

    pub fn deinit(self: *Template, allocator: Allocator) void {
        allocator.free(self.instructions);
        allocator.free(self.data);
        self.* = undefined;
    }
};

/// A named in-memory partial template, looked up before the filesystem.
pub const Partial = struct {
    name: []const u8,
    data: []const u8,
};

pub const LoadError = error{
    TooDeep,
    ClosureMismatch,
    FileNotFound,
    FileTooBig,
    FileNameTooLong,
    FileNameTooShort,
    DelimiterTooLong,
} || Allocator.Error;

/// Compiles a template. `data` takes precedence over `filename` as the
/// template's contents; `filename` then only names the template (enabling
/// recursive partials that reference the root). Without `data`, the template
/// is read from `filename`, which requires `io`. Partials are resolved
/// against `partials` first, then loaded from the filesystem relative to the
/// including template's directory (which requires `io`); unresolved partials
/// render as the empty string (per the mustache spec).
pub fn load(
    gpa: Allocator,
    io: ?std.Io,
    filename: ?[]const u8,
    data: ?[]const u8,
    partials: []const Partial,
) LoadError!Template {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var loader: Loader = .{
        .gpa = gpa,
        .arena = arena_state.allocator(),
        .io = io,
        .partials = partials,
    };
    defer {
        loader.instructions.deinit(gpa);
        loader.data.deinit(gpa);
        loader.segments.deinit(gpa);
    }

    if (data) |d| {
        try loader.loadData(filename orelse "", d);
    } else {
        _ = try loader.loadFile(filename orelse return error.FileNameTooShort);
    }

    try loader.parse();

    const instructions = try loader.instructions.toOwnedSlice(gpa);
    errdefer gpa.free(instructions);
    return .{
        .instructions = instructions,
        .data = try loader.data.toOwnedSlice(gpa),
    };
}

/// One template on the loader stack, parsed LIFO: encountering a partial
/// pushes a frame and parsing resumes with the partial's text; when it
/// completes, the including template continues where it left off.
pub const Frame = struct {
    /// Index into `Loader.segments`.
    segment: u32,
    data_start: u32,
    data_pos: u32,
    data_end: u32,
    /// Sections opened in this template that still need their closing tag.
    open_sections: u16,
    del_start: [DELIMITER_MAX]u8,
    del_start_len: u8,
    del_end: [DELIMITER_MAX]u8,
    del_end_len: u8,
};

/// One loaded template file/blob; used to resolve relative partial paths and
/// to reuse already-compiled templates (via `section_goto`).
pub const Segment = struct {
    /// Resolved path (or the caller-provided name), arena-owned.
    filename: []const u8,
    /// Length of the directory prefix of `filename`, including the '/'.
    path_len: u16,
    /// Instruction index of this template's `section_start`.
    inst_start: u32,
};

const Loader = struct {
    gpa: Allocator,
    /// Scratch memory that only lives for the duration of `load`.
    arena: Allocator,
    io: ?std.Io,
    partials: []const Partial = &.{},
    instructions: std.ArrayList(Instruction) = .empty,
    data: std.ArrayList(u8) = .empty,
    segments: std.ArrayList(Segment) = .empty,
    stack: [NESTING_LIMIT]Frame = undefined,
    /// Top of `stack`; 0 means empty (frame 0 is never used).
    index: u16 = 0,
    /// Instruction index of the currently active `padding_push` (0 = none;
    /// instruction 0 is always a `section_start`, so 0 is unambiguous).
    padding: u32 = 0,

    fn pushInstruction(l: *Loader, inst: Instruction) LoadError!void {
        if (l.instructions.items.len >= std.math.maxInt(i32)) return error.TooDeep;
        try l.instructions.append(l.gpa, inst);
    }

    /// Emits text as `write_text` instructions, splitting at newlines and
    /// interleaving `padding_write` so that active padding (partial
    /// indentation) is repeated on every line at render time.
    fn pushTextInstructions(l: *Loader, pos_arg: u32, len_arg: u32) LoadError!void {
        var pos = pos_arg;
        var len = len_arg;
        while (len > 0) {
            const nl = std.mem.indexOfScalarPos(u8, l.data.items[0 .. pos + len], pos, '\n') orelse break;
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
    /// frame for it. `name` must not alias `l.data` (which may grow here).
    fn loadData(l: *Loader, name: []const u8, contents: []const u8) LoadError!void {
        if (l.data.items.len + contents.len > std.math.maxInt(u32)) return error.TooDeep;
        var path_len: usize = name.len;
        while (path_len > 0) {
            path_len -= 1;
            if (name[path_len] == '/' or name[path_len] == '\\') {
                path_len += 1;
                break;
            }
        }
        try l.segments.append(l.gpa, .{
            .filename = try l.arena.dupe(u8, name),
            .path_len = @intCast(path_len),
            .inst_start = @intCast(l.instructions.items.len),
        });
        const data_start: u32 = @intCast(l.data.items.len);
        try l.data.appendSlice(l.gpa, contents);
        try l.pushInstruction(.{ .op = .section_start });
        if (l.index + 1 >= NESTING_LIMIT) return error.TooDeep;
        l.index += 1;
        l.stack[l.index] = .{
            .segment = @intCast(l.segments.items.len - 1),
            .data_start = data_start,
            .data_pos = data_start,
            .data_end = @intCast(l.data.items.len),
            .open_sections = 0,
            .del_start = .{ '{', '{', 0, 0 },
            .del_start_len = 2,
            .del_end = .{ '}', '}', 0, 0 },
            .del_end_len = 2,
        };
    }

    /// Returns the `section_start` instruction index of an already-loaded
    /// template, or null.
    fn fileInstStart(l: *Loader, path: []const u8) ?u32 {
        for (l.segments.items) |seg| {
            if (std.mem.eql(u8, seg.filename, path)) return seg.inst_start;
        }
        return null;
    }

    /// Loads a partial template by name. In-memory partials are tried first;
    /// the filesystem search order matches the C parser: walk the loader
    /// stack from the including template outwards, trying each template's
    /// directory with the exact name and then with a ".mustache" extension.
    /// Returns the number of content bytes loaded (0 for empty files and for
    /// templates reused via `section_goto`).
    fn loadFile(l: *Loader, name_arg: []const u8) LoadError!usize {
        if (name_arg.len == 0) return error.FileNameTooShort;
        if (name_arg.len >= 8192) return error.FileNameTooLong;
        // The name may point into l.data, which grows below.
        const name = try l.arena.dupe(u8, name_arg);

        for (l.partials) |p| {
            if (!std.mem.eql(u8, p.name, name)) continue;
            if (p.data.len == 0) return 0;
            if (l.fileInstStart(name)) |inst_start| {
                // Already compiled: jump to it instead of recompiling.
                try l.pushInstruction(.{
                    .op = .section_goto,
                    .len = inst_start,
                    .end = @intCast(l.instructions.items.len),
                });
                return 0;
            }
            try l.loadData(name, p.data);
            return p.data.len;
        }

        // Collect the directory prefixes to search, deduplicating repeats of
        // the previously tried one (as the C parser does).
        var dirs: std.ArrayList([]const u8) = .empty;
        if (l.index == 0) {
            try dirs.append(l.arena, "");
        } else {
            var i: u16 = l.index;
            while (i >= 1) : (i -= 1) {
                const seg = l.segments.items[l.stack[i].segment];
                const dir = seg.filename[0..seg.path_len];
                if (dirs.items.len > 0 and std.mem.eql(u8, dirs.items[dirs.items.len - 1], dir))
                    continue;
                try dirs.append(l.arena, dir);
                // A cwd-relative template makes further walking pointless.
                if (dir.len == 0) break;
            }
        }

        const found: ?struct { path: []u8, size: u64 } = blk: {
            const io = l.io orelse break :blk null;
            for (dirs.items) |dir| {
                for ([2][]const u8{ "", ".mustache" }) |ext| {
                    const path = try std.mem.concat(l.arena, u8, &.{ dir, name, ext });
                    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch continue;
                    if (stat.kind != .file) continue;
                    break :blk .{ .path = path, .size = stat.size };
                }
            }
            break :blk null;
        };

        if (found) |file| {
            const io = l.io.?;
            if (file.size >= std.math.maxInt(i32)) return error.FileTooBig;
            if (file.size == 0) return 0;
            if (l.fileInstStart(file.path)) |inst_start| {
                // Already compiled: jump to it instead of recompiling.
                try l.pushInstruction(.{
                    .op = .section_goto,
                    .len = inst_start,
                    .end = @intCast(l.instructions.items.len),
                });
                return 0;
            }
            const contents = std.Io.Dir.cwd().readFileAlloc(
                io,
                file.path,
                l.arena,
                .limited(std.math.maxInt(i32)),
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.StreamTooLong => return error.FileTooBig,
                else => return error.FileNotFound,
            };
            try l.loadData(file.path, contents);
            return contents.len;
        }

        // Not on disk: the name may refer to the (virtual) root template,
        // which enables recursive templates for in-memory data.
        if (l.segments.items.len > 0) {
            const root = l.segments.items[0];
            if (std.mem.eql(u8, root.filename, name)) {
                try l.pushInstruction(.{
                    .op = .section_goto,
                    .len = 0,
                    .end = @intCast(l.instructions.items.len),
                });
                return 0;
            }
        }
        return error.FileNotFound;
    }

    /// For a standalone tag (a tag alone on its line): skips the newline
    /// that follows it and trims the line's leading whitespace from the
    /// preceding `write_text` instruction. `stand_alone` is
    /// `(padding_len << 1) | 1`, or 0 when the tag is not standalone.
    fn standAloneAdjust(l: *Loader, stand_alone: u32) void {
        if (stand_alone == 0) return;
        const f = &l.stack[l.index];
        if (f.data_pos < f.data_end and l.data.items[f.data_pos] == '\r') f.data_pos += 1;
        f.data_pos += 1;
        const pad_len = stand_alone >> 1;
        if (l.instructions.items.len == 0) return;
        const last = &l.instructions.items[l.instructions.items.len - 1];
        if (last.op != .write_text) return;
        if (last.name_len <= pad_len) {
            _ = l.instructions.pop();
        } else {
            last.name_len -= pad_len;
        }
    }

    /// Parses every template on the loader stack until it is empty.
    fn parse(l: *Loader) LoadError!void {
        while (l.index != 0) {
            while (l.stack[l.index].data_pos < l.stack[l.index].data_end) {
                try l.parseTag();
            }
            try l.closeTemplate();
            l.index -= 1;
        }
    }

    /// Parses text up to and including the next tag of the top template.
    fn parseTag(l: *Loader) LoadError!void {
        const data = l.data.items;
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

        // Standalone tag detection: nothing but the (optional) newline after
        // the tag, and only whitespace between the tag and the line start.
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
            // Empty tag; emit an (unresolvable) empty-named argument.
            try l.pushInstruction(.{ .op = .write_arg, .name_pos = beg, .name_len = 0 });
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
                    l.padding = @intCast(l.instructions.items.len - 1);
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
                const insts = l.instructions.items;
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
                try l.pushInstruction(.{
                    .op = if (escaped) .write_arg else .write_arg_unescaped,
                    .name_pos = b,
                    .name_len = e - b,
                });
            },
        }
    }

    /// Finishes the top template: validates section closure, patches the
    /// template's `section_start`, and appends its `section_end` (plus any
    /// padding bookkeeping around partial boundaries).
    fn closeTemplate(l: *Loader) LoadError!void {
        const f = l.stack[l.index];
        if (f.open_sections != 0) return error.ClosureMismatch;
        // A trailing padding_write must run after the section closes (with
        // the including template's padding), so move it past the closure.
        var trailing_padding_write = false;
        if (l.instructions.items.len > 0 and
            l.instructions.items[l.instructions.items.len - 1].op == .padding_write)
        {
            _ = l.instructions.pop();
            trailing_padding_write = true;
        }
        const seg = l.segments.items[f.segment];
        l.instructions.items[seg.inst_start].end = @intCast(l.instructions.items.len);
        try l.pushInstruction(.{ .op = .section_end });
        if (l.padding != 0 and l.padding + 1 == seg.inst_start) {
            l.padding = l.instructions.items[l.padding].end;
            try l.pushInstruction(.{ .op = .padding_pop });
        }
        if (trailing_padding_write)
            try l.pushInstruction(.{ .op = .padding_write });
    }
};

/// Trims whitespace from both ends of `data[b..e]` in place. A U+FEFF (BOM)
/// also counts as whitespace, matching JavaScript's `\s` (and therefore
/// mustache.js's tag-name trimming).
pub fn trim(data: []const u8, b: *u32, e: *u32) void {
    const bom = "\u{FEFF}";
    while (b.* < e.*) {
        if (std.ascii.isWhitespace(data[b.*])) {
            b.* += 1;
        } else if (e.* - b.* >= bom.len and std.mem.eql(u8, data[b.*..][0..bom.len], bom)) {
            b.* += bom.len;
        } else break;
    }
    while (e.* > b.*) {
        if (std.ascii.isWhitespace(data[e.* - 1])) {
            e.* -= 1;
        } else if (e.* - b.* >= bom.len and std.mem.eql(u8, data[e.* - bom.len ..][0..bom.len], bom)) {
            e.* -= bom.len;
        } else break;
    }
}
