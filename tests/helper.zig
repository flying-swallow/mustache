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
