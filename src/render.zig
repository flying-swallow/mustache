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
    var r: Renderer = .{
        .insts = template.instructions,
        .data = template.data,
        .path_segs = template.path_segs,
        .out = out,
    };
    const len: u32 = @intCast(template.instructions.len);
    const T = @TypeOf(data);
    if (comptime staticEligible(T)) {
        // Monomorphic fast path: dispatch field writes directly against the
        // concrete root type, no `Context` vtable. `Parents` starts empty.
        try r.renderStatic(T, &data, @TypeOf(.{}), .{}, 0, len, 0);
    } else {
        const root: Context = if (comptime context.isComptimeOnly(T))
            comptime context.comptimeValue(data)
        else
            Context.init(&data);
        try r.renderErased(&.{root}, 0, len, false);
    }
}

/// Comptime eligibility for the monomorphic static render path: the root value
/// must be a concrete (non-tuple) struct we can scan field-by-field. Everything
/// else (bare strings/ints/arrays, comptime-only roots, tuples) renders through
/// the type-erased VM.
fn staticEligible(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| !info.is_tuple,
        else => false,
    };
}

/// Cap on the statically-tracked ancestor chain. Every specialized section
/// instantiates `renderStatic` for a longer `(Ctx, Parents)` combination, and
/// recursive partials over recursive data types (`Node{children: []Node}`)
/// would otherwise instantiate without bound; past the cap, sections fall
/// back to the type-erased VM (which handles recursion via its frame stack).
const STATIC_PARENTS_MAX = 8;

/// Whether a section element of type `Child` renders identically through the
/// static path (`renderStatic` over `&items[i]`) and the VM
/// (`Context.init(&items[i])`): structs and scalars do; optionals, unions and
/// pointers are unwrapped per element by `Context.init`, so they stay erased.
fn elementStatic(comptime Child: type) bool {
    return switch (@typeInfo(Child)) {
        .@"struct" => |info| !info.is_tuple,
        .bool, .int, .float, .@"enum", .error_set => true,
        else => false,
    };
}

/// Result of trying to render a named section statically. `handled` includes
/// falsy values that render nothing; `fallback` means the value was found but
/// its iteration semantics live in the erased contexts; `miss` means the
/// name does not resolve here.
const SectionOutcome = enum { handled, fallback, miss };

const Renderer = struct {
    insts: []const Instruction,
    data: []const u8,
    path_segs: []const parser.PathSeg,
    out: *std.Io.Writer,
    frames: [parser.NESTING_LIMIT]RenderFrame = undefined,
    index: usize = 0,
    /// Instruction index of the active `padding_push` (0 = none).
    padding: u32 = 0,

    /// The type-erased instruction VM. Renders instructions `[start, end)`
    /// with the frame stack seeded from `seeds` (root context first, current
    /// context last), so a field miss walks up through every seeded ancestor.
    /// This is the correctness baseline; the monomorphic static renderer falls
    /// back here for anything it does not specialize.
    fn renderErased(r: *Renderer, seeds: []const Context, start: u32, end: u32, stop_at_base: bool) Error!void {
        const insts = r.insts;
        const bytes = r.data;
        for (seeds, 0..) |seed, i| {
            r.frames[i] = .{
                .context = seed,
                .section = null,
                .start = start,
                .end = end,
                .idx = 0,
                .count = 0,
            };
        }
        // The seeded base level. When rendering a single fallen-back section
        // (`stop_at_base`, `start` at its `section_start`, `end` the full
        // instruction count), execution completes when the frame stack pops
        // back to `base` — a `section_goto` (recursive partial) can roam past
        // the section's own end, so completion is tracked by frame level, not
        // `pos`.
        const base = seeds.len - 1;
        r.index = base;

        var pos: u32 = start;
        while (pos < end) : (pos += 1) {
            const inst = insts[pos];
            switch (inst.op) {
                .write_text => try r.out.writeAll(bytes[inst.name_pos..][0..inst.name_len]),
                .write_arg => try r.writeArg(inst.offset, true),
                .write_arg_unescaped => try r.writeArg(inst.offset, false),
                .write_path => if (r.findValuePath(inst)) |v| try v.write(r.out, true),
                .write_path_unescaped => if (r.findValuePath(inst)) |v| try v.write(r.out, false),
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
                        frame.section = r.findValuePath(inst);
                        // Truthiness matches mustache.js: '', 0 and NaN are falsy.
                        var count: usize = if (frame.section) |v| v.count() else 0;
                        if (inst.op == .section_start_inv) count = @intFromBool(count == 0);
                        frame.count = count;
                    }
                    pos = r.sectionEnd();
                    if (stop_at_base and r.index == base) return;
                },
                .section_end => {
                    pos = r.sectionEnd();
                    if (stop_at_base and r.index == base) return;
                },
                .padding_push => r.padding = pos,
                .padding_pop => r.padding = insts[r.padding].end,
                .padding_write => try r.writePadding(),
            }
        }
    }

    /// Monomorphic render of instructions `[start, end)` against a
    /// comptime-known context type `Ctx`. Field writes and same-context
    /// wrappers / partial jumps dispatch statically (no vtable); anything not
    /// yet specialized — named data sections, dotted / implicit names — falls
    /// back to `renderErased`. `Parents` is a tuple of typed ancestor pointers
    /// (root first, immediate parent last); a field missing from `Ctx` is
    /// resolved there.
    fn renderStatic(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        start: u32,
        end: u32,
        depth: u16,
    ) Error!void {
        if (depth >= parser.NESTING_LIMIT) return error.TooDeep;
        const insts = r.insts;
        const bytes = r.data;
        var pos: u32 = start;
        while (pos < end) : (pos += 1) {
            const inst = insts[pos];
            switch (inst.op) {
                .write_text => try r.out.writeAll(bytes[inst.name_pos..][0..inst.name_len]),
                .write_arg => try r.renderField(Ctx, ctx, Parents, parents, inst.offset, true),
                .write_arg_unescaped => try r.renderField(Ctx, ctx, Parents, parents, inst.offset, false),
                .write_path => try r.renderPath(Ctx, ctx, Parents, parents, inst, true),
                .write_path_unescaped => try r.renderPath(Ctx, ctx, Parents, parents, inst, false),
                .section_goto => {
                    // Partial include: jump to the reused range's body, same
                    // context. `inst.len` is the target's (unnamed)
                    // `section_start`; execution resumes after this goto.
                    const target = inst.len;
                    try r.renderStatic(Ctx, ctx, Parents, parents, target + 1, insts[target].end, depth + 1);
                },
                .section_start, .section_start_inv => {
                    if (inst.name_pos == parser.NO_NAME) {
                        // Unnamed wrapper (template / partial body): same
                        // context, runs exactly once.
                        try r.renderStatic(Ctx, ctx, Parents, parents, pos + 1, inst.end, depth + 1);
                    } else if (!try r.sectionStatic(Ctx, ctx, Parents, parents, inst, pos, depth)) {
                        // Not statically specializable -> VM.
                        try r.fallbackSection(Ctx, ctx, Parents, parents, pos);
                    }
                    pos = inst.end;
                },
                .section_end => {},
                .padding_push => r.padding = pos,
                .padding_pop => r.padding = insts[r.padding].end,
                .padding_write => try r.writePadding(),
            }
        }
    }

    /// Resolves a simple key (classified at parse time — never dotted,
    /// implicit or empty; `hash` is its precomputed `fieldHash`) against
    /// `Ctx`, then the `Parents` chain nearest first, and writes it through
    /// direct `context.writeField` calls — no vtable.
    fn renderField(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        hash: u32,
        escape: bool,
    ) std.Io.Writer.Error!void {
        if (try context.writeField(Ctx, ctx, hash, r.out, escape)) return;
        comptime var k = @typeInfo(Parents).@"struct".field_types.len;
        inline while (k > 0) {
            k -= 1;
            const p = parents[k];
            if (try context.writeField(@TypeOf(p.*), p, hash, r.out, escape)) return;
        }
        // Total miss: mustache renders nothing.
    }

    /// Static handler for a `write_path` instruction. `count == 0` is the
    /// implicit iterator `{{.}}` (writes the current context, which for a struct
    /// is nothing) or an empty tag (nothing); otherwise it dispatches the
    /// precomputed segments through the recursive `writePath`.
    fn renderPath(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        inst: Instruction,
        escape: bool,
    ) std.Io.Writer.Error!void {
        const count = inst.len;
        if (count == 0) {
            if (inst.name_len == 1) try Context.init(ctx).write(r.out, escape); // `{{.}}`
            return;
        }
        const segs = r.path_segs[inst.offset..][0..count];
        _ = try r.writePath(Ctx, ctx, Parents, parents, segs, 0, escape);
    }

    /// Resolves `segs[seg_index..]` against `Ctx` by precomputed hash — no
    /// '.'-scan, no string search beyond the collision-confirming compare —
    /// descending statically into concrete struct fields. Returns true once a
    /// context containing the head segment is found (the chain then commits: a
    /// broken tail writes nothing but does NOT fall back to `Parents`). The head
    /// segment (`seg_index == 0`) also walks the `Parents` chain nearest-first.
    fn writePath(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        segs: []const parser.PathSeg,
        seg_index: usize,
        escape: bool,
    ) std.Io.Writer.Error!bool {
        const seg = segs[seg_index];
        const name = r.data[seg.pos..][0..seg.len];
        const last = seg_index + 1 == segs.len;

        if (comptime staticEligible(Ctx)) {
            const s = @typeInfo(Ctx).@"struct";
            inline for (s.field_names, s.field_types, s.field_attrs) |fname, F, attrs| {
                if (comptime F != void) {
                    if (seg.hash == (comptime context.fieldHash(fname)) and std.mem.eql(u8, name, fname)) {
                        if (last) {
                            // Leaf/field write reuses `writeField`'s exact logic.
                            _ = try context.writeField(Ctx, ctx, seg.hash, r.out, escape);
                        } else if (comptime !attrs.@"comptime" and s.layout != .@"packed" and staticEligible(F)) {
                            // Descend statically into a concrete struct field.
                            _ = try r.writePath(F, &@field(ctx.*, fname), @TypeOf(.{}), .{}, segs, seg_index + 1, escape);
                        } else {
                            // Optional / union / pointer / slice / packed /
                            // comptime field: resolve to a Context and finish the
                            // tail through the type-erased path.
                            if (Context.init(ctx).getKeyHash(seg.hash)) |fc|
                                _ = try r.writePathErasedTail(fc, segs, seg_index + 1, escape);
                        }
                        return true; // head matched -> committed
                    }
                }
            }
        }

        // Not found in `Ctx`. Only the head segment falls back to parents.
        if (seg_index == 0) {
            comptime var k = @typeInfo(Parents).@"struct".field_types.len;
            inline while (k > 0) {
                k -= 1;
                const p = parents[k];
                if (try r.writePath(@TypeOf(p.*), p, @TypeOf(.{}), .{}, segs, 0, escape)) return true;
            }
        }
        return false;
    }

    /// Finishes a dotted tail against an already-resolved `Context` (used when a
    /// segment lands on an optional/union/pointer/slice/packed/comptime field
    /// the static path cannot descend into). Strict per segment.
    fn writePathErasedTail(r: *Renderer, start: Context, segs: []const parser.PathSeg, seg_index: usize, escape: bool) std.Io.Writer.Error!bool {
        var current = start;
        for (segs[seg_index..]) |seg| {
            current = current.getKeyHash(seg.hash) orelse return false;
        }
        try current.write(r.out, escape);
        return true;
    }

    /// Statically renders the named section at instruction `pos`, if the
    /// section value resolves to a comptime-known field whose iteration
    /// semantics the static path reproduces (structs, scalars, slices/arrays
    /// of those, optionals and pointers thereof). Returns false when the VM
    /// must take over instead. The head segment resolves against the current
    /// context, then the ancestor chain nearest-first — the same scope walk
    /// the VM performs over its frame stack.
    fn sectionStatic(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        inst: Instruction,
        pos: u32,
        depth: u16,
    ) Error!bool {
        // The implicit iterator `{{#.}}` (and empty names) iterate the
        // current context itself -> VM.
        if (inst.len == 0) return false;
        const segs = r.path_segs[inst.offset..][0..inst.len];
        const inverted = inst.op == .section_start_inv;
        var outcome = try r.sectionResolve(Ctx, ctx, Ctx, ctx, Parents, parents, segs, 0, inverted, pos + 1, inst.end, depth);
        if (outcome == .miss) {
            comptime var k = @typeInfo(Parents).@"struct".field_types.len;
            inline while (k > 0) {
                k -= 1;
                const p = parents[k];
                outcome = try r.sectionResolve(@TypeOf(p.*), p, Ctx, ctx, Parents, parents, segs, 0, inverted, pos + 1, inst.end, depth);
                if (outcome != .miss) break;
            }
        }
        switch (outcome) {
            .handled => return true,
            .fallback => return false,
            .miss => {
                // A missing (or broken dotted) name is falsy: the inverted
                // body runs once with the current context kept, exactly as
                // the VM keeps the parent frame's context.
                if (inverted) try r.renderStatic(Ctx, ctx, Parents, parents, pos + 1, inst.end, depth + 1);
                return true;
            },
        }
    }

    /// Resolves `segs[seg_index..]` against the comptime-known `LookCtx`
    /// (mirroring `writePath`: hash-dispatched field scan, static descent
    /// into concrete struct fields) and hands the resolved leaf to
    /// `sectionValue`. `Ctx`/`Parents` stay the section's original scope —
    /// the VM's section frame sits on top of the frame stack as it was, not
    /// on the object the name resolved through.
    fn sectionResolve(
        r: *Renderer,
        comptime LookCtx: type,
        look: *const LookCtx,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        segs: []const parser.PathSeg,
        seg_index: usize,
        inverted: bool,
        body_start: u32,
        body_end: u32,
        depth: u16,
    ) Error!SectionOutcome {
        if (comptime staticEligible(LookCtx)) {
            const seg = segs[seg_index];
            const name = r.data[seg.pos..][0..seg.len];
            const last = seg_index + 1 == segs.len;
            const s = @typeInfo(LookCtx).@"struct";
            inline for (s.field_names, s.field_types, s.field_attrs) |fname, F, attrs| {
                if (comptime F != void) {
                    if (seg.hash == (comptime context.fieldHash(fname)) and std.mem.eql(u8, name, fname)) {
                        // Comptime and packed fields are not addressable -> VM.
                        if (comptime attrs.@"comptime" or s.layout == .@"packed") return .fallback;
                        if (last)
                            return r.sectionValue(F, &@field(look.*, fname), Ctx, ctx, Parents, parents, inverted, body_start, body_end, depth);
                        if (comptime staticEligible(F))
                            return r.sectionResolve(F, &@field(look.*, fname), Ctx, ctx, Parents, parents, segs, seg_index + 1, inverted, body_start, body_end, depth);
                        // Optional/pointer/... interior segment -> VM.
                        return .fallback;
                    }
                }
            }
        }
        return .miss;
    }

    /// Renders a named section over the statically-resolved value `v`, or
    /// reports that the VM must take over. Truthiness, iteration counts and
    /// element contexts mirror the type-erased contexts exactly: optionals
    /// and pointers-to-one unwrap (like `Context.init`), objects and truthy
    /// scalars run the body once with themselves as context (falsy inverted
    /// scalars too — the erased `element` hands back the value itself), and
    /// arrays iterate elementwise.
    fn sectionValue(
        r: *Renderer,
        comptime F: type,
        v: *const F,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        inverted: bool,
        body_start: u32,
        body_end: u32,
        depth: u16,
    ) Error!SectionOutcome {
        if (comptime @typeInfo(Parents).@"struct".field_types.len >= STATIC_PARENTS_MAX)
            return .fallback;
        switch (@typeInfo(F)) {
            .optional => |o| {
                if (v.*) |*payload|
                    return r.sectionValue(o.child, payload, Ctx, ctx, Parents, parents, inverted, body_start, body_end, depth);
                // Null is found-but-falsy; its inverted body runs with the
                // null context, which has no static counterpart -> VM.
                return if (inverted) .fallback else .handled;
            },
            .pointer => |p| switch (p.size) {
                .one => return r.sectionValue(p.child, v.*, Ctx, ctx, Parents, parents, inverted, body_start, body_end, depth),
                .slice => return r.sectionSlice(p.child, v.*, Ctx, ctx, Parents, parents, inverted, body_start, body_end, depth),
                else => return .fallback,
            },
            .array => |a| {
                if (comptime a.child == u8) return .fallback; // string/bytes semantics
                return r.sectionSlice(a.child, v, Ctx, ctx, Parents, parents, inverted, body_start, body_end, depth);
            },
            .@"struct" => |info| {
                if (comptime info.is_tuple) return .fallback;
                // An object is always truthy; the body runs once with it as
                // the context.
                if (!inverted) {
                    const chain = parents ++ .{ctx};
                    try r.renderStatic(F, v, @TypeOf(chain), chain, body_start, body_end, depth + 1);
                }
                return .handled;
            },
            .bool, .int, .float, .@"enum", .error_set => {
                const truthy = switch (@typeInfo(F)) {
                    .bool => v.*,
                    .int => v.* != 0,
                    .float => v.* != 0 and !std.math.isNan(v.*),
                    .@"enum" => @intFromEnum(v.*) != 0,
                    .error_set => true,
                    else => comptime unreachable,
                };
                if (truthy != inverted) {
                    const chain = parents ++ .{ctx};
                    try r.renderStatic(F, v, @TypeOf(chain), chain, body_start, body_end, depth + 1);
                }
                return .handled;
            },
            // Strings/bytes, tuples, unions, vectors: iteration/unwrap
            // semantics live in the erased contexts -> VM.
            else => return .fallback,
        }
    }

    /// Elementwise static render of a section over `items`. Falsy (empty)
    /// arrays keep the current context for the inverted body, exactly as the
    /// VM does when `element` returns null.
    fn sectionSlice(
        r: *Renderer,
        comptime Child: type,
        items: []const Child,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        inverted: bool,
        body_start: u32,
        body_end: u32,
        depth: u16,
    ) Error!SectionOutcome {
        if (comptime Child == u8 or !elementStatic(Child)) return .fallback;
        if (inverted) {
            if (items.len == 0)
                try r.renderStatic(Ctx, ctx, Parents, parents, body_start, body_end, depth + 1);
            return .handled;
        }
        const chain = parents ++ .{ctx};
        for (items) |*item|
            try r.renderStatic(Child, item, @TypeOf(chain), chain, body_start, body_end, depth + 1);
        return .handled;
    }

    /// Hands a named section (and its body) at instruction `pos` to the
    /// type-erased VM, seeding the frame stack with the static ancestor chain
    /// (root first) so scope-walk still reaches statically-rendered ancestors.
    fn fallbackSection(
        r: *Renderer,
        comptime Ctx: type,
        ctx: *const Ctx,
        comptime Parents: type,
        parents: Parents,
        pos: u32,
    ) Error!void {
        const np = @typeInfo(Parents).@"struct".field_types.len;
        var seeds: [np + 1]Context = undefined;
        inline for (0..np) |i| seeds[i] = Context.init(parents[i]);
        seeds[np] = Context.init(ctx);
        // Full instruction bound + stop-at-base: a recursive partial's goto may
        // jump beyond this section's own end, so completion is tracked by frame
        // level, not `pos`.
        try r.renderErased(&seeds, pos, @intCast(r.insts.len), true);
    }

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

    fn writePadding(r: *Renderer) std.Io.Writer.Error!void {
        var i = r.padding;
        while (i != 0) : (i = r.insts[i].end) {
            const inst = r.insts[i];
            try r.out.writeAll(r.data[inst.name_pos..][0..inst.name_len]);
        }
    }

    /// Resolves a simple key (classified at parse time — never the implicit
    /// `{{.}}`, dotted or empty; `hash` is its `fieldHash`, precomputed at
    /// parse time) and writes its value as text. Walks the scope chain like
    /// `lookupTree`, but resolves and writes in a single vtable call per
    /// frame, skipping the intermediate Context and the second (write)
    /// dispatch. Padding (partial indentation) is never injected here: per
    /// the mustache spec, indentation applies to the partial's own lines, not
    /// to lines inside interpolated values.
    fn writeArg(r: *Renderer, hash: u32, escape: bool) std.Io.Writer.Error!void {
        var i = r.index;
        var previous: ?Context = null;
        while (true) : (i -= 1) {
            const ctx = r.frames[i].context;
            const repeated = if (previous) |p| ctx.eql(p) else false;
            if (!repeated) {
                if (try ctx.getKeyWrite(hash, r.out, escape)) return;
                previous = ctx;
            }
            if (i == 0) return;
        }
    }

    /// Resolves a `write_path` or named-section instruction using the
    /// precomputed, pre-hashed segments in `path_segs` — no '.'-scan, no
    /// re-hash. `inst.offset`/`inst.len` bound the segment run; `count == 0` is
    /// the implicit iterator `{{.}}` (`name_len == 1`) or an empty tag
    /// (`name_len == 0`). The head segment scope-walks the frame stack; the tail
    /// segments are strict lookups on the resolved object.
    fn findValuePath(r: *const Renderer, inst: Instruction) ?Context {
        const count = inst.len;
        if (count == 0) {
            if (inst.name_len == 1) return r.frames[r.index].context; // `{{.}}`
            return null; // empty tag
        }
        const segs = r.path_segs[inst.offset..][0..count];
        var current = r.lookupTreeHash(segs[0]) orelse return null;
        for (segs[1..]) |seg| {
            current = current.getKeyHash(seg.hash) orelse return null;
        }
        return current;
    }

    /// Hash-based counterpart to `lookupTree`: searches the frame stack from the
    /// current section towards the root (skipping repeated contexts) for an
    /// object containing the segment.
    fn lookupTreeHash(r: *const Renderer, seg: parser.PathSeg) ?Context {
        var i = r.index;
        var previous: ?Context = null;
        while (true) : (i -= 1) {
            const ctx = r.frames[i].context;
            const repeated = if (previous) |p| ctx.eql(p) else false;
            if (!repeated) {
                if (ctx.getKeyHash(seg.hash)) |v| return v;
                previous = ctx;
            }
            if (i == 0) return null;
        }
    }
};
