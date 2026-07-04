//! mustache.js render fixtures (`test/_files`): sections, inverted
//! sections and iteration.
//!
//! Templates and expected outputs are transcribed byte-exactly; data is
//! translated from JS object literals to Zig struct literals, with
//! constant-returning functions replaced by their value and `undefined`/
//! `null` becoming optional-null. Deviations from the original expected
//! output are commented in place. Everything runs through the shared
//! helpers, so each case is checked against both the runtime and comptime
//! parsers.
//!
//! Skipped fixtures: higher_order_sections,
//! nested_higher_order_sections (lambdas, unsupported).

const std = @import("std");
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;

test "mustachejs: two_sections" {
    try expectRender(
        \\{{#foo}}
        \\{{/foo}}
        \\{{#bar}}
        \\{{/bar}}
    ++ "\n",
        &.{},
        .{},
        "",
    );
    try expectRenderComptime(
        \\{{#foo}}
        \\{{/foo}}
        \\{{#bar}}
        \\{{/bar}}
    ++ "\n",
        &.{},
        .{},
        "",
    );
}

test "mustachejs: empty_sections" {
    try expectRender(
        "{{#foo}}{{/foo}}foo{{#bar}}{{/bar}}\n",
        &.{},
        .{},
        "foo\n",
    );
    try expectRenderComptime(
        "{{#foo}}{{/foo}}foo{{#bar}}{{/bar}}\n",
        &.{},
        .{},
        "foo\n",
    );
}

test "mustachejs: empty_list" {
    try expectRender(
        \\These are the jobs:
        \\{{#jobs}}
        \\{{.}}
        \\{{/jobs}}
    ++ "\n",
        &.{},
        .{ .jobs = [0][]const u8{} },
        "These are the jobs:\n",
    );
    try expectRenderComptime(
        \\These are the jobs:
        \\{{#jobs}}
        \\{{.}}
        \\{{/jobs}}
    ++ "\n",
        &.{},
        .{ .jobs = [0][]const u8{} },
        "These are the jobs:\n",
    );
}

test "mustachejs: inverted_section" {
    try expectRender(
        \\{{#repos}}<b>{{name}}</b>{{/repos}}
        \\{{^repos}}No repos :({{/repos}}
        \\{{^nothin}}Hello!{{/nothin}}
    ++ "\n",
        &.{},
        .{ .repos = [0][]const u8{} },
        \\
        \\No repos :(
        \\Hello!
    ++ "\n");
    try expectRenderComptime(
        \\{{#repos}}<b>{{name}}</b>{{/repos}}
        \\{{^repos}}No repos :({{/repos}}
        \\{{^nothin}}Hello!{{/nothin}}
    ++ "\n",
        &.{},
        .{ .repos = [0][]const u8{} },
        \\
        \\No repos :(
        \\Hello!
    ++ "\n");
}

test "mustachejs: array_of_strings" {
    try expectRender(
        "{{#array_of_strings}}{{.}} {{/array_of_strings}}\n",
        &.{},
        .{ .array_of_strings = [_][]const u8{ "hello", "world" } },
        "hello world \n",
    );
    try expectRenderComptime(
        "{{#array_of_strings}}{{.}} {{/array_of_strings}}\n",
        &.{},
        .{ .array_of_strings = [_][]const u8{ "hello", "world" } },
        "hello world \n",
    );
}

test "mustachejs: implicit_iterator" {
    try expectRender(
        \\{{# data.author.twitter_id }}
        \\<meta name="twitter:site:id" content="{{.}}">
        \\{{/ data.author.twitter_id }}
        \\
        \\{{# data.author.name }}
        \\<meta name="twitter:site" content="{{.}}">
        \\{{/ data.author.name }}
    ++ "\n",
        &.{},
        .{ .data = .{ .author = .{ .twitter_id = 819606, .name = "janl" } } },
        \\<meta name="twitter:site:id" content="819606">
        \\
        \\<meta name="twitter:site" content="janl">
    ++ "\n");
    try expectRenderComptime(
        \\{{# data.author.twitter_id }}
        \\<meta name="twitter:site:id" content="{{.}}">
        \\{{/ data.author.twitter_id }}
        \\
        \\{{# data.author.name }}
        \\<meta name="twitter:site" content="{{.}}">
        \\{{/ data.author.name }}
    ++ "\n",
        &.{},
        .{ .data = .{ .author = .{ .twitter_id = 819606, .name = "janl" } } },
        \\<meta name="twitter:site:id" content="819606">
        \\
        \\<meta name="twitter:site" content="janl">
    ++ "\n");
}

test "mustachejs: nested_iterating" {
    try expectRender(
        "{{#inner}}{{foo}}{{#inner}}{{bar}}{{/inner}}{{/inner}}\n",
        &.{},
        .{ .inner = .{.{ .foo = "foo", .inner = .{.{ .bar = "bar" }} }} },
        "foobar\n",
    );
    try expectRenderComptime(
        "{{#inner}}{{foo}}{{#inner}}{{bar}}{{/inner}}{{/inner}}\n",
        &.{},
        .{ .inner = .{.{ .foo = "foo", .inner = .{.{ .bar = "bar" }} }} },
        "foobar\n",
    );
}

test "mustachejs: nesting" {
    try expectRender(
        \\{{#foo}}
        \\  {{#a}}
        \\    {{b}}
        \\  {{/a}}
        \\{{/foo}}
    ++ "\n",
        &.{},
        .{
            .foo = .{
                .{ .a = .{ .b = 1 } },
                .{ .a = .{ .b = 2 } },
                .{ .a = .{ .b = 3 } },
            },
        },
        \\    1
        \\    2
        \\    3
    ++ "\n");
    try expectRenderComptime(
        \\{{#foo}}
        \\  {{#a}}
        \\    {{b}}
        \\  {{/a}}
        \\{{/foo}}
    ++ "\n",
        &.{},
        .{
            .foo = .{
                .{ .a = .{ .b = 1 } },
                .{ .a = .{ .b = 2 } },
                .{ .a = .{ .b = 3 } },
            },
        },
        \\    1
        \\    2
        \\    3
    ++ "\n");
}

test "mustachejs: nesting_same_name" {
    try expectRender(
        "{{#items}}{{name}}{{#items}}{{.}}{{/items}}{{/items}}\n",
        &.{},
        .{ .items = .{.{ .name = "name", .items = .{ 1, 2, 3, 4 } }} },
        "name1234\n",
    );
    try expectRenderComptime(
        "{{#items}}{{name}}{{#items}}{{.}}{{/items}}{{/items}}\n",
        &.{},
        .{ .items = .{.{ .name = "name", .items = .{ 1, 2, 3, 4 } }} },
        "name1234\n",
    );
}

test "mustachejs: reuse_of_enumerables" {
    try expectRender(
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
    ++ "\n",
        &.{},
        .{
            .terms = .{
                .{ .name = "t1", .index = 0 },
                .{ .name = "t2", .index = 1 },
            },
        },
        \\  t1
        \\  0
        \\  t2
        \\  1
        \\  t1
        \\  0
        \\  t2
        \\  1
    ++ "\n");
    try expectRenderComptime(
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
        \\{{#terms}}
        \\  {{name}}
        \\  {{index}}
        \\{{/terms}}
    ++ "\n",
        &.{},
        .{
            .terms = .{
                .{ .name = "t1", .index = 0 },
                .{ .name = "t2", .index = 1 },
            },
        },
        \\  t1
        \\  0
        \\  t2
        \\  1
        \\  t1
        \\  0
        \\  t2
        \\  1
    ++ "\n");
}

test "mustachejs: double_render" {
    // Rendered values are not re-rendered, so `{{win}}` stays literal.
    try expectRender(
        "{{#foo}}{{bar}}{{/foo}}\n",
        &.{},
        .{ .foo = true, .bar = "{{win}}", .win = "FAIL" },
        "{{win}}\n",
    );
    try expectRenderComptime(
        "{{#foo}}{{bar}}{{/foo}}\n",
        &.{},
        .{ .foo = true, .bar = "{{win}}", .win = "FAIL" },
        "{{win}}\n",
    );
}

test "mustachejs: disappearing_whitespace" {
    try expectRender(
        "{{#bedrooms}}{{total}}{{/bedrooms}} BED\n",
        &.{},
        .{ .bedrooms = true, .total = 1 },
        "1 BED\n",
    );
    try expectRenderComptime(
        "{{#bedrooms}}{{total}}{{/bedrooms}} BED\n",
        &.{},
        .{ .bedrooms = true, .total = 1 },
        "1 BED\n",
    );
}

test "mustachejs: section_as_context" {
    try expectRender(
        \\{{#a_object}}
        \\  <h1>{{title}}</h1>
        \\  <p>{{description}}</p>
        \\  <ul>
        \\    {{#a_list}}
        \\    <li>{{label}}</li>
        \\    {{/a_list}}
        \\  </ul>
        \\{{/a_object}}
    ++ "\n",
        &.{},
        .{
            .a_object = .{
                .title = "this is an object",
                .description = "one of its attributes is a list",
                .a_list = .{
                    .{ .label = "listitem1" },
                    .{ .label = "listitem2" },
                },
            },
        },
        \\  <h1>this is an object</h1>
        \\  <p>one of its attributes is a list</p>
        \\  <ul>
        \\    <li>listitem1</li>
        \\    <li>listitem2</li>
        \\  </ul>
    ++ "\n");
    try expectRenderComptime(
        \\{{#a_object}}
        \\  <h1>{{title}}</h1>
        \\  <p>{{description}}</p>
        \\  <ul>
        \\    {{#a_list}}
        \\    <li>{{label}}</li>
        \\    {{/a_list}}
        \\  </ul>
        \\{{/a_object}}
    ++ "\n",
        &.{},
        .{
            .a_object = .{
                .title = "this is an object",
                .description = "one of its attributes is a list",
                .a_list = .{
                    .{ .label = "listitem1" },
                    .{ .label = "listitem2" },
                },
            },
        },
        \\  <h1>this is an object</h1>
        \\  <p>one of its attributes is a list</p>
        \\  <ul>
        \\    <li>listitem1</li>
        \\    <li>listitem2</li>
        \\  </ul>
    ++ "\n");
}

test "mustachejs: string_as_context" {
    try expectRender(
        \\<ul>
        \\{{#a_list}}
        \\  <li>{{a_string}}/{{.}}</li>
        \\{{/a_list}}
        \\</ul>
    ,
        &.{},
        .{ .a_string = "aa", .a_list = [_][]const u8{ "a", "b", "c" } },
        \\<ul>
        \\  <li>aa/a</li>
        \\  <li>aa/b</li>
        \\  <li>aa/c</li>
        \\</ul>
    );
    try expectRenderComptime(
        \\<ul>
        \\{{#a_list}}
        \\  <li>{{a_string}}/{{.}}</li>
        \\{{/a_list}}
        \\</ul>
    ,
        &.{},
        .{ .a_string = "aa", .a_list = [_][]const u8{ "a", "b", "c" } },
        \\<ul>
        \\  <li>aa/a</li>
        \\  <li>aa/b</li>
        \\  <li>aa/c</li>
        \\</ul>
    );
}

test "mustachejs: complex" {
    // `header`, `list`, `empty` and the per-item `link` were functions;
    // `link` is baked into each item as `!current`.
    try expectRender(
        \\<h1>{{header}}</h1>
        \\{{#list}}
        \\  <ul>
        \\  {{#item}}
        \\  {{#current}}
        \\  <li><strong>{{name}}</strong></li>
        \\  {{/current}}
        \\  {{#link}}
        \\  <li><a href="{{url}}">{{name}}</a></li>
        \\  {{/link}}
        \\  {{/item}}
        \\  </ul>
        \\{{/list}}
        \\{{#empty}}
        \\  <p>The list is empty.</p>
        \\{{/empty}}
    ++ "\n",
        &.{},
        .{
            .header = "Colors",
            .item = .{
                .{ .name = "red", .current = true, .url = "#Red", .link = false },
                .{ .name = "green", .current = false, .url = "#Green", .link = true },
                .{ .name = "blue", .current = false, .url = "#Blue", .link = true },
            },
            .list = true,
            .empty = false,
        },
        \\<h1>Colors</h1>
        \\  <ul>
        \\  <li><strong>red</strong></li>
        \\  <li><a href="#Green">green</a></li>
        \\  <li><a href="#Blue">blue</a></li>
        \\  </ul>
    ++ "\n");
    try expectRenderComptime(
        \\<h1>{{header}}</h1>
        \\{{#list}}
        \\  <ul>
        \\  {{#item}}
        \\  {{#current}}
        \\  <li><strong>{{name}}</strong></li>
        \\  {{/current}}
        \\  {{#link}}
        \\  <li><a href="{{url}}">{{name}}</a></li>
        \\  {{/link}}
        \\  {{/item}}
        \\  </ul>
        \\{{/list}}
        \\{{#empty}}
        \\  <p>The list is empty.</p>
        \\{{/empty}}
    ++ "\n",
        &.{},
        .{
            .header = "Colors",
            .item = .{
                .{ .name = "red", .current = true, .url = "#Red", .link = false },
                .{ .name = "green", .current = false, .url = "#Green", .link = true },
                .{ .name = "blue", .current = false, .url = "#Blue", .link = true },
            },
            .list = true,
            .empty = false,
        },
        \\<h1>Colors</h1>
        \\  <ul>
        \\  <li><strong>red</strong></li>
        \\  <li><a href="#Green">green</a></li>
        \\  <li><a href="#Blue">blue</a></li>
        \\  </ul>
    ++ "\n");
}
