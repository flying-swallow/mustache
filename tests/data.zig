//! mustache.js render fixtures (`test/_files`): empty, null and falsy
//! data, and view/key edge cases.
//!
//! Templates and expected outputs are transcribed byte-exactly; data is
//! translated from JS object literals to Zig struct literals, with
//! constant-returning functions replaced by their value and `undefined`/
//! `null` becoming optional-null. Deviations from the original expected
//! output are commented in place. Everything runs through the shared
//! helpers, so each case is checked against both the runtime and comptime
//! parsers.
//!
//! Skipped fixture: check_falsy (lambda, unsupported).

const std = @import("std");
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;

test "mustachejs: empty_template" {
    try expectRender(
        "<html><head></head><body><h1>Test</h1></body></html>",
        &.{},
        .{},
        "<html><head></head><body><h1>Test</h1></body></html>",
    );
    try expectRenderComptime(
        "<html><head></head><body><h1>Test</h1></body></html>",
        &.{},
        .{},
        "<html><head></head><body><h1>Test</h1></body></html>",
    );
}

test "mustachejs: empty_string" {
    try expectRender(
        "{{description}}{{#child}}{{description}}{{/child}}\n",
        &.{},
        .{ .description = "That is all!", .child = .{ .description = "" } },
        "That is all!\n",
    );
    try expectRenderComptime(
        "{{description}}{{#child}}{{description}}{{/child}}\n",
        &.{},
        .{ .description = "That is all!", .child = .{ .description = "" } },
        "That is all!\n",
    );
}

test "mustachejs: error_not_found" {
    try expectRender("{{foo}}", &.{}, .{ .bar = 2 }, "");
    try expectRenderComptime("{{foo}}", &.{}, .{ .bar = 2 }, "");
}

test "mustachejs: null_view" {
    try expectRender(
        "{{name}}'s friends: {{#friends}}{{name}}, {{/friends}}",
        &.{},
        .{ .name = "Joe", .friends = @as(?u8, null) },
        "Joe's friends: ",
    );
    try expectRenderComptime(
        "{{name}}'s friends: {{#friends}}{{name}}, {{/friends}}",
        &.{},
        .{ .name = "Joe", .friends = @as(?u8, null) },
        "Joe's friends: ",
    );
}

test "mustachejs: null_string" {
    // `numeric` was a function returning NaN, which JS prints as "NaN";
    // it is stored as that string here (Zig formats f64 NaN as "nan").
    try expectRender(
        \\Hello {{name}}
        \\glytch {{glytch}}
        \\binary {{binary}}
        \\value {{value}}
        \\undef {{undef}}
        \\numeric {{numeric}}
    ++ "\n",
        &.{},
        .{
            .name = "Elise",
            .glytch = true,
            .binary = false,
            .value = @as(?u8, null),
            .undef = @as(?u8, null),
            .numeric = "NaN",
        },
        "Hello Elise\nglytch true\nbinary false\nvalue \nundef \nnumeric NaN\n",
    );
    try expectRenderComptime(
        \\Hello {{name}}
        \\glytch {{glytch}}
        \\binary {{binary}}
        \\value {{value}}
        \\undef {{undef}}
        \\numeric {{numeric}}
    ++ "\n",
        &.{},
        .{
            .name = "Elise",
            .glytch = true,
            .binary = false,
            .value = @as(?u8, null),
            .undef = @as(?u8, null),
            .numeric = "NaN",
        },
        "Hello Elise\nglytch true\nbinary false\nvalue \nundef \nnumeric NaN\n",
    );
}

test "mustachejs: zero_view" {
    try expectRender(
        "{{#nums}}{{.}},{{/nums}}",
        &.{},
        .{ .nums = .{ 0, 1, 2 } },
        "0,1,2,",
    );
    try expectRenderComptime(
        "{{#nums}}{{.}},{{/nums}}",
        &.{},
        .{ .nums = .{ 0, 1, 2 } },
        "0,1,2,",
    );
}

test "mustachejs: falsy" {
    try expectRender(
        \\{{#emptyString}}empty string{{/emptyString}}
        \\{{^emptyString}}inverted empty string{{/emptyString}}
        \\{{#emptyArray}}empty array{{/emptyArray}}
        \\{{^emptyArray}}inverted empty array{{/emptyArray}}
        \\{{#zero}}zero{{/zero}}
        \\{{^zero}}inverted zero{{/zero}}
        \\{{#null}}null{{/null}}
        \\{{^null}}inverted null{{/null}}
        \\{{#undefined}}undefined{{/undefined}}
        \\{{^undefined}}inverted undefined{{/undefined}}
        \\{{#NaN}}NaN{{/NaN}}
        \\{{^NaN}}inverted NaN{{/NaN}}
    ++ "\n",
        &.{},
        .{
            .emptyString = "",
            .emptyArray = [0][]const u8{},
            .zero = 0,
            .@"null" = @as(?u8, null),
            .@"undefined" = @as(?u8, null),
            .NaN = std.math.nan(f64),
        },
        \\
        \\inverted empty string
        \\
        \\inverted empty array
        \\
        \\inverted zero
        \\
        \\inverted null
        \\
        \\inverted undefined
        \\
        \\inverted NaN
    ++ "\n");
    try expectRenderComptime(
        \\{{#emptyString}}empty string{{/emptyString}}
        \\{{^emptyString}}inverted empty string{{/emptyString}}
        \\{{#emptyArray}}empty array{{/emptyArray}}
        \\{{^emptyArray}}inverted empty array{{/emptyArray}}
        \\{{#zero}}zero{{/zero}}
        \\{{^zero}}inverted zero{{/zero}}
        \\{{#null}}null{{/null}}
        \\{{^null}}inverted null{{/null}}
        \\{{#undefined}}undefined{{/undefined}}
        \\{{^undefined}}inverted undefined{{/undefined}}
        \\{{#NaN}}NaN{{/NaN}}
        \\{{^NaN}}inverted NaN{{/NaN}}
    ++ "\n",
        &.{},
        .{
            .emptyString = "",
            .emptyArray = [0][]const u8{},
            .zero = 0,
            .@"null" = @as(?u8, null),
            .@"undefined" = @as(?u8, null),
            .NaN = std.math.nan(f64),
        },
        \\
        \\inverted empty string
        \\
        \\inverted empty array
        \\
        \\inverted zero
        \\
        \\inverted null
        \\
        \\inverted undefined
        \\
        \\inverted NaN
    ++ "\n");
}

test "mustachejs: falsy_array" {
    try expectRender(
        \\{{#list}}
        \\{{#.}}{{#.}}{{.}}{{/.}}{{^.}}inverted {{/.}}{{/.}}
        \\{{/list}}
    ,
        &.{},
        .{
            .list = .{
                .{ "", "emptyString" },
                .{ [0][]const u8{}, "emptyArray" },
                .{ 0, "zero" },
                .{ @as(?u8, null), "null" },
                .{ @as(?u8, null), "undefined" },
                .{ std.math.nan(f64), "NaN" },
            },
        },
        \\inverted emptyString
        \\inverted emptyArray
        \\inverted zero
        \\inverted null
        \\inverted undefined
        \\inverted NaN
    ++ "\n");
    try expectRenderComptime(
        \\{{#list}}
        \\{{#.}}{{#.}}{{.}}{{/.}}{{^.}}inverted {{/.}}{{/.}}
        \\{{/list}}
    ,
        &.{},
        .{
            .list = .{
                .{ "", "emptyString" },
                .{ [0][]const u8{}, "emptyArray" },
                .{ 0, "zero" },
                .{ @as(?u8, null), "null" },
                .{ @as(?u8, null), "undefined" },
                .{ std.math.nan(f64), "NaN" },
            },
        },
        \\inverted emptyString
        \\inverted emptyArray
        \\inverted zero
        \\inverted null
        \\inverted undefined
        \\inverted NaN
    ++ "\n");
}

test "mustachejs: avoids_obj_prototype_in_view_cache" {
    // In JS this guards against Object.prototype methods leaking into the
    // view cache; here they are ordinary keys.
    try expectRender(
        "{{valueOf}} {{watch}}",
        &.{},
        .{ .valueOf = "Avoids methods", .watch = "in Object.prototype" },
        "Avoids methods in Object.prototype",
    );
    try expectRenderComptime(
        "{{valueOf}} {{watch}}",
        &.{},
        .{ .valueOf = "Avoids methods", .watch = "in Object.prototype" },
        "Avoids methods in Object.prototype",
    );
}

test "mustachejs: uses_props_from_view_prototype" {
    // The JS fixture reads `y` through a prototype getter; flattened here.
    try expectRender(
        "[{{ item.x }};{{ item.y }}]||{{#items}}[{{ a.x }};{{ a.y }} {{#a}}{{y}}{{/a}}]{{/items}}",
        &.{},
        .{
            .item = .{ .x = "0", .y = "00" },
            .items = .{
                .{ .a = .{ .x = "1", .y = "2" } },
                .{ .a = .{ .x = "3", .y = "4" } },
            },
        },
        "[0;00]||[1;2 2][3;4 4]",
    );
    try expectRenderComptime(
        "[{{ item.x }};{{ item.y }}]||{{#items}}[{{ a.x }};{{ a.y }} {{#a}}{{y}}{{/a}}]{{/items}}",
        &.{},
        .{
            .item = .{ .x = "0", .y = "00" },
            .items = .{
                .{ .a = .{ .x = "1", .y = "2" } },
                .{ .a = .{ .x = "3", .y = "4" } },
            },
        },
        "[0;00]||[1;2 2][3;4 4]",
    );
}

test "mustachejs: bug_length_property" {
    try expectRender(
        "{{#length}}The length variable is: {{length}}{{/length}}\n",
        &.{},
        .{ .length = "hello" },
        "The length variable is: hello\n",
    );
    try expectRenderComptime(
        "{{#length}}The length variable is: {{length}}{{/length}}\n",
        &.{},
        .{ .length = "hello" },
        "The length variable is: hello\n",
    );
}
