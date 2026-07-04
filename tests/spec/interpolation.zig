//! Test cases from the official mustache spec (mustache/spec, specs/interpolation.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// Mustache-free templates should render as-is.
test "spec:interpolation: No Interpolation" {
    try h.expectRender(
        "Hello from {Mustache}!\n",
        &.{},
        .{},
        "Hello from {Mustache}!\n",
    );
    try h.expectRenderComptime(
        "Hello from {Mustache}!\n",
        &.{},
        .{},
        "Hello from {Mustache}!\n",
    );
}

// Unadorned tags should interpolate content into the template.
test "spec:interpolation: Basic Interpolation" {
    try h.expectRender(
        "Hello, {{subject}}!\n",
        &.{},
        .{ .subject = "world" },
        "Hello, world!\n",
    );
    try h.expectRenderComptime(
        "Hello, {{subject}}!\n",
        &.{},
        .{ .subject = "world" },
        "Hello, world!\n",
    );
}

// Interpolated tag output should not be re-interpolated.
test "spec:interpolation: No Re-interpolation" {
    try h.expectRender(
        "{{template}}: {{planet}}",
        &.{},
        .{ .template = "{{planet}}", .planet = "Earth" },
        "{{planet}}: Earth",
    );
    try h.expectRenderComptime(
        "{{template}}: {{planet}}",
        &.{},
        .{ .template = "{{planet}}", .planet = "Earth" },
        "{{planet}}: Earth",
    );
}

// Basic interpolation should be HTML escaped.
test "spec:interpolation: HTML Escaping" {
    try h.expectRender(
        "These characters should be HTML escaped: {{forbidden}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should be HTML escaped: &amp; &quot; &lt; &gt;\n",
    );
    try h.expectRenderComptime(
        "These characters should be HTML escaped: {{forbidden}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should be HTML escaped: &amp; &quot; &lt; &gt;\n",
    );
}

// Triple mustaches should interpolate without HTML escaping.
test "spec:interpolation: Triple Mustache" {
    try h.expectRender(
        "These characters should not be HTML escaped: {{{forbidden}}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should not be HTML escaped: & \" < >\n",
    );
    try h.expectRenderComptime(
        "These characters should not be HTML escaped: {{{forbidden}}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should not be HTML escaped: & \" < >\n",
    );
}

// Ampersand should interpolate without HTML escaping.
test "spec:interpolation: Ampersand" {
    try h.expectRender(
        "These characters should not be HTML escaped: {{&forbidden}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should not be HTML escaped: & \" < >\n",
    );
    try h.expectRenderComptime(
        "These characters should not be HTML escaped: {{&forbidden}}\n",
        &.{},
        .{ .forbidden = "& \" < >" },
        "These characters should not be HTML escaped: & \" < >\n",
    );
}

// Integers should interpolate seamlessly.
test "spec:interpolation: Basic Integer Interpolation" {
    try h.expectRender(
        "\"{{mph}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
    try h.expectRenderComptime(
        "\"{{mph}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
}

// Integers should interpolate seamlessly.
test "spec:interpolation: Triple Mustache Integer Interpolation" {
    try h.expectRender(
        "\"{{{mph}}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
    try h.expectRenderComptime(
        "\"{{{mph}}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
}

// Integers should interpolate seamlessly.
test "spec:interpolation: Ampersand Integer Interpolation" {
    try h.expectRender(
        "\"{{&mph}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
    try h.expectRenderComptime(
        "\"{{&mph}} miles an hour!\"",
        &.{},
        .{ .mph = 85 },
        "\"85 miles an hour!\"",
    );
}

// Decimals should interpolate seamlessly with proper significance.
test "spec:interpolation: Basic Decimal Interpolation" {
    try h.expectRender(
        "\"{{power}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
    try h.expectRenderComptime(
        "\"{{power}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
}

// Decimals should interpolate seamlessly with proper significance.
test "spec:interpolation: Triple Mustache Decimal Interpolation" {
    try h.expectRender(
        "\"{{{power}}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
    try h.expectRenderComptime(
        "\"{{{power}}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
}

// Decimals should interpolate seamlessly with proper significance.
test "spec:interpolation: Ampersand Decimal Interpolation" {
    try h.expectRender(
        "\"{{&power}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
    try h.expectRenderComptime(
        "\"{{&power}} jiggawatts!\"",
        &.{},
        .{ .power = 1.21 },
        "\"1.21 jiggawatts!\"",
    );
}

// Nulls should interpolate as the empty string.
test "spec:interpolation: Basic Null Interpolation" {
    try h.expectRender(
        "I ({{cannot}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{cannot}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
}

// Nulls should interpolate as the empty string.
test "spec:interpolation: Triple Mustache Null Interpolation" {
    try h.expectRender(
        "I ({{{cannot}}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{{cannot}}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
}

// Nulls should interpolate as the empty string.
test "spec:interpolation: Ampersand Null Interpolation" {
    try h.expectRender(
        "I ({{&cannot}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{&cannot}}) be seen!",
        &.{},
        .{ .cannot = null },
        "I () be seen!",
    );
}

// Failed context lookups should default to empty strings.
test "spec:interpolation: Basic Context Miss Interpolation" {
    try h.expectRender(
        "I ({{cannot}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{cannot}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
}

// Failed context lookups should default to empty strings.
test "spec:interpolation: Triple Mustache Context Miss Interpolation" {
    try h.expectRender(
        "I ({{{cannot}}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{{cannot}}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
}

// Failed context lookups should default to empty strings.
test "spec:interpolation: Ampersand Context Miss Interpolation" {
    try h.expectRender(
        "I ({{&cannot}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
    try h.expectRenderComptime(
        "I ({{&cannot}}) be seen!",
        &.{},
        .{},
        "I () be seen!",
    );
}

// Dotted names should be considered a form of shorthand for sections.
test "spec:interpolation: Dotted Names - Basic Interpolation" {
    try h.expectRender(
        "\"{{person.name}}\" == \"{{#person}}{{name}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
    try h.expectRenderComptime(
        "\"{{person.name}}\" == \"{{#person}}{{name}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
}

// Dotted names should be considered a form of shorthand for sections.
test "spec:interpolation: Dotted Names - Triple Mustache Interpolation" {
    try h.expectRender(
        "\"{{{person.name}}}\" == \"{{#person}}{{{name}}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
    try h.expectRenderComptime(
        "\"{{{person.name}}}\" == \"{{#person}}{{{name}}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
}

// Dotted names should be considered a form of shorthand for sections.
test "spec:interpolation: Dotted Names - Ampersand Interpolation" {
    try h.expectRender(
        "\"{{&person.name}}\" == \"{{#person}}{{&name}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
    try h.expectRenderComptime(
        "\"{{&person.name}}\" == \"{{#person}}{{&name}}{{/person}}\"",
        &.{},
        .{ .person = .{ .name = "Joe" } },
        "\"Joe\" == \"Joe\"",
    );
}

// Dotted names should be functional to any level of nesting.
test "spec:interpolation: Dotted Names - Arbitrary Depth" {
    try h.expectRender(
        "\"{{a.b.c.d.e.name}}\" == \"Phil\"",
        &.{},
        .{ .a = .{ .b = .{ .c = .{ .d = .{ .e = .{ .name = "Phil" } } } } } },
        "\"Phil\" == \"Phil\"",
    );
    try h.expectRenderComptime(
        "\"{{a.b.c.d.e.name}}\" == \"Phil\"",
        &.{},
        .{ .a = .{ .b = .{ .c = .{ .d = .{ .e = .{ .name = "Phil" } } } } } },
        "\"Phil\" == \"Phil\"",
    );
}

// Any falsey value prior to the last part of the name should yield ''.
test "spec:interpolation: Dotted Names - Broken Chains" {
    try h.expectRender(
        "\"{{a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{} },
        "\"\" == \"\"",
    );
    try h.expectRenderComptime(
        "\"{{a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{} },
        "\"\" == \"\"",
    );
}

// Each part of a dotted name should resolve only against its parent.
test "spec:interpolation: Dotted Names - Broken Chain Resolution" {
    try h.expectRender(
        "\"{{a.b.c.name}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{} }, .c = .{ .name = "Jim" } },
        "\"\" == \"\"",
    );
    try h.expectRenderComptime(
        "\"{{a.b.c.name}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{} }, .c = .{ .name = "Jim" } },
        "\"\" == \"\"",
    );
}

// The first part of a dotted name should resolve as any other name.
test "spec:interpolation: Dotted Names - Initial Resolution" {
    try h.expectRender(
        "\"{{#a}}{{b.c.d.e.name}}{{/a}}\" == \"Phil\"",
        &.{},
        .{ .a = .{ .b = .{ .c = .{ .d = .{ .e = .{ .name = "Phil" } } } } }, .b = .{ .c = .{ .d = .{ .e = .{ .name = "Wrong" } } } } },
        "\"Phil\" == \"Phil\"",
    );
    try h.expectRenderComptime(
        "\"{{#a}}{{b.c.d.e.name}}{{/a}}\" == \"Phil\"",
        &.{},
        .{ .a = .{ .b = .{ .c = .{ .d = .{ .e = .{ .name = "Phil" } } } } }, .b = .{ .c = .{ .d = .{ .e = .{ .name = "Wrong" } } } } },
        "\"Phil\" == \"Phil\"",
    );
}

// Dotted names should be resolved against former resolutions.
test "spec:interpolation: Dotted Names - Context Precedence" {
    try h.expectRender(
        "{{#a}}{{b.c}}{{/a}}",
        &.{},
        .{ .a = .{ .b = .{} }, .b = .{ .c = "ERROR" } },
        "",
    );
    try h.expectRenderComptime(
        "{{#a}}{{b.c}}{{/a}}",
        &.{},
        .{ .a = .{ .b = .{} }, .b = .{ .c = "ERROR" } },
        "",
    );
}

// Dotted names shall not be parsed as single, atomic keys
test "spec:interpolation: Dotted Names are never single keys" {
    try h.expectRender(
        "{{a.b}}",
        &.{},
        .{ .@"a.b" = "c" },
        "",
    );
    try h.expectRenderComptime(
        "{{a.b}}",
        &.{},
        .{ .@"a.b" = "c" },
        "",
    );
}

// Dotted Names in a given context are unvavailable due to dot splitting
test "spec:interpolation: Dotted Names - No Masking" {
    try h.expectRender(
        "{{a.b}}",
        &.{},
        .{ .@"a.b" = "c", .a = .{ .b = "d" } },
        "d",
    );
    try h.expectRenderComptime(
        "{{a.b}}",
        &.{},
        .{ .@"a.b" = "c", .a = .{ .b = "d" } },
        "d",
    );
}

// Unadorned tags should interpolate content into the template.
test "spec:interpolation: Implicit Iterators - Basic Interpolation" {
    try h.expectRender(
        "Hello, {{.}}!\n",
        &.{},
        "world",
        "Hello, world!\n",
    );
    try h.expectRenderComptime(
        "Hello, {{.}}!\n",
        &.{},
        "world",
        "Hello, world!\n",
    );
}

// Basic interpolation should be HTML escaped.
test "spec:interpolation: Implicit Iterators - HTML Escaping" {
    try h.expectRender(
        "These characters should be HTML escaped: {{.}}\n",
        &.{},
        "& \" < >",
        "These characters should be HTML escaped: &amp; &quot; &lt; &gt;\n",
    );
    try h.expectRenderComptime(
        "These characters should be HTML escaped: {{.}}\n",
        &.{},
        "& \" < >",
        "These characters should be HTML escaped: &amp; &quot; &lt; &gt;\n",
    );
}

// Triple mustaches should interpolate without HTML escaping.
test "spec:interpolation: Implicit Iterators - Triple Mustache" {
    try h.expectRender(
        "These characters should not be HTML escaped: {{{.}}}\n",
        &.{},
        "& \" < >",
        "These characters should not be HTML escaped: & \" < >\n",
    );
    try h.expectRenderComptime(
        "These characters should not be HTML escaped: {{{.}}}\n",
        &.{},
        "& \" < >",
        "These characters should not be HTML escaped: & \" < >\n",
    );
}

// Ampersand should interpolate without HTML escaping.
test "spec:interpolation: Implicit Iterators - Ampersand" {
    try h.expectRender(
        "These characters should not be HTML escaped: {{&.}}\n",
        &.{},
        "& \" < >",
        "These characters should not be HTML escaped: & \" < >\n",
    );
    try h.expectRenderComptime(
        "These characters should not be HTML escaped: {{&.}}\n",
        &.{},
        "& \" < >",
        "These characters should not be HTML escaped: & \" < >\n",
    );
}

// Integers should interpolate seamlessly.
test "spec:interpolation: Implicit Iterators - Basic Integer Interpolation" {
    try h.expectRender(
        "\"{{.}} miles an hour!\"",
        &.{},
        85,
        "\"85 miles an hour!\"",
    );
    try h.expectRenderComptime(
        "\"{{.}} miles an hour!\"",
        &.{},
        85,
        "\"85 miles an hour!\"",
    );
}

// Interpolation should not alter surrounding whitespace.
test "spec:interpolation: Interpolation - Surrounding Whitespace" {
    try h.expectRender(
        "| {{string}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
    try h.expectRenderComptime(
        "| {{string}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
}

// Interpolation should not alter surrounding whitespace.
test "spec:interpolation: Triple Mustache - Surrounding Whitespace" {
    try h.expectRender(
        "| {{{string}}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
    try h.expectRenderComptime(
        "| {{{string}}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
}

// Interpolation should not alter surrounding whitespace.
test "spec:interpolation: Ampersand - Surrounding Whitespace" {
    try h.expectRender(
        "| {{&string}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
    try h.expectRenderComptime(
        "| {{&string}} |",
        &.{},
        .{ .string = "---" },
        "| --- |",
    );
}

// Standalone interpolation should not alter surrounding whitespace.
test "spec:interpolation: Interpolation - Standalone" {
    try h.expectRender(
        "  {{string}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
    try h.expectRenderComptime(
        "  {{string}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
}

// Standalone interpolation should not alter surrounding whitespace.
test "spec:interpolation: Triple Mustache - Standalone" {
    try h.expectRender(
        "  {{{string}}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
    try h.expectRenderComptime(
        "  {{{string}}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
}

// Standalone interpolation should not alter surrounding whitespace.
test "spec:interpolation: Ampersand - Standalone" {
    try h.expectRender(
        "  {{&string}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
    try h.expectRenderComptime(
        "  {{&string}}\n",
        &.{},
        .{ .string = "---" },
        "  ---\n",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:interpolation: Interpolation With Padding" {
    try h.expectRender(
        "|{{ string }}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
    try h.expectRenderComptime(
        "|{{ string }}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:interpolation: Triple Mustache With Padding" {
    try h.expectRender(
        "|{{{ string }}}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
    try h.expectRenderComptime(
        "|{{{ string }}}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:interpolation: Ampersand With Padding" {
    try h.expectRender(
        "|{{& string }}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
    try h.expectRenderComptime(
        "|{{& string }}|",
        &.{},
        .{ .string = "---" },
        "|---|",
    );
}
