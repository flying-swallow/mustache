//! Test cases from the official mustache spec (mustache/spec, specs/comments.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// Comment blocks should be removed from the template.
test "spec:comments: Inline" {
    try h.expectRender(
        "12345{{! Comment Block! }}67890",
        &.{},
        .{},
        "1234567890",
    );
    try h.expectRenderComptime(
        "12345{{! Comment Block! }}67890",
        &.{},
        .{},
        "1234567890",
    );
}

// Multiline comments should be permitted.
test "spec:comments: Multiline" {
    try h.expectRender(
        "12345{{!\n  This is a\n  multi-line comment...\n}}67890\n",
        &.{},
        .{},
        "1234567890\n",
    );
    try h.expectRenderComptime(
        "12345{{!\n  This is a\n  multi-line comment...\n}}67890\n",
        &.{},
        .{},
        "1234567890\n",
    );
}

// All standalone comment lines should be removed.
test "spec:comments: Standalone" {
    try h.expectRender(
        "Begin.\n{{! Comment Block! }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n{{! Comment Block! }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// All standalone comment lines should be removed.
test "spec:comments: Indented Standalone" {
    try h.expectRender(
        "Begin.\n  {{! Indented Comment Block! }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n  {{! Indented Comment Block! }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// "\r\n" should be considered a newline for standalone tags.
test "spec:comments: Standalone Line Endings" {
    try h.expectRender(
        "|\r\n{{! Standalone Comment }}\r\n|",
        &.{},
        .{},
        "|\r\n|",
    );
    try h.expectRenderComptime(
        "|\r\n{{! Standalone Comment }}\r\n|",
        &.{},
        .{},
        "|\r\n|",
    );
}

// Standalone tags should not require a newline to precede them.
test "spec:comments: Standalone Without Previous Line" {
    try h.expectRender(
        "  {{! I'm Still Standalone }}\n!",
        &.{},
        .{},
        "!",
    );
    try h.expectRenderComptime(
        "  {{! I'm Still Standalone }}\n!",
        &.{},
        .{},
        "!",
    );
}

// Standalone tags should not require a newline to follow them.
test "spec:comments: Standalone Without Newline" {
    try h.expectRender(
        "!\n  {{! I'm Still Standalone }}",
        &.{},
        .{},
        "!\n",
    );
    try h.expectRenderComptime(
        "!\n  {{! I'm Still Standalone }}",
        &.{},
        .{},
        "!\n",
    );
}

// All standalone comment lines should be removed.
test "spec:comments: Multiline Standalone" {
    try h.expectRender(
        "Begin.\n{{!\nSomething's going on here...\n}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n{{!\nSomething's going on here...\n}}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// All standalone comment lines should be removed.
test "spec:comments: Indented Multiline Standalone" {
    try h.expectRender(
        "Begin.\n  {{!\n    Something's going on here...\n  }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
    try h.expectRenderComptime(
        "Begin.\n  {{!\n    Something's going on here...\n  }}\nEnd.\n",
        &.{},
        .{},
        "Begin.\nEnd.\n",
    );
}

// Inline comments should not strip whitespace
test "spec:comments: Indented Inline" {
    try h.expectRender(
        "  12 {{! 34 }}\n",
        &.{},
        .{},
        "  12 \n",
    );
    try h.expectRenderComptime(
        "  12 {{! 34 }}\n",
        &.{},
        .{},
        "  12 \n",
    );
}

// Comment removal should preserve surrounding whitespace.
test "spec:comments: Surrounding Whitespace" {
    try h.expectRender(
        "12345 {{! Comment Block! }} 67890",
        &.{},
        .{},
        "12345  67890",
    );
    try h.expectRenderComptime(
        "12345 {{! Comment Block! }} 67890",
        &.{},
        .{},
        "12345  67890",
    );
}

// Comments must never render, even if variable with same name exists.
test "spec:comments: Variable Name Collision" {
    try h.expectRender(
        "comments never show: >{{! comment }}<",
        &.{},
        .{ .@"! comment" = 1, .@"! comment " = 2, .@"!comment" = 3, .comment = 4 },
        "comments never show: ><",
    );
    try h.expectRenderComptime(
        "comments never show: >{{! comment }}<",
        &.{},
        .{ .@"! comment" = 1, .@"! comment " = 2, .@"!comment" = 3, .comment = 4 },
        "comments never show: ><",
    );
}
