//! Test cases from the official mustache spec (mustache/spec, specs/partials.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// The greater-than operator should expand to the named partial.
test "spec:partials: Basic Behavior" {
    try h.expectRender(
        "\"{{>text}}\"",
        &.{.{ .name = "text", .data = "from partial" }},
        .{},
        "\"from partial\"",
    );
    try h.expectRenderComptime(
        "\"{{>text}}\"",
        &.{.{ .name = "text", .data = "from partial" }},
        .{},
        "\"from partial\"",
    );
}

// The empty string should be used when the named partial is not found.
test "spec:partials: Failed Lookup" {
    try h.expectRender(
        "\"{{>text}}\"",
        &.{},
        .{},
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{>text}}\"",
        &.{},
        .{},
        "\"\"",
    );
}

// The greater-than operator should operate within the current context.
test "spec:partials: Context" {
    try h.expectRender(
        "\"{{>partial}}\"",
        &.{.{ .name = "partial", .data = "*{{text}}*" }},
        .{ .text = "content" },
        "\"*content*\"",
    );
    try h.expectRenderComptime(
        "\"{{>partial}}\"",
        &.{.{ .name = "partial", .data = "*{{text}}*" }},
        .{ .text = "content" },
        "\"*content*\"",
    );
}

// The greater-than operator should properly recurse.
test "spec:partials: Recursion" {
    try h.expectRender(
        "{{>node}}",
        &.{.{ .name = "node", .data = "{{content}}<{{#nodes}}{{>node}}{{/nodes}}>" }},
        .{ .content = "X", .nodes = .{.{ .content = "Y", .nodes = [0]bool{} }} },
        "X<Y<>>",
    );
    try h.expectRenderComptime(
        "{{>node}}",
        &.{.{ .name = "node", .data = "{{content}}<{{#nodes}}{{>node}}{{/nodes}}>" }},
        .{ .content = "X", .nodes = .{.{ .content = "Y", .nodes = [0]bool{} }} },
        "X<Y<>>",
    );
}

// The greater-than operator should work from within partials.
test "spec:partials: Nested" {
    try h.expectRender(
        "{{>outer}}",
        &.{ .{ .name = "outer", .data = "*{{a}} {{>inner}}*" }, .{ .name = "inner", .data = "{{b}}!" } },
        .{ .a = "hello", .b = "world" },
        "*hello world!*",
    );
    try h.expectRenderComptime(
        "{{>outer}}",
        &.{ .{ .name = "outer", .data = "*{{a}} {{>inner}}*" }, .{ .name = "inner", .data = "{{b}}!" } },
        .{ .a = "hello", .b = "world" },
        "*hello world!*",
    );
}

// The greater-than operator should not alter surrounding whitespace.
test "spec:partials: Surrounding Whitespace" {
    try h.expectRender(
        "| {{>partial}} |",
        &.{.{ .name = "partial", .data = "\t|\t" }},
        .{},
        "| \t|\t |",
    );
    try h.expectRenderComptime(
        "| {{>partial}} |",
        &.{.{ .name = "partial", .data = "\t|\t" }},
        .{},
        "| \t|\t |",
    );
}

// Whitespace should be left untouched.
test "spec:partials: Inline Indentation" {
    try h.expectRender(
        "  {{data}}  {{> partial}}\n",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{ .data = "|" },
        "  |  >\n>\n",
    );
    try h.expectRenderComptime(
        "  {{data}}  {{> partial}}\n",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{ .data = "|" },
        "  |  >\n>\n",
    );
}

// "\r\n" should be considered a newline for standalone tags.
test "spec:partials: Standalone Line Endings" {
    try h.expectRender(
        "|\r\n{{>partial}}\r\n|",
        &.{.{ .name = "partial", .data = ">" }},
        .{},
        "|\r\n>|",
    );
    try h.expectRenderComptime(
        "|\r\n{{>partial}}\r\n|",
        &.{.{ .name = "partial", .data = ">" }},
        .{},
        "|\r\n>|",
    );
}

// Standalone tags should not require a newline to precede them.
test "spec:partials: Standalone Without Previous Line" {
    try h.expectRender(
        "  {{>partial}}\n>",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        "  >\n  >>",
    );
    try h.expectRenderComptime(
        "  {{>partial}}\n>",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        "  >\n  >>",
    );
}

// Standalone tags should not require a newline to follow them.
test "spec:partials: Standalone Without Newline" {
    try h.expectRender(
        ">\n  {{>partial}}",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        ">\n  >\n  >",
    );
    try h.expectRenderComptime(
        ">\n  {{>partial}}",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        ">\n  >\n  >",
    );
}

// Each line of the partial should be indented before rendering.
test "spec:partials: Standalone Indentation" {
    try h.expectRender(
        "\\\n {{>partial}}\n/\n",
        &.{.{ .name = "partial", .data = "|\n{{{content}}}\n|\n" }},
        .{ .content = "<\n->" },
        "\\\n |\n <\n->\n |\n/\n",
    );
    try h.expectRenderComptime(
        "\\\n {{>partial}}\n/\n",
        &.{.{ .name = "partial", .data = "|\n{{{content}}}\n|\n" }},
        .{ .content = "<\n->" },
        "\\\n |\n <\n->\n |\n/\n",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:partials: Padding Whitespace" {
    try h.expectRender(
        "|{{> partial }}|",
        &.{.{ .name = "partial", .data = "[]" }},
        .{ .boolean = true },
        "|[]|",
    );
    try h.expectRenderComptime(
        "|{{> partial }}|",
        &.{.{ .name = "partial", .data = "[]" }},
        .{ .boolean = true },
        "|[]|",
    );
}
