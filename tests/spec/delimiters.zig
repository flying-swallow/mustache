//! Test cases from the official mustache spec (mustache/spec, specs/delimiters.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// The equals sign (used on both sides) should permit delimiter changes.
test "spec:delimiters: Pair Behavior" {
    try h.expectRender(
        "{{=<% %>=}}(<%text%>)",
        &.{},
        .{ .text = "Hey!" },
        "(Hey!)",
    );
    try h.expectRenderComptime(
        "{{=<% %>=}}(<%text%>)",
        &.{},
        .{ .text = "Hey!" },
        "(Hey!)",
    );
}

// Characters with special meaning regexen should be valid delimiters.
test "spec:delimiters: Special Characters" {
    try h.expectRender(
        "({{=[ ]=}}[text])",
        &.{},
        .{ .text = "It worked!" },
        "(It worked!)",
    );
    try h.expectRenderComptime(
        "({{=[ ]=}}[text])",
        &.{},
        .{ .text = "It worked!" },
        "(It worked!)",
    );
}

// Delimiters set outside sections should persist.
test "spec:delimiters: Sections" {
    try h.expectRender(
        "[\n{{#section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{= | | =}}\n|#section|\n  {{data}}\n  |data|\n|/section|\n]\n",
        &.{},
        .{ .section = true, .data = "I got interpolated." },
        "[\n  I got interpolated.\n  |data|\n\n  {{data}}\n  I got interpolated.\n]\n",
    );
    try h.expectRenderComptime(
        "[\n{{#section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{= | | =}}\n|#section|\n  {{data}}\n  |data|\n|/section|\n]\n",
        &.{},
        .{ .section = true, .data = "I got interpolated." },
        "[\n  I got interpolated.\n  |data|\n\n  {{data}}\n  I got interpolated.\n]\n",
    );
}

// Delimiters set outside inverted sections should persist.
test "spec:delimiters: Inverted Sections" {
    try h.expectRender(
        "[\n{{^section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{= | | =}}\n|^section|\n  {{data}}\n  |data|\n|/section|\n]\n",
        &.{},
        .{ .section = false, .data = "I got interpolated." },
        "[\n  I got interpolated.\n  |data|\n\n  {{data}}\n  I got interpolated.\n]\n",
    );
    try h.expectRenderComptime(
        "[\n{{^section}}\n  {{data}}\n  |data|\n{{/section}}\n\n{{= | | =}}\n|^section|\n  {{data}}\n  |data|\n|/section|\n]\n",
        &.{},
        .{ .section = false, .data = "I got interpolated." },
        "[\n  I got interpolated.\n  |data|\n\n  {{data}}\n  I got interpolated.\n]\n",
    );
}

// Delimiters set in a parent template should not affect a partial.
test "spec:delimiters: Partial Inheritence" {
    try h.expectRender(
        "[ {{>include}} ]\n{{= | | =}}\n[ |>include| ]\n",
        &.{.{ .name = "include", .data = ".{{value}}." }},
        .{ .value = "yes" },
        "[ .yes. ]\n[ .yes. ]\n",
    );
    try h.expectRenderComptime(
        "[ {{>include}} ]\n{{= | | =}}\n[ |>include| ]\n",
        &.{.{ .name = "include", .data = ".{{value}}." }},
        .{ .value = "yes" },
        "[ .yes. ]\n[ .yes. ]\n",
    );
}

// Delimiters set in a partial should not affect the parent template.
test "spec:delimiters: Post-Partial Behavior" {
    try h.expectRender(
        "[ {{>include}} ]\n[ .{{value}}.  .|value|. ]\n",
        &.{.{ .name = "include", .data = ".{{value}}. {{= | | =}} .|value|." }},
        .{ .value = "yes" },
        "[ .yes.  .yes. ]\n[ .yes.  .|value|. ]\n",
    );
    try h.expectRenderComptime(
        "[ {{>include}} ]\n[ .{{value}}.  .|value|. ]\n",
        &.{.{ .name = "include", .data = ".{{value}}. {{= | | =}} .|value|." }},
        .{ .value = "yes" },
        "[ .yes.  .yes. ]\n[ .yes.  .|value|. ]\n",
    );
}

// Surrounding whitespace should be left untouched.
test "spec:delimiters: Surrounding Whitespace" {
    try h.expectRender(
        "| {{=@ @=}} |",
        &.{},
        .{},
        "|  |",
    );
    try h.expectRenderComptime(
        "| {{=@ @=}} |",
        &.{},
        .{},
        "|  |",
    );
}

// Whitespace should be left untouched.
test "spec:delimiters: Outlying Whitespace (Inline)" {
    try h.expectRender(
        " | {{=@ @=}}\n",
        &.{},
        .{},
        " | \n",
    );
    try h.expectRenderComptime(
        " | {{=@ @=}}\n",
        &.{},
        .{},
        " | \n",
    );
}

// Standalone lines should be removed from the template.
test "spec:delimiters: Standalone Tag" {
    try h.expectRender(
        "Begin.\n{{=@ @=}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n{{=@ @=}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// Indented standalone lines should be removed from the template.
test "spec:delimiters: Indented Standalone Tag" {
    try h.expectRender(
        "Begin.\n  {{=@ @=}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n  {{=@ @=}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// "\r\n" should be considered a newline for standalone tags.
test "spec:delimiters: Standalone Line Endings" {
    try h.expectRender(
        "|\r\n{{= @ @ =}}\r\n|",
        &.{},
        .{},
        "|\r\n|",
    );
    try h.expectRenderComptime(
        "|\r\n{{= @ @ =}}\r\n|",
        &.{},
        .{},
        "|\r\n|",
    );
}

// Standalone tags should not require a newline to precede them.
test "spec:delimiters: Standalone Without Previous Line" {
    try h.expectRender(
        "  {{=@ @=}}\n=",
        &.{},
        .{},
        "=",
    );
    try h.expectRenderComptime(
        "  {{=@ @=}}\n=",
        &.{},
        .{},
        "=",
    );
}

// Standalone tags should not require a newline to follow them.
test "spec:delimiters: Standalone Without Newline" {
    try h.expectRender(
        "=\n  {{=@ @=}}",
        &.{},
        .{},
        "=\n",
    );
    try h.expectRenderComptime(
        "=\n  {{=@ @=}}",
        &.{},
        .{},
        "=\n",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:delimiters: Pair with Padding" {
    try h.expectRender(
        "|{{= @   @ =}}|",
        &.{},
        .{},
        "||",
    );
    try h.expectRenderComptime(
        "|{{= @   @ =}}|",
        &.{},
        .{},
        "||",
    );
}
