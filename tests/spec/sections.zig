//! Test cases from the official mustache spec (mustache/spec, specs/sections.yml),
//! converted to Zig. Maintained by hand.

const h = @import("../helper.zig");

// Truthy sections should have their contents rendered.
test "spec:sections: Truthy" {
    try h.expectRender(
        "\"{{#boolean}}This should be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = true },
        "\"This should be rendered.\"",
    );
    try h.expectRenderComptime(
        "\"{{#boolean}}This should be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = true },
        "\"This should be rendered.\"",
    );
}

// Falsey sections should have their contents omitted.
test "spec:sections: Falsey" {
    try h.expectRender(
        "\"{{#boolean}}This should not be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = false },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{#boolean}}This should not be rendered.{{/boolean}}\"",
        &.{},
        .{ .boolean = false },
        "\"\"",
    );
}

// Null is falsey.
test "spec:sections: Null is falsey" {
    try h.expectRender(
        "\"{{#null}}This should not be rendered.{{/null}}\"",
        &.{},
        .{ .null = null },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{#null}}This should not be rendered.{{/null}}\"",
        &.{},
        .{ .null = null },
        "\"\"",
    );
}

// Objects and hashes should be pushed onto the context stack.
test "spec:sections: Context" {
    try h.expectRender(
        "\"{{#context}}Hi {{name}}.{{/context}}\"",
        &.{},
        .{ .context = .{ .name = "Joe" } },
        "\"Hi Joe.\"",
    );
    try h.expectRenderComptime(
        "\"{{#context}}Hi {{name}}.{{/context}}\"",
        &.{},
        .{ .context = .{ .name = "Joe" } },
        "\"Hi Joe.\"",
    );
}

// Names missing in the current context are looked up in the stack.
test "spec:sections: Parent contexts" {
    try h.expectRender(
        "\"{{#sec}}{{a}}, {{b}}, {{c.d}}{{/sec}}\"",
        &.{},
        .{ .a = "foo", .b = "wrong", .sec = .{ .b = "bar" }, .c = .{ .d = "baz" } },
        "\"foo, bar, baz\"",
    );
    try h.expectRenderComptime(
        "\"{{#sec}}{{a}}, {{b}}, {{c.d}}{{/sec}}\"",
        &.{},
        .{ .a = "foo", .b = "wrong", .sec = .{ .b = "bar" }, .c = .{ .d = "baz" } },
        "\"foo, bar, baz\"",
    );
}

// Non-false sections have their value at the top of context, accessible as {{.}} or through the parent context. This gives a simple way to display content conditionally if a variable exists.
test "spec:sections: Variable test" {
    try h.expectRender(
        "\"{{#foo}}{{.}} is {{foo}}{{/foo}}\"",
        &.{},
        .{ .foo = "bar" },
        "\"bar is bar\"",
    );
    try h.expectRenderComptime(
        "\"{{#foo}}{{.}} is {{foo}}{{/foo}}\"",
        &.{},
        .{ .foo = "bar" },
        "\"bar is bar\"",
    );
}

// All elements on the context stack should be accessible within lists.
test "spec:sections: List Contexts" {
    try h.expectRender(
        "{{#tops}}{{#middles}}{{tname.lower}}{{mname}}.{{#bottoms}}{{tname.upper}}{{mname}}{{bname}}.{{/bottoms}}{{/middles}}{{/tops}}",
        &.{},
        .{ .tops = .{.{ .tname = .{ .upper = "A", .lower = "a" }, .middles = .{.{ .mname = "1", .bottoms = .{ .{ .bname = "x" }, .{ .bname = "y" } } }} }} },
        "a1.A1x.A1y.",
    );
    try h.expectRenderComptime(
        "{{#tops}}{{#middles}}{{tname.lower}}{{mname}}.{{#bottoms}}{{tname.upper}}{{mname}}{{bname}}.{{/bottoms}}{{/middles}}{{/tops}}",
        &.{},
        .{ .tops = .{.{ .tname = .{ .upper = "A", .lower = "a" }, .middles = .{.{ .mname = "1", .bottoms = .{ .{ .bname = "x" }, .{ .bname = "y" } } }} }} },
        "a1.A1x.A1y.",
    );
}

// All elements on the context stack should be accessible.
test "spec:sections: Deeply Nested Contexts" {
    try h.expectRender(
        "{{#a}}\n{{one}}\n{{#b}}\n{{one}}{{two}}{{one}}\n{{#c}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{#d}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{#five}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{.}}6{{.}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{/five}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{/d}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{/c}}\n{{one}}{{two}}{{one}}\n{{/b}}\n{{one}}\n{{/a}}\n",
        &.{},
        .{ .a = .{ .one = 1 }, .b = .{ .two = 2 }, .c = .{ .three = 3, .d = .{ .four = 4, .five = 5 } } },
        "1\n121\n12321\n1234321\n123454321\n12345654321\n123454321\n1234321\n12321\n121\n1\n",
    );
    try h.expectRenderComptime(
        "{{#a}}\n{{one}}\n{{#b}}\n{{one}}{{two}}{{one}}\n{{#c}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{#d}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{#five}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{.}}6{{.}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{/five}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{/d}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{/c}}\n{{one}}{{two}}{{one}}\n{{/b}}\n{{one}}\n{{/a}}\n",
        &.{},
        .{ .a = .{ .one = 1 }, .b = .{ .two = 2 }, .c = .{ .three = 3, .d = .{ .four = 4, .five = 5 } } },
        "1\n121\n12321\n1234321\n123454321\n12345654321\n123454321\n1234321\n12321\n121\n1\n",
    );
}

// Lists should be iterated; list items should visit the context stack.
test "spec:sections: List" {
    try h.expectRender(
        "\"{{#list}}{{item}}{{/list}}\"",
        &.{},
        .{ .list = .{ .{ .item = 1 }, .{ .item = 2 }, .{ .item = 3 } } },
        "\"123\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}{{item}}{{/list}}\"",
        &.{},
        .{ .list = .{ .{ .item = 1 }, .{ .item = 2 }, .{ .item = 3 } } },
        "\"123\"",
    );
}

// Empty lists should behave like falsey values.
test "spec:sections: Empty List" {
    try h.expectRender(
        "\"{{#list}}Yay lists!{{/list}}\"",
        &.{},
        .{ .list = [0]bool{} },
        "\"\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}Yay lists!{{/list}}\"",
        &.{},
        .{ .list = [0]bool{} },
        "\"\"",
    );
}

// Multiple sections per template should be permitted.
test "spec:sections: Doubled" {
    try h.expectRender(
        "{{#bool}}\n* first\n{{/bool}}\n* {{two}}\n{{#bool}}\n* third\n{{/bool}}\n",
        &.{},
        .{ .bool = true, .two = "second" },
        "* first\n* second\n* third\n",
    );
    try h.expectRenderComptime(
        "{{#bool}}\n* first\n{{/bool}}\n* {{two}}\n{{#bool}}\n* third\n{{/bool}}\n",
        &.{},
        .{ .bool = true, .two = "second" },
        "* first\n* second\n* third\n",
    );
}

// Nested truthy sections should have their contents rendered.
test "spec:sections: Nested (Truthy)" {
    try h.expectRender(
        "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = true },
        "| A B C D E |",
    );
    try h.expectRenderComptime(
        "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = true },
        "| A B C D E |",
    );
}

// Nested falsey sections should be omitted.
test "spec:sections: Nested (Falsey)" {
    try h.expectRender(
        "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = false },
        "| A  E |",
    );
    try h.expectRenderComptime(
        "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |",
        &.{},
        .{ .bool = false },
        "| A  E |",
    );
}

// Failed context lookups should be considered falsey.
test "spec:sections: Context Misses" {
    try h.expectRender(
        "[{{#missing}}Found key 'missing'!{{/missing}}]",
        &.{},
        .{},
        "[]",
    );
    try h.expectRenderComptime(
        "[{{#missing}}Found key 'missing'!{{/missing}}]",
        &.{},
        .{},
        "[]",
    );
}

// Implicit iterators should directly interpolate strings.
test "spec:sections: Implicit Iterator - String" {
    try h.expectRender(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "a", "b", "c", "d", "e" } },
        "\"(a)(b)(c)(d)(e)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "a", "b", "c", "d", "e" } },
        "\"(a)(b)(c)(d)(e)\"",
    );
}

// Implicit iterators should cast integers to strings and interpolate.
test "spec:sections: Implicit Iterator - Integer" {
    try h.expectRender(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ 1, 2, 3, 4, 5 } },
        "\"(1)(2)(3)(4)(5)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ 1, 2, 3, 4, 5 } },
        "\"(1)(2)(3)(4)(5)\"",
    );
}

// Implicit iterators should cast decimals to strings and interpolate.
test "spec:sections: Implicit Iterator - Decimal" {
    try h.expectRender(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ 1.1, 2.2, 3.3, 4.4, 5.5 } },
        "\"(1.1)(2.2)(3.3)(4.4)(5.5)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ 1.1, 2.2, 3.3, 4.4, 5.5 } },
        "\"(1.1)(2.2)(3.3)(4.4)(5.5)\"",
    );
}

// Implicit iterators should allow iterating over nested arrays.
test "spec:sections: Implicit Iterator - Array" {
    try h.expectRender(
        "\"{{#list}}({{#.}}{{.}}{{/.}}){{/list}}\"",
        &.{},
        .{ .list = .{ .{ 1, 2, 3 }, .{ "a", "b", "c" } } },
        "\"(123)(abc)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{#.}}{{.}}{{/.}}){{/list}}\"",
        &.{},
        .{ .list = .{ .{ 1, 2, 3 }, .{ "a", "b", "c" } } },
        "\"(123)(abc)\"",
    );
}

// Implicit iterators with basic interpolation should be HTML escaped.
test "spec:sections: Implicit Iterator - HTML Escaping" {
    try h.expectRender(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&amp;)(&quot;)(&lt;)(&gt;)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&amp;)(&quot;)(&lt;)(&gt;)\"",
    );
}

// Implicit iterators in triple mustache should interpolate without HTML escaping.
test "spec:sections: Implicit Iterator - Triple mustache" {
    try h.expectRender(
        "\"{{#list}}({{{.}}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&)(\")(<)(>)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{{.}}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&)(\")(<)(>)\"",
    );
}

// Implicit iterators in an Ampersand tag should interpolate without HTML escaping.
test "spec:sections: Implicit Iterator - Ampersand" {
    try h.expectRender(
        "\"{{#list}}({{&.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&)(\")(<)(>)\"",
    );
    try h.expectRenderComptime(
        "\"{{#list}}({{&.}}){{/list}}\"",
        &.{},
        .{ .list = .{ "&", "\"", "<", ">" } },
        "\"(&)(\")(<)(>)\"",
    );
}

// Implicit iterators should work on root-level lists.
test "spec:sections: Implicit Iterator - Root-level" {
    try h.expectRender(
        "\"{{#.}}({{value}}){{/.}}\"",
        &.{},
        .{ .{ .value = "a" }, .{ .value = "b" } },
        "\"(a)(b)\"",
    );
    try h.expectRenderComptime(
        "\"{{#.}}({{value}}){{/.}}\"",
        &.{},
        .{ .{ .value = "a" }, .{ .value = "b" } },
        "\"(a)(b)\"",
    );
}

// Dotted names should be valid for Section tags.
test "spec:sections: Dotted Names - Truthy" {
    try h.expectRender(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"Here\"",
        &.{},
        .{ .a = .{ .b = .{ .c = true } } },
        "\"Here\" == \"Here\"",
    );
    try h.expectRenderComptime(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"Here\"",
        &.{},
        .{ .a = .{ .b = .{ .c = true } } },
        "\"Here\" == \"Here\"",
    );
}

// Dotted names should be valid for Section tags.
test "spec:sections: Dotted Names - Falsey" {
    try h.expectRender(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{ .c = false } } },
        "\"\" == \"\"",
    );
    try h.expectRenderComptime(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{ .b = .{ .c = false } } },
        "\"\" == \"\"",
    );
}

// Dotted names that cannot be resolved should be considered falsey.
test "spec:sections: Dotted Names - Broken Chains" {
    try h.expectRender(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{} },
        "\"\" == \"\"",
    );
    try h.expectRenderComptime(
        "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"",
        &.{},
        .{ .a = .{} },
        "\"\" == \"\"",
    );
}

// Sections should not alter surrounding whitespace.
test "spec:sections: Surrounding Whitespace" {
    try h.expectRender(
        " | {{#boolean}}\t|\t{{/boolean}} | \n",
        &.{},
        .{ .boolean = true },
        " | \t|\t | \n",
    );
    try h.expectRenderComptime(
        " | {{#boolean}}\t|\t{{/boolean}} | \n",
        &.{},
        .{ .boolean = true },
        " | \t|\t | \n",
    );
}

// Sections should not alter internal whitespace.
test "spec:sections: Internal Whitespace" {
    try h.expectRender(
        " | {{#boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n",
        &.{},
        .{ .boolean = true },
        " |  \n  | \n",
    );
    try h.expectRenderComptime(
        " | {{#boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n",
        &.{},
        .{ .boolean = true },
        " |  \n  | \n",
    );
}

// Single-line sections should not alter surrounding whitespace.
test "spec:sections: Indented Inline Sections" {
    try h.expectRender(
        " {{#boolean}}YES{{/boolean}}\n {{#boolean}}GOOD{{/boolean}}\n",
        &.{},
        .{ .boolean = true },
        " YES\n GOOD\n",
    );
    try h.expectRenderComptime(
        " {{#boolean}}YES{{/boolean}}\n {{#boolean}}GOOD{{/boolean}}\n",
        &.{},
        .{ .boolean = true },
        " YES\n GOOD\n",
    );
}

// Standalone lines should be removed from the template.
test "spec:sections: Standalone Lines" {
    try h.expectRender(
        "| This Is\n{{#boolean}}\n|\n{{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = true },
        "| This Is\n|\n| A Line\n",
    );
    try h.expectRenderComptime(
        "| This Is\n{{#boolean}}\n|\n{{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = true },
        "| This Is\n|\n| A Line\n",
    );
}

// Indented standalone lines should be removed from the template.
test "spec:sections: Indented Standalone Lines" {
    try h.expectRender(
        "| This Is\n  {{#boolean}}\n|\n  {{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = true },
        "| This Is\n|\n| A Line\n",
    );
    try h.expectRenderComptime(
        "| This Is\n  {{#boolean}}\n|\n  {{/boolean}}\n| A Line\n",
        &.{},
        .{ .boolean = true },
        "| This Is\n|\n| A Line\n",
    );
}

// "\r\n" should be considered a newline for standalone tags.
test "spec:sections: Standalone Line Endings" {
    try h.expectRender(
        "|\r\n{{#boolean}}\r\n{{/boolean}}\r\n|",
        &.{},
        .{ .boolean = true },
        "|\r\n|",
    );
    try h.expectRenderComptime(
        "|\r\n{{#boolean}}\r\n{{/boolean}}\r\n|",
        &.{},
        .{ .boolean = true },
        "|\r\n|",
    );
}

// Standalone tags should not require a newline to precede them.
test "spec:sections: Standalone Without Previous Line" {
    try h.expectRender(
        "  {{#boolean}}\n#{{/boolean}}\n/",
        &.{},
        .{ .boolean = true },
        "#\n/",
    );
    try h.expectRenderComptime(
        "  {{#boolean}}\n#{{/boolean}}\n/",
        &.{},
        .{ .boolean = true },
        "#\n/",
    );
}

// Standalone tags should not require a newline to follow them.
test "spec:sections: Standalone Without Newline" {
    try h.expectRender(
        "#{{#boolean}}\n/\n  {{/boolean}}",
        &.{},
        .{ .boolean = true },
        "#\n/\n",
    );
    try h.expectRenderComptime(
        "#{{#boolean}}\n/\n  {{/boolean}}",
        &.{},
        .{ .boolean = true },
        "#\n/\n",
    );
}

// Superfluous in-tag whitespace should be ignored.
test "spec:sections: Padding" {
    try h.expectRender(
        "|{{# boolean }}={{/ boolean }}|",
        &.{},
        .{ .boolean = true },
        "|=|",
    );
    try h.expectRenderComptime(
        "|{{# boolean }}={{/ boolean }}|",
        &.{},
        .{ .boolean = true },
        "|=|",
    );
}
