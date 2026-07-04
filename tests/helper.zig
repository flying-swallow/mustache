//! Shared helper utilities for the test suite.
//!
//! `expectRender` checks the runtime parser (`parser.load`) and
//! `expectRenderComptime` the comptime parser (`comptime_parse.parse`);
//! test cases call both so the two implementations stay byte-identical.

const std = @import("std");
const mustache = @import("mustache");

pub const alloc = std.testing.allocator;

/// Asserts that `template` + `data` renders to `expected` through the
/// runtime parser.
pub fn expectRender(
    comptime template: []const u8,
    comptime partials: []const mustache.parser.Partial,
    data: anytype,
    expected: []const u8,
) !void {
    var m = try mustache.Mustache.init(alloc, .{ .data = template, .partials = partials });
    defer m.deinit();
    try expectRendered(&m.template, data, expected);
}

/// Asserts that `template` + `data` renders to `expected` through the
/// comptime parser.
pub fn expectRenderComptime(
    comptime template: []const u8,
    comptime partials: []const mustache.parser.Partial,
    data: anytype,
    expected: []const u8,
) !void {
    const t = comptime mustache.comptimeTemplate(.{ .data = template, .partials = partials });
    try expectRendered(&t, data, expected);
}

/// `expectRender` with a single partial named "partial" (the mustache.js test
/// harness renders every partial fixture with
/// `Mustache.render(template, view, { partial: <contents> })`).
pub fn expectRenderPartial(
    comptime template: []const u8,
    comptime partial: []const u8,
    data: anytype,
    expected: []const u8,
) !void {
    try expectRender(template, &.{.{ .name = "partial", .data = partial }}, data, expected);
}

/// `expectRenderPartial` through the comptime parser.
pub fn expectRenderPartialComptime(
    comptime template: []const u8,
    comptime partial: []const u8,
    data: anytype,
    expected: []const u8,
) !void {
    try expectRenderComptime(template, &.{.{ .name = "partial", .data = partial }}, data, expected);
}

/// Uses `renderAlloc` directly (rather than `Mustache.build`) because it has
/// no struct-only restriction: several spec cases use a bare string/int/array
/// as the top-level data.
fn expectRendered(
    template: *const mustache.parser.Template,
    data: anytype,
    expected: []const u8,
) !void {
    const rendered = try mustache.renderAlloc(alloc, template, data);
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}
