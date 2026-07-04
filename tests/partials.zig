//! mustache.js partial tests: the `test/_files` render fixtures and the
//! dedicated partials suite (`test/partial-test.js`).
//!
//! Templates and expected outputs are transcribed byte-exactly; data is
//! translated from JS object literals to Zig struct literals, with
//! constant-returning functions replaced by their value and `undefined`/
//! `null` becoming optional-null. Deviations from the original expected
//! output are commented in place. Everything runs through the shared
//! helpers, so each case is checked against both the runtime and comptime
//! parsers.
//!
//! Skipped: section_functions_in_partials and the two "should inherit
//! functions" suite cases (lambdas, unsupported); cli, cli_with_partials,
//! cli_js_view_with_function (mustache.js CLI harness); malicious_template
//! (JS code injection; the unresolved partial just renders as the empty
//! string here).

const std = @import("std");
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;
const expectRenderPartial = h.expectRenderPartial;
const expectRenderPartialComptime = h.expectRenderPartialComptime;

// -- Render fixtures (test/_files) --------------------------------------------

test "mustachejs: included_tag" {
    try expectRender(
        "You said \"{{{html}}}\" today\n",
        &.{},
        .{ .html = "I like {{mustache}}" },
        "You said \"I like {{mustache}}\" today\n",
    );
    try expectRenderComptime(
        "You said \"{{{html}}}\" today\n",
        &.{},
        .{ .html = "I like {{mustache}}" },
        "You said \"I like {{mustache}}\" today\n",
    );
}

test "mustachejs: partial_template" {
    // `title` was a constant-returning function.
    try expectRenderPartial(
        "<h1>{{title}}</h1>\n{{>partial}}\n",
        "Again, {{again}}!\n",
        .{ .title = "Welcome", .again = "Goodbye" },
        "<h1>Welcome</h1>\nAgain, Goodbye!\n",
    );
    try expectRenderPartialComptime(
        "<h1>{{title}}</h1>\n{{>partial}}\n",
        "Again, {{again}}!\n",
        .{ .title = "Welcome", .again = "Goodbye" },
        "<h1>Welcome</h1>\nAgain, Goodbye!\n",
    );
}

test "mustachejs: partial_view" {
    // `greeting`, `farewell` and `taxed_value` were constant functions.
    try expectRenderPartial(
        "<h1>{{greeting}}</h1>\n{{>partial}}\n<h3>{{farewell}}</h3>\n",
        \\Hello {{name}}
        \\You have just won ${{value}}!
        \\{{#in_ca}}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/in_ca}}
    ,
        .{
            .greeting = "Welcome",
            .farewell = "Fair enough, right?",
            .name = "Chris",
            .value = 10000,
            .taxed_value = 6000,
            .in_ca = true,
        },
        \\<h1>Welcome</h1>
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
        \\<h3>Fair enough, right?</h3>
    ++ "\n");
    try expectRenderPartialComptime(
        "<h1>{{greeting}}</h1>\n{{>partial}}\n<h3>{{farewell}}</h3>\n",
        \\Hello {{name}}
        \\You have just won ${{value}}!
        \\{{#in_ca}}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/in_ca}}
    ,
        .{
            .greeting = "Welcome",
            .farewell = "Fair enough, right?",
            .name = "Chris",
            .value = 10000,
            .taxed_value = 6000,
            .in_ca = true,
        },
        \\<h1>Welcome</h1>
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
        \\<h3>Fair enough, right?</h3>
    ++ "\n");
}

test "mustachejs: partial_array" {
    try expectRenderPartial(
        "{{>partial}}",
        \\Here's a non-sense array of values
        \\{{#array}}
        \\  {{.}}
        \\{{/array}}
    ++ "\n",
        .{ .array = [_][]const u8{ "1", "2", "3", "4" } },
        \\Here's a non-sense array of values
        \\  1
        \\  2
        \\  3
        \\  4
    ++ "\n");
    try expectRenderPartialComptime(
        "{{>partial}}",
        \\Here's a non-sense array of values
        \\{{#array}}
        \\  {{.}}
        \\{{/array}}
    ++ "\n",
        .{ .array = [_][]const u8{ "1", "2", "3", "4" } },
        \\Here's a non-sense array of values
        \\  1
        \\  2
        \\  3
        \\  4
    ++ "\n");
}

test "mustachejs: partial_array_of_partials" {
    try expectRenderPartial(
        \\Here is some stuff!
        \\{{#numbers}}
        \\{{>partial}}
        \\{{/numbers}}
    ++ "\n",
        "{{i}}\n",
        .{ .numbers = .{ .{ .i = "1" }, .{ .i = "2" }, .{ .i = "3" }, .{ .i = "4" } } },
        "Here is some stuff!\n1\n2\n3\n4\n",
    );
    try expectRenderPartialComptime(
        \\Here is some stuff!
        \\{{#numbers}}
        \\{{>partial}}
        \\{{/numbers}}
    ++ "\n",
        "{{i}}\n",
        .{ .numbers = .{ .{ .i = "1" }, .{ .i = "2" }, .{ .i = "3" }, .{ .i = "4" } } },
        "Here is some stuff!\n1\n2\n3\n4\n",
    );
}

test "mustachejs: partial_array_of_partials_implicit" {
    try expectRenderPartial(
        \\Here is some stuff!
        \\{{#numbers}}
        \\{{>partial}}
        \\{{/numbers}}
    ++ "\n",
        "{{.}}\n",
        .{ .numbers = [_][]const u8{ "1", "2", "3", "4" } },
        "Here is some stuff!\n1\n2\n3\n4\n",
    );
    try expectRenderPartialComptime(
        \\Here is some stuff!
        \\{{#numbers}}
        \\{{>partial}}
        \\{{/numbers}}
    ++ "\n",
        "{{.}}\n",
        .{ .numbers = [_][]const u8{ "1", "2", "3", "4" } },
        "Here is some stuff!\n1\n2\n3\n4\n",
    );
}

test "mustachejs: partial_empty" {
    try expectRenderPartial(
        "hey {{foo}}\n{{>partial}}\n",
        "",
        .{ .foo = 1 },
        "hey 1\n",
    );
    try expectRenderPartialComptime(
        "hey {{foo}}\n{{>partial}}\n",
        "",
        .{ .foo = 1 },
        "hey 1\n",
    );
}

test "mustachejs: partial_whitespace" {
    try expectRenderPartial(
        "<h1>{{  greeting  }}</h1>\n{{> partial }}\n<h3>{{ farewell }}</h3>\n",
        \\Hello {{ name}}
        \\You have just won ${{value }}!
        \\{{# in_ca  }}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/  in_ca }}
    ,
        .{
            .greeting = "Welcome",
            .farewell = "Fair enough, right?",
            .name = "Chris",
            .value = 10000,
            .taxed_value = 6000,
            .in_ca = true,
        },
        \\<h1>Welcome</h1>
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
        \\<h3>Fair enough, right?</h3>
    ++ "\n");
    try expectRenderPartialComptime(
        "<h1>{{  greeting  }}</h1>\n{{> partial }}\n<h3>{{ farewell }}</h3>\n",
        \\Hello {{ name}}
        \\You have just won ${{value }}!
        \\{{# in_ca  }}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/  in_ca }}
    ,
        .{
            .greeting = "Welcome",
            .farewell = "Fair enough, right?",
            .name = "Chris",
            .value = 10000,
            .taxed_value = 6000,
            .in_ca = true,
        },
        \\<h1>Welcome</h1>
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
        \\<h3>Fair enough, right?</h3>
    ++ "\n");
}

test "mustachejs: recursion_with_same_names" {
    try expectRender(
        \\{{ name }}
        \\{{ description }}
        \\
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
    ++ "\n",
        &.{},
        .{
            .name = "name",
            .description = "desc",
            .terms = .{
                .{ .name = "t1", .index = 0 },
                .{ .name = "t2", .index = 1 },
            },
        },
        \\name
        \\desc
        \\
        \\  t1
        \\  0
        \\  t2
        \\  1
    ++ "\n");
    try expectRenderComptime(
        \\{{ name }}
        \\{{ description }}
        \\
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
    ++ "\n",
        &.{},
        .{
            .name = "name",
            .description = "desc",
            .terms = .{
                .{ .name = "t1", .index = 0 },
                .{ .name = "t2", .index = 1 },
            },
        },
        \\name
        \\desc
        \\
        \\  t1
        \\  0
        \\  t2
        \\  1
    ++ "\n");
}

// -- Partials suite (test/partial-test.js): expansion & context ---------------

test "mustachejs partials: The greater-than operator should expand to the named partial." {
    try expectRender(
        "\"{{>text}}\"",
        &.{.{ .name = "text", .data = "from partial" }},
        .{},
        "\"from partial\"",
    );
    try expectRenderComptime(
        "\"{{>text}}\"",
        &.{.{ .name = "text", .data = "from partial" }},
        .{},
        "\"from partial\"",
    );
}

test "mustachejs partials: The empty string should be used when the named partial is not found." {
    try expectRender(
        "\"{{>text}}\"",
        &.{},
        .{},
        "\"\"",
    );
    try expectRenderComptime(
        "\"{{>text}}\"",
        &.{},
        .{},
        "\"\"",
    );
}

test "mustachejs partials: The greater-than operator should operate within the current context." {
    try expectRender(
        "\"{{>partial}}\"",
        &.{.{ .name = "partial", .data = "*{{text}}*" }},
        .{ .text = "content" },
        "\"*content*\"",
    );
    try expectRenderComptime(
        "\"{{>partial}}\"",
        &.{.{ .name = "partial", .data = "*{{text}}*" }},
        .{ .text = "content" },
        "\"*content*\"",
    );
}

test "mustachejs partials: Superfluous in-tag whitespace should be ignored." {
    try expectRender(
        "|{{> partial }}|",
        &.{.{ .name = "partial", .data = "[]" }},
        .{ .boolean = true },
        "|[]|",
    );
    try expectRenderComptime(
        "|{{> partial }}|",
        &.{.{ .name = "partial", .data = "[]" }},
        .{ .boolean = true },
        "|[]|",
    );
}

test "mustachejs partials: The greater-than operator should properly recurse." {
    try expectRender(
        "{{>node}}",
        &.{.{ .name = "node", .data = "{{content}}<{{#nodes}}{{>node}}{{/nodes}}>" }},
        .{ .content = "X", .nodes = .{.{ .content = "Y", .nodes = [0]bool{} }} },
        "X<Y<>>",
    );
    try expectRenderComptime(
        "{{>node}}",
        &.{.{ .name = "node", .data = "{{content}}<{{#nodes}}{{>node}}{{/nodes}}>" }},
        .{ .content = "X", .nodes = .{.{ .content = "Y", .nodes = [0]bool{} }} },
        "X<Y<>>",
    );
}

// -- Partials suite: whitespace & standalone tags -----------------------------

test "mustachejs partials: The greater-than operator should not alter surrounding whitespace." {
    try expectRender(
        "| {{>partial}} |",
        &.{.{ .name = "partial", .data = "\t|\t" }},
        .{},
        "| \t|\t |",
    );
    try expectRenderComptime(
        "| {{>partial}} |",
        &.{.{ .name = "partial", .data = "\t|\t" }},
        .{},
        "| \t|\t |",
    );
}

test "mustachejs partials: Whitespace should be left untouched." {
    try expectRender(
        "  {{data}}  {{> partial}}\n",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{ .data = "|" },
        "  |  >\n>\n",
    );
    try expectRenderComptime(
        "  {{data}}  {{> partial}}\n",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{ .data = "|" },
        "  |  >\n>\n",
    );
}

test "mustachejs partials: \"\\r\\n\" should be considered a newline for standalone tags." {
    try expectRender(
        "|\r\n{{>partial}}\r\n|",
        &.{.{ .name = "partial", .data = ">" }},
        .{},
        "|\r\n>|",
    );
    try expectRenderComptime(
        "|\r\n{{>partial}}\r\n|",
        &.{.{ .name = "partial", .data = ">" }},
        .{},
        "|\r\n>|",
    );
}

test "mustachejs partials: Standalone tags should not require a newline to precede them." {
    try expectRender(
        "  {{>partial}}\n>",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        "  >\n  >>",
    );
    try expectRenderComptime(
        "  {{>partial}}\n>",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        "  >\n  >>",
    );
}

test "mustachejs partials: Standalone tags should not require a newline to follow them." {
    try expectRender(
        ">\n  {{>partial}}",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        ">\n  >\n  >",
    );
    try expectRenderComptime(
        ">\n  {{>partial}}",
        &.{.{ .name = "partial", .data = ">\n>" }},
        .{},
        ">\n  >\n  >",
    );
}

// -- Partials suite: indentation ----------------------------------------------

test "mustachejs partials: Inline partials should not be indented" {
    try expectRender(
        "    <div>{{> partial}}</div>",
        &.{.{ .name = "partial", .data = "This is a partial." }},
        .{},
        "    <div>This is a partial.</div>",
    );
    try expectRenderComptime(
        "    <div>{{> partial}}</div>",
        &.{.{ .name = "partial", .data = "This is a partial." }},
        .{},
        "    <div>This is a partial.</div>",
    );
}

test "mustachejs partials: Inline partials should not be indented (multiline)" {
    // mustache.js column-aligns the continuation lines of an inline partial
    // when it is the first tag on its line ("    <div>This is a\n         "
    // "partial.</div>"). The mustache spec applies indentation only to
    // standalone partials, so here the continuation line stays unindented.
    try expectRender(
        "    <div>{{> partial}}</div>",
        &.{.{ .name = "partial", .data = "This is a\npartial." }},
        .{},
        "    <div>This is a\npartial.</div>",
    );
    try expectRenderComptime(
        "    <div>{{> partial}}</div>",
        &.{.{ .name = "partial", .data = "This is a\npartial." }},
        .{},
        "    <div>This is a\npartial.</div>",
    );
}

test "mustachejs partials: Each line of the partial should be indented before rendering." {
    try expectRender(
        "\\\n {{>partial}}\n/\n",
        &.{.{ .name = "partial", .data = "|\n{{{content}}}\n|\n" }},
        .{ .content = "<\n->" },
        "\\\n |\n <\n->\n |\n/\n",
    );
    try expectRenderComptime(
        "\\\n {{>partial}}\n/\n",
        &.{.{ .name = "partial", .data = "|\n{{{content}}}\n|\n" }},
        .{ .content = "<\n->" },
        "\\\n |\n <\n->\n |\n/\n",
    );
}

// -- Partials suite: custom delimiters ----------------------------------------

test "mustachejs partials: Nested partials should support custom delimiters." {
    // The original passes `tags: ['[[', ']]']` to Mustache.render, which
    // applies to the template and every partial. There is no render-time tags
    // API here, so each template opens with an equivalent `{{=[[ ]]=}}`
    // delimiter change (partials always start with the default delimiters).
    try expectRender(
        "{{=[[ ]]=}}[[> level1 ]]",
        &.{
            .{ .name = "level1", .data = "{{=[[ ]]=}}partial 1\n[[> level2]]" },
            .{ .name = "level2", .data = "{{=[[ ]]=}}partial 2\n[[> level3]]" },
            .{ .name = "level3", .data = "{{=[[ ]]=}}partial 3\n[[> level4]]" },
            .{ .name = "level4", .data = "{{=[[ ]]=}}partial 4\n[[> level5]]" },
            .{ .name = "level5", .data = "partial 5" },
        },
        .{},
        "partial 1\npartial 2\npartial 3\npartial 4\npartial 5",
    );
    try expectRenderComptime(
        "{{=[[ ]]=}}[[> level1 ]]",
        &.{
            .{ .name = "level1", .data = "{{=[[ ]]=}}partial 1\n[[> level2]]" },
            .{ .name = "level2", .data = "{{=[[ ]]=}}partial 2\n[[> level3]]" },
            .{ .name = "level3", .data = "{{=[[ ]]=}}partial 3\n[[> level4]]" },
            .{ .name = "level4", .data = "{{=[[ ]]=}}partial 4\n[[> level5]]" },
            .{ .name = "level5", .data = "partial 5" },
        },
        .{},
        "partial 1\npartial 2\npartial 3\npartial 4\npartial 5",
    );
}
