//! mustache.js render fixtures (`test/_files`): comments.
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

test "mustachejs: comments" {
    // `title` was a constant-returning function.
    try expectRender(
        "<h1>{{title}}{{! just something interesting... or not... }}</h1>\n",
        &.{},
        .{ .title = "A Comedy of Errors" },
        "<h1>A Comedy of Errors</h1>\n",
    );
    try expectRenderComptime(
        "<h1>{{title}}{{! just something interesting... or not... }}</h1>\n",
        &.{},
        .{ .title = "A Comedy of Errors" },
        "<h1>A Comedy of Errors</h1>\n",
    );
}

test "mustachejs: multiline_comment" {
    try expectRender(
        \\{{!
        \\
        \\This is a multi-line comment.
        \\
        \\}}
        \\Hello world!
    ++ "\n",
        &.{},
        .{},
        "Hello world!\n",
    );
    try expectRenderComptime(
        \\{{!
        \\
        \\This is a multi-line comment.
        \\
        \\}}
        \\Hello world!
    ++ "\n",
        &.{},
        .{},
        "Hello world!\n",
    );
}
