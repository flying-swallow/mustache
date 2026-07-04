//! Rendering benchmark, ported from mustache-zig's "ramhorns" suite
//! (https://github.com/batiati/mustache-zig/tree/master/benchmark).
//!
//! Renders a small template `TIMES` times across three output modes and
//! compares throughput against a `std.fmt` baseline. Unlike the reference —
//! which drives a JSON runtime data model — this engine renders directly
//! against native Zig structs, so the JSON variants are replaced with a
//! comptime-compiled-template pass (`mustache.Comptime`), this engine's
//! headline feature.
//!
//! Run: `zig build bench -Doptimize=ReleaseFast`

const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const mustache = @import("mustache");
const Template = mustache.parser.Template;

const TIMES = if (builtin.mode == .Debug) 10_000 else 1_000_000;

const Mode = enum { Buffer, Alloc, Writer };

const Metrics = struct {
    ns_per_iter: f64,
    ops_per_s: f64,
    mb_s: f64,
    /// elapsed / reference: >1 is slower than the baseline, <1 is faster.
    /// `null` for the baseline itself and for runs without a reference.
    vs_ref: ?f64,
};

const Row = struct {
    section: []const u8,
    caption: []const u8,
    mode: ?Mode,
    metrics: Metrics,
};

// Every run pushes one row; the fixed capacity comfortably covers the
// (fixed) number of runs below. Reported as a Markdown table by `printTable`.
var rows: [64]Row = undefined;
var row_count: usize = 0;

const Data = struct { title: []const u8, body: []const u8 };
const data: Data = .{
    .title = "Hello, Mustache!",
    .body = "This is a really simple test of the rendering!",
};

// Identical template text to the reference; the values carry no HTML-special
// characters, so the escaped `{{title}}` matches the raw `{[title]s}` and the
// std.fmt comparison stays apples-to-apples.
const simple_template = "<title>{{title}}</title><h1>{{ title }}</h1><div>{{{body}}}</div>";
const fmt_template = "<title>{[title]s}</title><h1>{[title]s}</h1><div>{[body]s}</div>";

// A comptime-compiled template — parsed entirely at compile time.
const Comptime = mustache.Comptime(.{ .data = simple_template });

const partial_template =
    \\{{>head.html}}
    \\<body>
    \\    <div>{{body}}</div>
    \\    {{>footer.html}}
    \\</body>
;
const head_partial =
    \\<head>
    \\    <title>{{title}}</title>
    \\</head>
;
const footer_partial = "<footer>Sup?</footer>";

const parse_template =
    \\<html>
    \\    <head>
    \\        <title>{{title}}</title>
    \\    </head>
    \\    <body>
    \\        {{#posts}}
    \\            <h1>{{title}}</h1>
    \\            <em>{{date}}</em>
    \\            <article>
    \\                {{{body}}}
    \\            </article>
    \\        {{/posts}}
    \\    </body>
    \\</html>
;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer if (builtin.mode == .Debug) {
        _ = debug_allocator.deinit();
    };
    const allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    try simpleTemplate(allocator, io, .Buffer);
    try simpleTemplate(allocator, io, .Alloc);
    try simpleTemplate(allocator, io, .Writer);

    try partialTemplates(allocator, io, .Buffer);
    try partialTemplates(allocator, io, .Alloc);
    try partialTemplates(allocator, io, .Writer);

    try parseTemplates(allocator, io);

    try printTable(io);
}

fn simpleTemplate(allocator: Allocator, io: std.Io, comptime mode: Mode) !void {
    var m = try mustache.Mustache.fromData(allocator, simple_template);
    defer m.deinit();

    std.debug.print("Mode {s}\n", .{@tagName(mode)});
    std.debug.print("----------------------------------\n", .{});

    const reference = try repeat(io, "Simple template", mode, "Zig fmt (baseline)", zigFmt, .{ allocator, mode, fmt_template, data }, null);
    _ = try repeat(io, "Simple template", mode, "Mustache pre-parsed (runtime)", renderTmpl, .{ allocator, mode, &m.template, data }, reference);
    _ = try repeat(io, "Simple template", mode, "Mustache pre-parsed (comptime)", renderTmpl, .{ allocator, mode, &Comptime.template, data }, reference);

    std.debug.print("\n\n", .{});
}

fn partialTemplates(allocator: Allocator, io: std.Io, comptime mode: Mode) !void {
    var m = try mustache.Mustache.init(allocator, .{
        .data = partial_template,
        .partials = &.{
            .{ .name = "head.html", .data = head_partial },
            .{ .name = "footer.html", .data = footer_partial },
        },
    });
    defer m.deinit();

    std.debug.print("Mode {s}\n", .{@tagName(mode)});
    std.debug.print("----------------------------------\n", .{});

    _ = try repeat(io, "Partials", mode, "Mustache pre-parsed partials", renderTmpl, .{ allocator, mode, &m.template, data }, null);

    std.debug.print("\n\n", .{});
}

fn parseTemplates(allocator: Allocator, io: std.Io) !void {
    std.debug.print("----------------------------------\n", .{});
    _ = try repeat(io, "Parse", null, "Parse (compile + discard)", parseOnce, .{allocator}, null);
    std.debug.print("\n\n", .{});
}

fn repeat(io: std.Io, section: []const u8, mode: ?Mode, caption: []const u8, comptime func: anytype, args: anytype, reference: ?i128) !i128 {
    var index: usize = 0;
    var total_bytes: usize = 0;

    const start = std.Io.Clock.awake.now(io).nanoseconds;
    while (index < TIMES) : (index += 1) {
        total_bytes += try @call(.auto, func, args);
    }
    const elapsed: i128 = std.Io.Clock.awake.now(io).nanoseconds - start;

    const metrics = computeMetrics(elapsed, total_bytes, reference);
    printSummary(caption, elapsed, metrics);

    rows[row_count] = .{ .section = section, .caption = caption, .mode = mode, .metrics = metrics };
    row_count += 1;

    return elapsed;
}

fn computeMetrics(elapsed: i128, total_bytes: usize, reference: ?i128) Metrics {
    const secs = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
    var vs_ref: ?f64 = null;
    if (reference) |reference_time| {
        vs_ref = if (reference_time > 0)
            @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(reference_time))
        else
            0;
    }
    return .{
        .ns_per_iter = @as(f64, @floatFromInt(elapsed)) / TIMES,
        .ops_per_s = TIMES / secs,
        .mb_s = (@as(f64, @floatFromInt(total_bytes)) / 1024 / 1024) / secs,
        .vs_ref = vs_ref,
    };
}

fn printSummary(caption: []const u8, elapsed: i128, metrics: Metrics) void {
    const secs = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
    std.debug.print("{s}\n", .{caption});
    std.debug.print("Total time {d:.3}s\n", .{secs});

    if (metrics.vs_ref) |perf| {
        std.debug.print("Comparison {d:.3}x {s}\n", .{ perf, if (perf >= 1) "slower" else "faster" });
    }

    std.debug.print("{d:.0} ops/s\n", .{metrics.ops_per_s});
    std.debug.print("{d:.0} ns/iter\n", .{metrics.ns_per_iter});
    std.debug.print("{d:.1} MB/s\n", .{metrics.mb_s});
    std.debug.print("\n", .{});
}

/// Emits a copy-pasteable Markdown summary of every run to stdout, grouped by
/// section. Kept separate from the verbose per-run output above so the table
/// can be captured cleanly (`zig build bench ... > table.md`).
fn printTable(io: std.Io) !void {
    var buf: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buf);
    const w = &stdout_writer.interface;

    try w.writeAll("\n## Benchmark summary\n\n");

    var i: usize = 0;
    while (i < row_count) {
        const section = rows[i].section;
        try w.print("### {s}\n\n", .{section});
        try w.writeAll("| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |\n");
        try w.writeAll("| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |\n");
        while (i < row_count and std.mem.eql(u8, rows[i].section, section)) : (i += 1) {
            const r = rows[i];
            const m = r.metrics;
            const mode_str = if (r.mode) |mode| @tagName(mode) else "-";
            try w.print("| {s:<30} | {s:<6} | {d:>7.1} | {d:>10.0} | {d:>6.1} | ", .{
                r.caption, mode_str, m.ns_per_iter, m.ops_per_s, m.mb_s,
            });
            if (m.vs_ref) |vs| {
                try w.print("{d:>5.2}x |\n", .{vs});
            } else {
                try w.writeAll("      - |\n");
            }
        }
        try w.writeAll("\n");
    }

    try w.flush();
}

/// Renders an already-compiled template (runtime- or comptime-parsed).
fn renderTmpl(allocator: Allocator, comptime mode: Mode, template: *const Template, d: anytype) !usize {
    switch (mode) {
        .Buffer => {
            var buffer: [1024]u8 = undefined;
            var w = std.Io.Writer.fixed(&buffer);
            try mustache.render(template, d, &w);
            return w.end;
        },
        .Writer => {
            var scratch: [1024]u8 = undefined;
            var discarding = std.Io.Writer.Discarding.init(&scratch);
            try mustache.render(template, d, &discarding.writer);
            return @intCast(discarding.fullCount());
        },
        .Alloc => {
            const ret = try mustache.renderAlloc(allocator, template, d);
            defer allocator.free(ret);
            return ret.len;
        },
    }
}

/// Reference baseline: the equivalent render via `std.fmt`.
fn zigFmt(allocator: Allocator, comptime mode: Mode, comptime fmt: []const u8, d: anytype) !usize {
    switch (mode) {
        .Buffer => {
            var buffer: [1024]u8 = undefined;
            return (try std.fmt.bufPrint(&buffer, fmt, d)).len;
        },
        .Writer => {
            var scratch: [1024]u8 = undefined;
            var discarding = std.Io.Writer.Discarding.init(&scratch);
            try discarding.writer.print(fmt, d);
            return @intCast(discarding.fullCount());
        },
        .Alloc => {
            const ret = try std.fmt.allocPrint(allocator, fmt, d);
            defer allocator.free(ret);
            return ret.len;
        },
    }
}

/// Parse-only pass: compile and discard the template each iteration.
fn parseOnce(allocator: Allocator) !usize {
    var m = try mustache.Mustache.fromData(allocator, parse_template);
    m.deinit();
    return parse_template.len;
}
