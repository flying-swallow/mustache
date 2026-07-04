//! Test cases from the official mustache spec (mustache/spec, specs/inverted.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// Falsey sections should have their contents rendered.
test "spec:inverted: Falsey" {
    try h.expectRender(
        "\"{{^boolean}}This should be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = false },
        "\"This should be rendered.\"",
    );
    try h.expectRenderComptime(
        "\"{{^boolean}}This should be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = false },
        "\"This should be rendered.\"",
    );
}

// Truthy sections should have their contents omitted.
test "spec:inverted: Truthy" {
    try h.expectRender(
        "\"{{^boolean}}This should not be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = true },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{^boolean}}This should not be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = true },
        "\"\"",
    );
}

// Null is falsey.
test "spec:inverted: Null is falsey" {
    try h.expectRender(
        "\"{{^null}}This should be rendered.{{/null}}\"",
        &.{},
        .{ .null = null },
        "\"This should be rendered.\"",
    );
    try h.expectRenderComptime(
        "\"{{^null}}This should be rendered.{{/null}}\"",
        &.{},
        .{ .null = null },
        "\"This should be rendered.\"",
    );
}

// Objects and hashes should behave like truthy values.
test "spec:inverted: Context" {
    try h.expectRender(
        "\"{{^context}}Hi {{name}}.{{/context}}\"",
        &.{},
        .{ .context = .{ .name = "Joe" } },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{^context}}Hi {{name}}.{{/context}}\"",
        &.{},
        .{ .context = .{ .name = "Joe" } },
        "\"\"",
    );
}

// Lists should behave like truthy values.
test "spec:inverted: List" {
    try h.expectRender(
        "\"{{^list}}{{n}}{{/list}}\"",
        &.{},
        .{ .list = .{ .{ .n = 1 }, .{ .n = 2 }, .{ .n = 3 } } },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{^list}}{{n}}{{/list}}\"",
        &.{},
        .{ .list = .{ .{ .n = 1 }, .{ .n = 2 }, .{ .n = 3 } } },
        "\"\"",
    );
}

// Empty lists should behave like falsey values.
test "spec:inverted: Empty List" {
    try h.expectRender(
        "\"{{^list}}Yay lists!{{/list}}\"",
        &.{},
        .{ .list = [0]bool{} },
        "\"Yay lists!\"",
    );
    try h.expectRenderComptime(
        "\"{{^list}}Yay lists!{{/list}}\"",
        &.{},
        .{ .list = [0]bool{} },
        "\"Yay lists!\"",
    );
}

// Multiple inverted sections per template should be permitted.
test "spec:inverted: Doubled" {
    try h.expectRender(
        "{{^bool}}\n* first\n{{/bool}}\n* {{two}}\n{{^bool}}\n* third\n{{/bool}}\n",
        &.{},
        .{ .bool = false, .two = "second" },
        "* first\n* second\n* third\n",
    );
    try h.expectRenderComptime(
        "{{^bool}}\n* first\n{{/bool}}\n* {{two}}\n{{^bool}}\n* third\n{{/bool}}\n",
        &.{},
        .{ .bool = false, .two = "second" },
        "* first\n* second\n* third\n",
    );
}

// Nested falsey sections should have their contents rendered.
test "spec:inverted: Nested (Falsey)" {
    try h.expectRender(
        "| A {{^bool}}B {{^bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = false },
        "| A B C D E |",
    );
    try h.expectRenderComptime(
        "| A {{^bool}}B {{^bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = false },
        "| A B C D E |",
    );
}

// Nested truthy sections should be omitted.
test "spec:inverted: Nested (Truthy)" {
    try h.expectRender(
        "| A {{^bool}}B {{^bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = true },
        "| A  E |",
    );
    try h.expectRenderComptime(
        "| A {{^bool}}B {{^bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = true },
        "| A  E |",
    );
}

// Failed context lookups should be considered falsey.
test "spec:inverted: Context Misses" {
    try h.expectRender(
        "[{{^missing}}Cannot find key 'missing'!{{/missing}}]",
        &.{},
        .{},
        "[Cannot find key 'missing'!]",
    );
    try h.expectRenderComptime(
        "[{{^missing}}Cannot find key 'missing'!{{/missing}}]",
        &.{},
        .{},
        "[Cannot find key 'missing'!]",
    );
}

// Dotted names should be valid for Inverted Section tags.
test "spec:inverted: Dotted Names - Truthy" {
    try h.expectRender(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{ .c = true } } },
        "\"\" == \"\"",
    );
    try h.expectRenderComptime(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{ .c = true } } },
        "\"\" == \"\"",
    );
}

// Dotted names should be valid for Inverted Section tags.
test "spec:inverted: Dotted Names - Falsey" {
    try h.expectRender(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"Not Here\"",
        &.{},
        .{ .a = .{ .b = .{ .c = false } } },
        "\"Not Here\" == \"Not Here\"",
    );
    try h.expectRenderComptime(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"Not Here\"",
        &.{},
        .{ .a = .{ .b = .{ .c = false } } },
        "\"Not Here\" == \"Not Here\"",
    );
}

// Dotted names that cannot be resolved should be considered falsey.
test "spec:inverted: Dotted Names - Broken Chains" {
    try h.expectRender(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"Not Here\"",
        &.{},
        .{ .a = .{} },
        "\"Not Here\" == \"Not Here\"",
    );
    try h.expectRenderComptime(
        "\"{{^a.b.c}}Not Here{{/a.b.c}}\" == \"Not Here\"",
        &.{},
        .{ .a = .{} },
        "\"Not Here\" == \"Not Here\"",
    );
}

// Inverted sections should not alter surrounding whitespace.
test "spec:inverted: Surrounding Whitespace" {
    try h.expectRender(
        " | {{^boolean}}\t|\t{{/boolean}} | \n",
        &.{},
        .{ .boolean = false },
        " | \t|\t | \n",
    );
    try h.expectRenderComptime(
        " | {{^boolean}}\t|\t{{/boolean}} | \n",
        &.{},
        .{ .boolean = false },
        " | \t|\t | \n",
    );
}

// Inverted should not alter internal whitespace.
test "spec:inverted: Internal Whitespace" {
    try h.expectRender(
        " | {{^boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n",
        &.{},
        .{ .boolean = false },
        " |  \n  | \n",
    );
    try h.expectRenderComptime(
        " | {{^boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n",
        &.{},
        .{ .boolean = false },
        " |  \n  | \n",
    );
}

// Single-line sections should not alter surrounding whitespace.
test "spec:inverted: Indented Inline Sections" {
    try h.expectRender(
        " {{^boolean}}NO{{/boolean}}\n {{^boolean}}WAY{{/boolean}}\n",
        &.{},
        .{ .boolean = false },
        " NO\n WAY\n",
    );
    try h.expectRenderComptime(
        " {{^boolean}}NO{{/boolean}}\n {{^boolean}}WAY{{/boolean}}\n",
        &.{},
        .{ .boolean = false },
        " NO\n WAY\n",
    );
}

// Standalone lines should be removed from the template.
test "spec:inverted: Standalone Lines" {
    try h.expectRender(
        "| This Is\n{{^boolean}}\n|\n{{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = false },
        "| This Is\n|\n| A Line\n",
    );
    try h.expectRenderComptime(
        "| This Is\n{{^boolean}}\n|\n{{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = false },
        "| This Is\n|\n| A Line\n",
    );
}

// Standalone indented lines should be removed from the template.
test "spec:inverted: Standalone Indented Lines" {
    try h.expectRender(
        "| This Is\n  {{^boolean}}\n|\n  {{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = false },
        "| This Is\n|\n| A Line\n",
    );
    try h.expectRenderComptime(
        "| This Is\n  {{^boolean}}\n|\n  {{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = false },
        "| This Is\n|\n| A Line\n",
    );
}

// "\r\n" should be considered a newline for standalone tags.
test "spec:inverted: Standalone Line Endings" {
    try h.expectRender(
        "|\r\n{{^boolean}}\r\n{{/boolean}}\r\n|",
        &.{},
        .{ .boolean = false },
        "|\r\n|",
    );
    try h.expectRenderComptime(
        "|\r\n{{^boolean}}\r\n{{/boolean}}\r\n|",
        &.{},
        .{ .boolean = false },
        "|\r\n|",
    );
}

// Standalone tags should not require a newline to precede them.
test "spec:inverted: Standalone Without Previous Line" {
    try h.expectRender(
        "  {{^boolean}}\n^{{/boolean}}\n/",
        &.{},
        .{ .boolean = false },
        "^\n/",
    );
    try h.expectRenderComptime(
        "  {{^boolean}}\n^{{/boolean}}\n/",
        &.{},
        .{ .boolean = false },
        "^\n/",
    );
}

// Standalone tags should not require a newline to follow them.
test "spec:inverted: Standalone Without Newline" {
    try h.expectRender(
        "^{{^boolean}}\n/\n  {{/boolean}}",
        &.{},
        .{ .boolean = false },
        "^\n/\n",
    );
    try h.expectRenderComptime(
        "^{{^boolean}}\n/\n  {{/boolean}}",
        &.{},
        .{ .boolean = false },
        "^\n/\n",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:inverted: Padding" {
    try h.expectRender(
        "|{{^ boolean }}={{/ boolean }}|",
        &.{},
        .{ .boolean = false },
        "|=|",
    );
    try h.expectRenderComptime(
        "|{{^ boolean }}={{/ boolean }}|",
        &.{},
        .{ .boolean = false },
        "|=|",
    );
}
