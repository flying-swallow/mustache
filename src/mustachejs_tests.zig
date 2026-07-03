//! Ports of the mustache.js render fixtures (`test/_files/*.{mustache,js,txt}`).
//!
//! Each test is named after its fixture. Templates and expected outputs are
//! transcribed byte-exactly; data files are translated from JS object
//! literals to Zig struct literals. Constant-returning JS functions are
//! replaced by their value and `undefined`/`null` become optional-null.
//! Deviations from the original expected output are commented in place.
//!
//! Skipped fixtures:
//! - higher_order_sections, nested_higher_order_sections,
//!   section_functions_in_partials, check_falsy, cli_js_view_with_function:
//!   real lambdas / higher-order sections (unsupported).
//! - cli, cli_with_partials: exercise the mustache.js CLI harness.
//! - malicious_template: JS code-injection test; the template just fails
//!   compilation here (unresolved partial -> error.FileNotFound).

const std = @import("std");
const mustache = @import("root.zig");
const Mustache = mustache.Mustache;

const alloc = std.testing.allocator;

fn expectRender(template: []const u8, data: anytype, expected: []const u8) !void {
    var m = try Mustache.fromData(alloc, template);
    defer m.deinit();
    const rendered = try m.build(alloc, data);
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

/// The JS test harness renders every partial fixture with
/// `Mustache.render(template, view, { partial: <contents> })`.
fn expectRenderPartial(
    template: []const u8,
    partial: []const u8,
    data: anytype,
    expected: []const u8,
) !void {
    var m = try Mustache.init(alloc, .{
        .data = template,
        .partials = &.{.{ .name = "partial", .data = partial }},
    });
    defer m.deinit();
    const rendered = try m.build(alloc, data);
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "mustachejs: ampersand_escape" {
    try expectRender(
        "{{&message}}\n",
        .{ .message = "Some <code>" },
        "Some <code>\n",
    );
}

test "mustachejs: apostrophe" {
    try expectRender(
        "{{apos}}{{control}}\n",
        .{ .apos = "'", .control = "X" },
        "&#39;X\n",
    );
}

test "mustachejs: array_of_strings" {
    try expectRender(
        "{{#array_of_strings}}{{.}} {{/array_of_strings}}\n",
        .{ .array_of_strings = [_][]const u8{ "hello", "world" } },
        "hello world \n",
    );
}

test "mustachejs: avoids_obj_prototype_in_view_cache" {
    // In JS this guards against Object.prototype methods leaking into the
    // view cache; here they are ordinary keys.
    try expectRender(
        "{{valueOf}} {{watch}}",
        .{ .valueOf = "Avoids methods", .watch = "in Object.prototype" },
        "Avoids methods in Object.prototype",
    );
}

test "mustachejs: backslashes" {
    try expectRender(
        \\* {{value}}
        \\* {{{value}}}
        \\* {{&value}}
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n",
        .{ .value = "\\abc" },
        \\* \abc
        \\* \abc
        \\* \abc
        \\<script>
        \\foo = { bar: 'abc\"xyz\"' };
        \\foo = { bar: 'x\'y' };
        \\</script>
    ++ "\n");
}

test "mustachejs: bug_11_eating_whitespace" {
    try expectRender("{{tag}} foo\n", .{ .tag = "yo" }, "yo foo\n");
}

test "mustachejs: bug_length_property" {
    try expectRender(
        "{{#length}}The length variable is: {{length}}{{/length}}\n",
        .{ .length = "hello" },
        "The length variable is: hello\n",
    );
}

test "mustachejs: changing_delimiters" {
    try expectRender(
        "{{=<% %>=}}<% foo %> {{foo}} <%{bar}%> {{{bar}}}\n",
        .{ .foo = "foooooooooooooo", .bar = "<b>bar!</b>" },
        "foooooooooooooo {{foo}} <b>bar!</b> {{{bar}}}\n",
    );
}

test "mustachejs: comments" {
    // `title` was a constant-returning function.
    try expectRender(
        "<h1>{{title}}{{! just something interesting... or not... }}</h1>\n",
        .{ .title = "A Comedy of Errors" },
        "<h1>A Comedy of Errors</h1>\n",
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

test "mustachejs: context_lookup" {
    try expectRender(
        "{{#outer}}{{#second}}{{id}}{{/second}}{{/outer}}\n",
        .{ .outer = .{ .id = 1, .second = .{ .nothing = 2 } } },
        "1\n",
    );
}

test "mustachejs: delimiters" {
    try expectRender(
        \\{{=<% %>=}}*
        \\<% first %>
        \\* <% second %>
        \\<%=| |=%>
        \\* | third |
        \\|={{ }}=|
        \\* {{ fourth }}
    ++ "\n",
        .{
            .first = "It worked the first time.",
            .second = "And it worked the second time.",
            .third = "Then, surprisingly, it worked the third time.",
            .fourth = "Fourth time also fine!.",
        },
        \\*
        \\It worked the first time.
        \\* And it worked the second time.
        \\* Then, surprisingly, it worked the third time.
        \\* Fourth time also fine!.
    ++ "\n");
}

test "mustachejs: disappearing_whitespace" {
    try expectRender(
        "{{#bedrooms}}{{total}}{{/bedrooms}} BED\n",
        .{ .bedrooms = true, .total = 1 },
        "1 BED\n",
    );
}

test "mustachejs: dot_notation" {
    // `vat` was a function returning 40. The three `…length` lines rely on
    // JS string/array autoboxing (`"USD".length` etc.); those keys do not
    // exist here, so they render empty instead of 3 / 14 / 2.
    try expectRender(
        \\<!-- exciting part -->
        \\<h1>{{name}}</h1>
        \\<p>Authors: <ul>{{#authors}}<li>{{.}}</li>{{/authors}}</ul></p>
        \\<p>Price: {{{price.currency.symbol}}}{{price.value}} {{#price.currency}}{{name}} <b>{{availability.text}}</b>{{/price.currency}}</p>
        \\<p>VAT: {{{price.currency.symbol}}}{{#price}}{{vat}}{{/price}}</p>
        \\<!-- boring part -->
        \\<h2>Test truthy false values:</h2>
        \\<p>Zero: {{truthy.zero}}</p>
        \\<p>False: {{truthy.notTrue}}</p>
        \\<p>length of string should be rendered: {{price.currency.name.length}}</p>
        \\<p>length of string in a list should be rendered: {{#singletonList}}{{singletonItem.length}}{{/singletonList}}</p>
        \\<p>length of an array should be rendered: {{authors.length}}</p>
    ++ "\n",
        .{
            .name = "A Book",
            .authors = [_][]const u8{ "John Power", "Jamie Walsh" },
            .price = .{
                .value = 200,
                .vat = 40,
                .currency = .{ .symbol = "$", .name = "USD" },
            },
            .availability = .{ .status = true, .text = "In Stock" },
            .truthy = .{ .zero = 0, .notTrue = false },
            .singletonList = .{.{ .singletonItem = "singleton item" }},
        },
        \\<!-- exciting part -->
        \\<h1>A Book</h1>
        \\<p>Authors: <ul><li>John Power</li><li>Jamie Walsh</li></ul></p>
        \\<p>Price: $200 USD <b>In Stock</b></p>
        \\<p>VAT: $40</p>
        \\<!-- boring part -->
        \\<h2>Test truthy false values:</h2>
        \\<p>Zero: 0</p>
        \\<p>False: false</p>
        \\<p>length of string should be rendered: </p>
        \\<p>length of string in a list should be rendered: </p>
        \\<p>length of an array should be rendered: </p>
    ++ "\n");
}

test "mustachejs: double_render" {
    // Rendered values are not re-rendered, so `{{win}}` stays literal.
    try expectRender(
        "{{#foo}}{{bar}}{{/foo}}\n",
        .{ .foo = true, .bar = "{{win}}", .win = "FAIL" },
        "{{win}}\n",
    );
}

test "mustachejs: empty_list" {
    try expectRender(
        \\These are the jobs:
        \\{{#jobs}}
        \\{{.}}
        \\{{/jobs}}
    ++ "\n",
        .{ .jobs = [0][]const u8{} },
        "These are the jobs:\n",
    );
}

test "mustachejs: empty_sections" {
    try expectRender(
        "{{#foo}}{{/foo}}foo{{#bar}}{{/bar}}\n",
        .{},
        "foo\n",
    );
}

test "mustachejs: empty_string" {
    try expectRender(
        "{{description}}{{#child}}{{description}}{{/child}}\n",
        .{ .description = "That is all!", .child = .{ .description = "" } },
        "That is all!\n",
    );
}

test "mustachejs: empty_template" {
    try expectRender(
        "<html><head></head><body><h1>Test</h1></body></html>",
        .{},
        "<html><head></head><body><h1>Test</h1></body></html>",
    );
}

test "mustachejs: error_not_found" {
    try expectRender("{{foo}}", .{ .bar = 2 }, "");
}

test "mustachejs: escaped" {
    // `title` was a constant-returning function.
    try expectRender(
        \\<h1>{{title}}{{symbol}}</h1>
        \\And even {{entities}}, but not {{{entities}}}.
    ++ "\n",
        .{
            .title = "Bear > Shark",
            .symbol = @as(?u8, null),
            .entities = "&quot; \"'<>`=/",
        },
        \\<h1>Bear &gt; Shark</h1>
        \\And even &amp;quot; &quot;&#39;&lt;&gt;&#x60;&#x3D;&#x2F;, but not &quot; "'<>`=/.
    ++ "\n");
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

test "mustachejs: grandparent_context" {
    try expectRender(
        \\{{grand_parent_id}}
        \\{{#parent_contexts}}
        \\{{grand_parent_id}}
        \\{{parent_id}}
        \\{{#child_contexts}}
        \\{{grand_parent_id}}
        \\{{parent_id}}
        \\{{child_id}}
        \\{{/child_contexts}}
        \\{{/parent_contexts}}
    ++ "\n",
        .{
            .grand_parent_id = "grand_parent1",
            .parent_contexts = .{
                .{
                    .parent_id = "parent1",
                    .child_contexts = .{
                        .{ .child_id = "parent1-child1" },
                        .{ .child_id = "parent1-child2" },
                    },
                },
                .{
                    .parent_id = "parent2",
                    .child_contexts = .{
                        .{ .child_id = "parent2-child1" },
                        .{ .child_id = "parent2-child2" },
                    },
                },
            },
        },
        \\grand_parent1
        \\grand_parent1
        \\parent1
        \\grand_parent1
        \\parent1
        \\parent1-child1
        \\grand_parent1
        \\parent1
        \\parent1-child2
        \\grand_parent1
        \\parent2
        \\grand_parent1
        \\parent2
        \\parent2-child1
        \\grand_parent1
        \\parent2
        \\parent2-child2
    ++ "\n");
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
        .{ .data = .{ .author = .{ .twitter_id = 819606, .name = "janl" } } },
        \\<meta name="twitter:site:id" content="819606">
        \\
        \\<meta name="twitter:site" content="janl">
    ++ "\n");
}

test "mustachejs: included_tag" {
    try expectRender(
        "You said \"{{{html}}}\" today\n",
        .{ .html = "I like {{mustache}}" },
        "You said \"I like {{mustache}}\" today\n",
    );
}

test "mustachejs: inverted_section" {
    try expectRender(
        \\{{#repos}}<b>{{name}}</b>{{/repos}}
        \\{{^repos}}No repos :({{/repos}}
        \\{{^nothin}}Hello!{{/nothin}}
    ++ "\n",
        .{ .repos = [0][]const u8{} },
        \\
        \\No repos :(
        \\Hello!
    ++ "\n");
}

test "mustachejs: keys_with_questionmarks" {
    try expectRender(
        \\{{#person?}}
        \\  Hi {{name}}!
        \\{{/person?}}
    ++ "\n",
        .{ .@"person?" = .{ .name = "Jon" } },
        "  Hi Jon!\n",
    );
}

test "mustachejs: multiline_comment" {
    try expectRender(
        \\{{!
        \\
        \\This is a multi-line comment.
        \\
        \\}}
        \\Hello world!
    ++ "\n",
        .{},
        "Hello world!\n",
    );
}

test "mustachejs: nested_dot" {
    try expectRender(
        "{{#name}}Hello {{.}}{{/name}}",
        .{ .name = "Bruno" },
        "Hello Bruno",
    );
}

test "mustachejs: nested_iterating" {
    try expectRender(
        "{{#inner}}{{foo}}{{#inner}}{{bar}}{{/inner}}{{/inner}}\n",
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
        .{ .items = .{.{ .name = "name", .items = .{ 1, 2, 3, 4 } }} },
        "name1234\n",
    );
}

test "mustachejs: null_lookup_array" {
    try expectRender(
        \\{{#farray}}
        \\{{#.}}{{#.}}{{.}} {{/.}}{{^.}}no twitter{{/.}}{{/.}}
        \\{{/farray}}
    ++ "\n",
        .{
            .name = "David",
            .twitter = "@dasilvacontin",
            .farray = .{
                .{ "Flor", "@florrts" },
                .{ "Miquel", @as(?u8, null) },
                .{ "Chris", @as(?u8, null) },
            },
        },
        "Flor @florrts \nMiquel no twitter\nChris no twitter\n",
    );
}

test "mustachejs: null_lookup_object" {
    try expectRender(
        \\{{#fobject}}
        \\{{name}}'s twitter: {{#twitter}}{{.}}{{/twitter}}{{^twitter}}unknown{{/twitter}}.
        \\{{/fobject}}
        \\
        \\{{#mascot}}
        \\{{name}}'s favorite color: {{#favorites.color}}{{.}}{{/favorites.color}}{{^favorites.color}}no one{{/favorites.color}}.
        \\{{name}}'s favorite president: {{#favorites.president}}{{.}}{{/favorites.president}}{{^favorites.president}}no one{{/favorites.president}}.
        \\{{name}}'s favorite show: {{#favorites.show}}{{.}}{{/favorites.show}}{{^favorites.show}}none{{/favorites.show}}.
        \\{{/mascot}}
    ++ "\n",
        .{
            .name = "David",
            .twitter = "@dasilvacontin",
            .fobject = .{
                .{ .name = "Flor", .twitter = @as(?[]const u8, "@florrts") },
                .{ .name = "Miquel", .twitter = @as(?[]const u8, null) },
                .{ .name = "Chris", .twitter = @as(?[]const u8, null) },
            },
            .favorites = .{ .color = "blue", .president = "Bush", .show = "Futurama" },
            .mascot = .{
                .name = "Squid",
                .favorites = .{
                    .color = "orange",
                    .president = @as(?u8, null),
                    .show = @as(?u8, null),
                },
            },
        },
        \\Flor's twitter: @florrts.
        \\Miquel's twitter: unknown.
        \\Chris's twitter: unknown.
        \\
        \\Squid's favorite color: orange.
        \\Squid's favorite president: no one.
        \\Squid's favorite show: none.
    ++ "\n");
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

test "mustachejs: null_view" {
    try expectRender(
        "{{name}}'s friends: {{#friends}}{{name}}, {{/friends}}",
        .{ .name = "Joe", .friends = @as(?u8, null) },
        "Joe's friends: ",
    );
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
}

test "mustachejs: partial_empty" {
    try expectRenderPartial(
        "hey {{foo}}\n{{>partial}}\n",
        "",
        .{ .foo = 1 },
        "hey 1\n",
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

test "mustachejs: simple" {
    // `taxed_value` was a function returning 6000.
    try expectRender(
        \\Hello {{name}}
        \\You have just won ${{value}}!
        \\{{#in_ca}}
        \\Well, ${{ taxed_value }}, after taxes.
        \\{{/in_ca}}
    ++ "\n",
        .{ .name = "Chris", .value = 10000, .taxed_value = 6000, .in_ca = true },
        \\Hello Chris
        \\You have just won $10000!
        \\Well, $6000, after taxes.
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
        .{ .a_string = "aa", .a_list = [_][]const u8{ "a", "b", "c" } },
        \\<ul>
        \\  <li>aa/a</li>
        \\  <li>aa/b</li>
        \\  <li>aa/c</li>
        \\</ul>
    );
}

test "mustachejs: two_in_a_row" {
    try expectRender(
        "{{greeting}}, {{name}}!\n",
        .{ .name = "Joe", .greeting = "Welcome" },
        "Welcome, Joe!\n",
    );
}

test "mustachejs: two_sections" {
    try expectRender(
        \\{{#foo}}
        \\{{/foo}}
        \\{{#bar}}
        \\{{/bar}}
    ++ "\n",
        .{},
        "",
    );
}

test "mustachejs: unescaped" {
    // `title` was a constant-returning function.
    try expectRender(
        "<h1>{{{title}}}{{{symbol}}}</h1>\n",
        .{ .title = "Bear > Shark", .symbol = @as(?u8, null) },
        "<h1>Bear > Shark</h1>\n",
    );
}

test "mustachejs: uses_props_from_view_prototype" {
    // The JS fixture reads `y` through a prototype getter; flattened here.
    try expectRender(
        "[{{ item.x }};{{ item.y }}]||{{#items}}[{{ a.x }};{{ a.y }} {{#a}}{{y}}{{/a}}]{{/items}}",
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

test "mustachejs: whitespace" {
    try expectRender(
        "{{tag1}}\n\n\n{{tag2}}.\n",
        .{ .tag1 = "Hello", .tag2 = "World" },
        "Hello\n\n\nWorld.\n",
    );
}

test "mustachejs: zero_view" {
    try expectRender(
        "{{#nums}}{{.}},{{/nums}}",
        .{ .nums = .{ 0, 1, 2 } },
        "0,1,2,",
    );
}
