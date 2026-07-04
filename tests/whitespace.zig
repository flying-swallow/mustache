//! mustache.js render fixtures (`test/_files`): whitespace handling.
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

test "mustachejs: whitespace" {
    try expectRender(
        "{{tag1}}\n\n\n{{tag2}}.\n",
        &.{},
        .{ .tag1 = "Hello", .tag2 = "World" },
        "Hello\n\n\nWorld.\n",
    );
    try expectRenderComptime(
        "{{tag1}}\n\n\n{{tag2}}.\n",
        &.{},
        .{ .tag1 = "Hello", .tag2 = "World" },
        "Hello\n\n\nWorld.\n",
    );
}

test "mustachejs: bug_11_eating_whitespace" {
    try expectRender("{{tag}} foo\n", &.{}, .{ .tag = "yo" }, "yo foo\n");
    try expectRenderComptime("{{tag}} foo\n", &.{}, .{ .tag = "yo" }, "yo foo\n");
}
