//! mustache.js render fixtures (`test/_files`): context lookup and
//! dot notation.
//!
//! Templates and expected outputs are transcribed byte-exactly; data is
//! translated from JS object literals to Zig struct literals, with
//! constant-returning functions replaced by their value and `undefined`/
//! `null` becoming optional-null. Deviations from the original expected
//! output are commented in place. Everything runs through the shared
//! helpers, so each case is checked against both the runtime and comptime
//! parsers.

const std = @import("std");
const h = @import("helper.zig");
const expectRender = h.expectRender;
const expectRenderComptime = h.expectRenderComptime;

test "mustachejs: context_lookup" {
    try expectRender(
        "{{#outer}}{{#second}}{{id}}{{/second}}{{/outer}}\n",
        &.{},
        .{ .outer = .{ .id = 1, .second = .{ .nothing = 2 } } },
        "1\n",
    );
    try expectRenderComptime(
        "{{#outer}}{{#second}}{{id}}{{/second}}{{/outer}}\n",
        &.{},
        .{ .outer = .{ .id = 1, .second = .{ .nothing = 2 } } },
        "1\n",
    );
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
        &.{},
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
    try expectRenderComptime(
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
        &.{},
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
        &.{},
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
    try expectRenderComptime(
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
        &.{},
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

test "mustachejs: nested_dot" {
    try expectRender(
        "{{#name}}Hello {{.}}{{/name}}",
        &.{},
        .{ .name = "Bruno" },
        "Hello Bruno",
    );
    try expectRenderComptime(
        "{{#name}}Hello {{.}}{{/name}}",
        &.{},
        .{ .name = "Bruno" },
        "Hello Bruno",
    );
}

test "mustachejs: null_lookup_array" {
    try expectRender(
        \\{{#farray}}
        \\{{#.}}{{#.}}{{.}} {{/.}}{{^.}}no twitter{{/.}}{{/.}}
        \\{{/farray}}
    ++ "\n",
        &.{},
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
    try expectRenderComptime(
        \\{{#farray}}
        \\{{#.}}{{#.}}{{.}} {{/.}}{{^.}}no twitter{{/.}}{{/.}}
        \\{{/farray}}
    ++ "\n",
        &.{},
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
        &.{},
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
    try expectRenderComptime(
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
        &.{},
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
