//! mustache.js render fixtures (`test/_files`): custom delimiters.
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

test "mustachejs: changing_delimiters" {
    try expectRender(
        "{{=<% %>=}}<% foo %> {{foo}} <%{bar}%> {{{bar}}}\n",
        &.{},
        .{ .foo = "foooooooooooooo", .bar = "<b>bar!</b>" },
        "foooooooooooooo {{foo}} <b>bar!</b> {{{bar}}}\n",
    );
    try expectRenderComptime(
        "{{=<% %>=}}<% foo %> {{foo}} <%{bar}%> {{{bar}}}\n",
        &.{},
        .{ .foo = "foooooooooooooo", .bar = "<b>bar!</b>" },
        "foooooooooooooo {{foo}} <b>bar!</b> {{{bar}}}\n",
    );
}

test "mustachejs: delimiters" {
    try expectRender(
        \\{{=<% %>=}}*
        \\<% first %>
        \\* <% second %>
        \\<%=| |=%>
        \\* | third |
        \\|={{ }}=|
        \\* {{ fourth }}
    ++ "\n",
        &.{},
        .{
            .first = "It worked the first time.",
            .second = "And it worked the second time.",
            .third = "Then, surprisingly, it worked the third time.",
            .fourth = "Fourth time also fine!.",
        },
        \\*
        \\It worked the first time.
        \\* And it worked the second time.
        \\* Then, surprisingly, it worked the third time.
        \\* Fourth time also fine!.
    ++ "\n");
    try expectRenderComptime(
        \\{{=<% %>=}}*
        \\<% first %>
        \\* <% second %>
        \\<%=| |=%>
        \\* | third |
        \\|={{ }}=|
        \\* {{ fourth }}
    ++ "\n",
        &.{},
        .{
            .first = "It worked the first time.",
            .second = "And it worked the second time.",
            .third = "Then, surprisingly, it worked the third time.",
            .fourth = "Fourth time also fine!.",
        },
        \\*
        \\It worked the first time.
        \\* And it worked the second time.
        \\* Then, surprisingly, it worked the third time.
        \\* Fourth time also fine!.
    ++ "\n");
}
