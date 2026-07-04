//! Core library tests: API surface, filesystem partials, load errors, and
//! engine behaviors not covered by the ported spec / mustache.js suites.
//! In-memory render expectations call `helper.expectRender` (runtime
//! parser) and `helper.expectRenderComptime` (comptime parser).

const std = @import("std");
const mustache = @import("mustache");
const Mustache = mustache.Mustache;
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;

const alloc = std.testing.allocator;

const User = struct {
    name: []const u8,
    id: isize,
};

const user_data = .{
    .users = [_]User{
        .{ .name = "Rene", .id = 1 },
        .{ .name = "Caro", .id = 6 },
    },
    .nested = .{
        .item = "nesting works",
    },
};

test "in-memory template" {
    try expectRender(
        "{{=<< >>=}}* Users:\n<<#users>><<id>>. <<& name>> (<<name>>)\n<</users>>\nNested: <<& nested.item >>.",
        &.{},
        user_data,
        "* Users:\n1. Rene (Rene)\n6. Caro (Caro)\nNested: nesting works.",
    );
    try expectRenderComptime(
        "{{=<< >>=}}* Users:\n<<#users>><<id>>. <<& name>> (<<name>>)\n<</users>>\nNested: <<& nested.item >>.",
        &.{},
        user_data,
        "* Users:\n1. Rene (Rene)\n6. Caro (Caro)\nNested: nesting works.",
    );
}

test "template from file with partial" {
    var threaded: std.Io.Threaded = .init(alloc, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    var m = try Mustache.fromFile(alloc, io, "tests/testdata/template.html");
    defer m.deinit();
    const rendered = try m.build(alloc, user_data);
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings(
        "* Users:\n1. Rene (Rene)\n6. Caro (Caro)\nNested: nesting works.\n",
        rendered,
    );
}

test "sections over falsy and truthy values" {
    try expectRender(
        "{{#t}}T{{/t}}{{#f}}F{{/f}}{{#missing}}M{{/missing}}{{#opt}}O{{/opt}}{{#s}}({{x}}){{/s}}",
        &.{},
        .{ .t = true, .f = false, .opt = @as(?u8, null), .s = .{ .x = 1 } },
        "T(1)",
    );
    try expectRenderComptime(
        "{{#t}}T{{/t}}{{#f}}F{{/f}}{{#missing}}M{{/missing}}{{#opt}}O{{/opt}}{{#s}}({{x}}){{/s}}",
        &.{},
        .{ .t = true, .f = false, .opt = @as(?u8, null), .s = .{ .x = 1 } },
        "T(1)",
    );
}

test "inverted sections" {
    try expectRender(
        "{{^missing}}M{{/missing}}{{^f}}F{{/f}}{{^t}}T{{/t}}{{^empty}}E{{/empty}}{{^full}}X{{/full}}",
        &.{},
        .{ .f = false, .t = true, .empty = [_]User{}, .full = [_]User{.{ .name = "a", .id = 0 }} },
        "MFE",
    );
    try expectRenderComptime(
        "{{^missing}}M{{/missing}}{{^f}}F{{/f}}{{^t}}T{{/t}}{{^empty}}E{{/empty}}{{^full}}X{{/full}}",
        &.{},
        .{ .f = false, .t = true, .empty = [_]User{}, .full = [_]User{.{ .name = "a", .id = 0 }} },
        "MFE",
    );
}

test "array sections iterate" {
    try expectRender(
        "{{#list}}[{{v}}]{{/list}}",
        &.{},
        .{ .list = [_]struct { v: u8 }{ .{ .v = 1 }, .{ .v = 2 }, .{ .v = 3 } } },
        "[1][2][3]",
    );
    try expectRenderComptime(
        "{{#list}}[{{v}}]{{/list}}",
        &.{},
        .{ .list = [_]struct { v: u8 }{ .{ .v = 1 }, .{ .v = 2 }, .{ .v = 3 } } },
        "[1][2][3]",
    );
}

test "dot notation and parent scope fallback" {
    try expectRender(
        "{{a.b.c}}|{{#inner}}{{outer_val}}{{a.b.c}}{{/inner}}",
        &.{},
        .{
            .a = .{ .b = .{ .c = "deep" } },
            .inner = .{ .x = 1 },
            .outer_val = "out",
        },
        "deep|outdeep",
    );
    try expectRenderComptime(
        "{{a.b.c}}|{{#inner}}{{outer_val}}{{a.b.c}}{{/inner}}",
        &.{},
        .{
            .a = .{ .b = .{ .c = "deep" } },
            .inner = .{ .x = 1 },
            .outer_val = "out",
        },
        "deep|outdeep",
    );
}

test "html escaping matches the mustache.js entityMap" {
    try expectRender(
        "{{v}}",
        &.{},
        .{ .v = "<b>\"&'`=/| a" },
        "&lt;b&gt;&quot;&amp;&#39;&#x60;&#x3D;&#x2F;| a",
    );
    try expectRenderComptime(
        "{{v}}",
        &.{},
        .{ .v = "<b>\"&'`=/| a" },
        "&lt;b&gt;&quot;&amp;&#39;&#x60;&#x3D;&#x2F;| a",
    );
    try expectRender("{{& v}}", &.{}, .{ .v = "<b>\"&'`=/| a" }, "<b>\"&'`=/| a");
    try expectRenderComptime("{{& v}}", &.{}, .{ .v = "<b>\"&'`=/| a" }, "<b>\"&'`=/| a");
    try expectRender("{{{v}}}", &.{}, .{ .v = "<b>\"&'`=/| a" }, "<b>\"&'`=/| a");
    try expectRenderComptime("{{{v}}}", &.{}, .{ .v = "<b>\"&'`=/| a" }, "<b>\"&'`=/| a");
}

test "scalar rendering" {
    const E = enum(u8) { zig = 7, c = 9 };
    try expectRender(
        "{{i}} {{n}} {{f}} {{b}} {{e}} {{big}}{{opt}}",
        &.{},
        .{
            .i = @as(u32, 42),
            .n = @as(i8, -7),
            .f = @as(f64, 3.5),
            .b = true,
            .e = E.zig,
            .big = @as(u64, std.math.maxInt(u64)),
            .opt = @as(?u8, null),
        },
        "42 -7 3.5 true 7 18446744073709551615",
    );
    try expectRenderComptime(
        "{{i}} {{n}} {{f}} {{b}} {{e}} {{big}}{{opt}}",
        &.{},
        .{
            .i = @as(u32, 42),
            .n = @as(i8, -7),
            .f = @as(f64, 3.5),
            .b = true,
            .e = E.zig,
            .big = @as(u64, std.math.maxInt(u64)),
            .opt = @as(?u8, null),
        },
        "42 -7 3.5 true 7 18446744073709551615",
    );
}

test "implicit iterator" {
    try expectRender(
        "{{#list}}({{.}}){{/list}}",
        &.{},
        .{ .list = [_][]const u8{ "a", "b" } },
        "(a)(b)",
    );
    try expectRenderComptime(
        "{{#list}}({{.}}){{/list}}",
        &.{},
        .{ .list = [_][]const u8{ "a", "b" } },
        "(a)(b)",
    );
    try expectRender("{{#n}}<{{{.}}}>{{/n}}", &.{}, .{ .n = .{ .x = 1 } }, "<>");
    try expectRenderComptime("{{#n}}<{{{.}}}>{{/n}}", &.{}, .{ .n = .{ .x = 1 } }, "<>");
}

test "sections over scalars use mustache.js truthiness" {
    try expectRender(
        "{{#s}}S{{/s}}{{#es}}E{{/es}}{{#i}}I{{/i}}{{#z}}Z{{/z}}{{#f}}F{{/f}}{{#nan}}N{{/nan}}",
        &.{},
        .{
            .s = "x",
            .es = "",
            .i = @as(i64, 2),
            .z = @as(i64, 0),
            .f = @as(f64, 0.5),
            .nan = std.math.nan(f64),
        },
        "SIF",
    );
    try expectRenderComptime(
        "{{#s}}S{{/s}}{{#es}}E{{/es}}{{#i}}I{{/i}}{{#z}}Z{{/z}}{{#f}}F{{/f}}{{#nan}}N{{/nan}}",
        &.{},
        .{
            .s = "x",
            .es = "",
            .i = @as(i64, 2),
            .z = @as(i64, 0),
            .f = @as(f64, 0.5),
            .nan = std.math.nan(f64),
        },
        "SIF",
    );
}

test "tuples valueify as arrays" {
    try expectRender(
        "{{#list}}[{{.}}]{{/list}}",
        &.{},
        .{ .list = .{ "a", @as(u8, 2), true } },
        "[a][2][true]",
    );
    try expectRenderComptime(
        "{{#list}}[{{.}}]{{/list}}",
        &.{},
        .{ .list = .{ "a", @as(u8, 2), true } },
        "[a][2][true]",
    );
}

test "delimiter change" {
    try expectRender(
        "{{a}}{{=[[ ]]=}}[[a]]{{b}}[[=<% %>=]]<%a%>",
        &.{},
        .{ .a = "A", .b = "ignored" },
        "AA{{b}}A",
    );
    try expectRenderComptime(
        "{{a}}{{=[[ ]]=}}[[a]]{{b}}[[=<% %>=]]<%a%>",
        &.{},
        .{ .a = "A", .b = "ignored" },
        "AA{{b}}A",
    );
}

test "comments and standalone tag trimming" {
    try expectRender(
        "line1\n  {{! a comment }}\nline2\n",
        &.{},
        .{ .x = 1 },
        "line1\nline2\n",
    );
    try expectRenderComptime(
        "line1\n  {{! a comment }}\nline2\n",
        &.{},
        .{ .x = 1 },
        "line1\nline2\n",
    );
}

test "partial with padding is indented on every line" {
    var threaded: std.Io.Threaded = .init(alloc, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    var m = try Mustache.fromFile(alloc, io, "tests/testdata/padding_root.html");
    defer m.deinit();
    const rendered = try m.build(alloc, .{ .v = "X" });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings(
        "Start\n  line1 X\n  line2\nEnd\n",
        rendered,
    );
}

test "repeated partial is compiled once and reused" {
    var threaded: std.Io.Threaded = .init(alloc, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    var m = try Mustache.fromFile(alloc, io, "tests/testdata/dedup_root.html");
    defer m.deinit();

    // The second include must be a jump, not a recompilation.
    var goto_count: usize = 0;
    for (m.template.instructions) |inst| {
        if (inst.op == .section_goto) goto_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), goto_count);

    const rendered = try m.build(alloc, .{ .v = "X" });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("line1 X\nline2\nline1 X\nline2\n", rendered);
}

test "in-memory partials" {
    var m = try Mustache.init(alloc, .{
        .data = "[{{> p}}|{{> p}}|{{> empty}}]",
        .partials = &.{
            .{ .name = "p", .data = "hi {{name}}" },
            .{ .name = "empty", .data = "" },
        },
    });
    defer m.deinit();

    // The second include must be a jump, not a recompilation.
    var goto_count: usize = 0;
    for (m.template.instructions) |inst| {
        if (inst.op == .section_goto) goto_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), goto_count);

    const rendered = try m.build(alloc, .{ .name = "you" });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("[hi you|hi you|]", rendered);
}

test "recursive template via virtual root" {
    var m = try Mustache.init(alloc, .{
        .filename = "root",
        .data = "A{{#child}}{{> root}}{{/child}}B",
    });
    defer m.deinit();
    const rendered = try m.build(alloc, .{ .child = .{ .child = false } });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("AABB", rendered);
}

test "unbounded recursion fails with TooDeep" {
    var m = try Mustache.init(alloc, .{
        .filename = "root",
        .data = "{{#child}}{{> root}}{{/child}}",
    });
    defer m.deinit();
    // `child` resolves in every nested scope, so rendering never terminates
    // and must trip the nesting limit.
    try std.testing.expectError(error.TooDeep, m.build(alloc, .{ .child = .{ .x = 1 } }));
}

test "load errors" {
    try std.testing.expectError(error.ClosureMismatch, Mustache.fromData(alloc, "{{name"));
    try std.testing.expectError(error.ClosureMismatch, Mustache.fromData(alloc, "{{#a}}no closing tag"));
    try std.testing.expectError(error.ClosureMismatch, Mustache.fromData(alloc, "{{#a}}x{{/b}}"));
    try std.testing.expectError(error.DelimiterTooLong, Mustache.fromData(alloc, "{{=aaaaa bbbbb=}}x"));
    // From mustache.js parse-test.js: closing a section that was never opened.
    try std.testing.expectError(error.ClosureMismatch, Mustache.fromData(alloc, "The end of the list! {{/people}}"));
    // From mustache.js parse-test.js: delimiter tag missing the end delimiter.
    try std.testing.expectError(error.ClosureMismatch, Mustache.fromData(alloc, "A template {{=<%=}}"));
}

test "unresolved partial renders as empty string" {
    try expectRender("a{{> nonexistent}}b", &.{}, .{}, "ab");
    try expectRenderComptime("a{{> nonexistent}}b", &.{}, .{}, "ab");
}

// -- Comptime-compiled templates ----------------------------------------------
// `expectRender` above already checks the comptime parser against every
// in-memory case; these cover the comptime-specific API surface.

test "comptime: in-memory partials" {
    const t = comptime mustache.comptimeTemplate(.{
        .data = "[{{> p}}|{{> p}}|{{> empty}}]",
        .partials = &.{
            .{ .name = "p", .data = "hi {{name}}" },
            .{ .name = "empty", .data = "" },
        },
    });

    // The second include must be a jump, not a recompilation.
    comptime var goto_count: usize = 0;
    inline for (t.instructions) |inst| {
        if (inst.op == .section_goto) goto_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), goto_count);

    const rendered = try mustache.renderAlloc(alloc, &t, .{ .name = "you" });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("[hi you|hi you|]", rendered);
}

test "comptime: recursive template via virtual root" {
    const T = mustache.Comptime(.{
        .filename = "root",
        .data = "A{{#child}}{{> root}}{{/child}}B",
    });
    const rendered = try T.build(alloc, .{ .child = .{ .child = false } });
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("AABB", rendered);
}

test "comptime: unbounded recursion fails at render time with TooDeep" {
    const t = comptime mustache.comptimeTemplate(.{
        .filename = "root",
        .data = "{{#child}}{{> root}}{{/child}}",
    });
    try std.testing.expectError(error.TooDeep, mustache.renderAlloc(alloc, &t, .{ .child = .{ .x = 1 } }));
}
