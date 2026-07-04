//! mustache.js render fixtures (`test/_files`): interpolation and
//! HTML escaping.
//!
//! Templates and expected outputs are transcribed byte-exactly; data is
//! translated from JS object literals to Zig struct literals, with
//! constant-returning functions replaced by their value and `undefined`/
//! `null` becoming optional-null. Deviations from the original expected
//! output are commented in place. Everything runs through the shared
//! helpers, so each case is checked against both the runtime and comptime
//! parsers.

const std = @import("std");
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;

test "mustachejs: simple" {
    // `taxed_value` was a function returning 6000.
    try expectRender(
        \\Hello {{name}}
        \\You have just won ${{value}}!
        \\{{#in_ca}}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/in_ca}}
    ++ "\n",
        &.{},
        .{ .name = "Chris", .value = 10000, .taxed_value = 6000, .in_ca = true },
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
    ++ "\n");
    try expectRenderComptime(
        \\Hello {{name}}
        \\You have just won ${{value}}!
        \\{{#in_ca}}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/in_ca}}
    ++ "\n",
        &.{},
        .{ .name = "Chris", .value = 10000, .taxed_value = 6000, .in_ca = true },
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
    ++ "\n");
}

test "mustachejs: two_in_a_row" {
    try expectRender(
        "{{greeting}}, {{name}}!\n",
        &.{},
        .{ .name = "Joe", .greeting = "Welcome" },
        "Welcome, Joe!\n",
    );
    try expectRenderComptime(
        "{{greeting}}, {{name}}!\n",
        &.{},
        .{ .name = "Joe", .greeting = "Welcome" },
        "Welcome, Joe!\n",
    );
}

test "mustachejs: unescaped" {
    // `title` was a constant-returning function.
    try expectRender(
        "<h1>{{{title}}}{{{symbol}}}</h1>\n",
        &.{},
        .{ .title = "Bear > Shark", .symbol = @as(?u8, null) },
        "<h1>Bear > Shark</h1>\n",
    );
    try expectRenderComptime(
        "<h1>{{{title}}}{{{symbol}}}</h1>\n",
        &.{},
        .{ .title = "Bear > Shark", .symbol = @as(?u8, null) },
        "<h1>Bear > Shark</h1>\n",
    );
}

test "mustachejs: escaped" {
    // `title` was a constant-returning function.
    try expectRender(
        \\<h1>{{title}}{{symbol}}</h1>
        \\And even {{entities}}, but not {{{entities}}}.
    ++ "\n",
        &.{},
        .{
            .title = "Bear > Shark",
            .symbol = @as(?u8, null),
            .entities = "&quot; \"'<>`=/",
        },
        \\<h1>Bear &gt; Shark</h1>
        \\And even &amp;quot; &quot;&#39;&lt;&gt;&#x60;&#x3D;&#x2F;, but not &quot; "'<>`=/.
    ++ "\n");
    try expectRenderComptime(
        \\<h1>{{title}}{{symbol}}</h1>
        \\And even {{entities}}, but not {{{entities}}}.
    ++ "\n",
        &.{},
        .{
            .title = "Bear > Shark",
            .symbol = @as(?u8, null),
            .entities = "&quot; \"'<>`=/",
        },
        \\<h1>Bear &gt; Shark</h1>
        \\And even &amp;quot; &quot;&#39;&lt;&gt;&#x60;&#x3D;&#x2F;, but not &quot; "'<>`=/.
    ++ "\n");
}

test "mustachejs: ampersand_escape" {
    try expectRender(
        "{{&message}}\n",
        &.{},
        .{ .message = "Some <code>" },
        "Some <code>\n",
    );
    try expectRenderComptime(
        "{{&message}}\n",
        &.{},
        .{ .message = "Some <code>" },
        "Some <code>\n",
    );
}

test "mustachejs: apostrophe" {
    try expectRender(
        "{{apos}}{{control}}\n",
        &.{},
        .{ .apos = "'", .control = "X" },
        "&#39;X\n",
    );
    try expectRenderComptime(
        "{{apos}}{{control}}\n",
        &.{},
        .{ .apos = "'", .control = "X" },
        "&#39;X\n",
    );
}

test "mustachejs: backslashes" {
    try expectRender(
        \\* {{value}}
        \\* {{{value}}}
        \\* {{&value}}
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n",
        &.{},
        .{ .value = "\\abc" },
        \\* \abc
        \\* \abc
        \\* \abc
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n");
    try expectRenderComptime(
        \\* {{value}}
        \\* {{{value}}}
        \\* {{&value}}
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n",
        &.{},
        .{ .value = "\\abc" },
        \\* \abc
        \\* \abc
        \\* \abc
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n");
}

test "mustachejs: keys_with_questionmarks" {
    try expectRender(
        \\{{#person?}}
        \\  Hi {{name}}!
        \\{{/person?}}
    ++ "\n",
        &.{},
        .{ .@"person?" = .{ .name = "Jon" } },
        "  Hi Jon!\n",
    );
    try expectRenderComptime(
        \\{{#person?}}
        \\  Hi {{name}}!
        \\{{/person?}}
    ++ "\n",
        &.{},
        .{ .@"person?" = .{ .name = "Jon" } },
        "  Hi Jon!\n",
    );
}

test "mustachejs: bom_as_whitespace" {
    // From spec/_files: a U+FEFF (BOM) inside a tag name counts as whitespace
    // (JS `\s` matches it), so `{{\u{FEFF}tag}}` resolves the key "tag".
    // The '/' in the value is escaped per the entityMap (the fixture's .txt
    // has a plain '/'; its spec runner used a different escape function).
    try expectRender(
        "{{\u{FEFF}tag}}",
        &.{},
        .{ .tag = "Tag name w/o BOM", .@"\u{FEFF}tag" = "Tag name with BOM" },
        "Tag name w&#x2F;o BOM",
    );
    try expectRenderComptime(
        "{{\u{FEFF}tag}}",
        &.{},
        .{ .tag = "Tag name w/o BOM", .@"\u{FEFF}tag" = "Tag name with BOM" },
        "Tag name w&#x2F;o BOM",
    );
}

test "escaping: long strings through the vectorized scan" {
    // Exercises the SIMD escape path in `writeString`: strings longer than a
    // vector chunk, escapes falling inside chunks, on chunk boundaries, in
    // the sub-vector tail, back-to-back, and none at all.
    const clean = "a clean sentence that is comfortably longer than one simd chunk";
    try expectRender("{{v}}", &.{}, .{ .v = clean }, clean);

    // 64 bytes with escapes at positions 0, 15, 16, 31 and in the tail.
    const spiky = "&23456789012345<>2345678901234\"56789012345678901234567890123'56";
    const spiky_out = "&amp;23456789012345&lt;&gt;2345678901234&quot;56789012345678901234567890123&#39;56";
    try expectRender("{{v}}", &.{}, .{ .v = spiky }, spiky_out);
    try expectRenderComptime("{{v}}", &.{}, .{ .v = spiky }, spiky_out);

    // Every byte escapes, spanning several chunks.
    const dense: [34]u8 = @splat('&');
    const dense_out = comptime blk: {
        var s: []const u8 = "";
        for (0..dense.len) |_| s = s ++ "&amp;";
        break :blk s;
    };
    try expectRender("{{v}}", &.{}, .{ .v = &dense }, dense_out);

    // Unescaped writes bypass the scan entirely.
    try expectRender("{{{v}}}", &.{}, .{ .v = spiky }, spiky);
}
