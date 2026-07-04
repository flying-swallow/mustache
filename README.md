# mustache

A pure-Zig [mustache](https://mustache.github.io/) template engine, ported
from the C implementation in [facil.io](https://facil.io)
(`mustache_parser.h` / `fiobj_mustache.c`, MIT, Boaz Segev). Originally the
template engine behind [zap](https://github.com/zigzap/zap).

Templates are compiled once into a flat instruction array and can then be
rendered any number of times against plain Zig values (structs, slices,
arrays, optionals, numbers, strings, ...).

## Features

- Sections and inverted sections (`{{#name}}`, `{{^name}}`), iterating arrays
- Dot notation (`{{a.b.c}}`) with parent-scope fallback
- Partials (`{{> file}}`) loaded from the filesystem relative to the
  including template, with a `.mustache` extension fallback; repeated
  partials are compiled once and reused, and recursive templates work
- Custom delimiters (`{{=<% %>=}}`)
- Standalone-tag whitespace handling and partial indentation ("padding")
- HTML escaping compatible with the facil.io implementation
  (`{{x}}` escaped, `{{{x}}}` / `{{& x}}` raw)

## Usage

```zig
const Mustache = @import("mustache").Mustache;

var m = try Mustache.fromData(allocator, "Hello {{name}}!");
defer m.deinit();

const rendered = try m.build(allocator, .{ .name = "World" });
defer allocator.free(rendered);
```

## API reference

The module's root (`@import("mustache")`) exposes the `Mustache` type, the
comptime helpers (`Comptime`, `comptimeTemplate`), the low-level `renderAlloc`
and `valueify` functions, and the `Value` union.

### Compiling a template

A template is compiled once and rendered any number of times. All three
constructors return a `Mustache` that must be freed with `deinit`.

```zig
// From an in-memory string. Partials referenced by the template render as
// the empty string.
var m = try Mustache.fromData(allocator, "Hello {{name}}!");
defer m.deinit();

// From the filesystem. Requires a `std.Io`; partials are resolved relative
// to the file (with a `.mustache` extension fallback).
var m = try Mustache.fromFile(allocator, io, "templates/index.html");
defer m.deinit();
```

For full control, use `init` with `LoadArgs`:

```zig
var m = try Mustache.init(allocator, .{
    // .io       — a `std.Io`, required for `filename` and filesystem partials
    // .filename — names the template (enables recursive partials)
    .data = "Hi {{name}}, see {{> footer}}",
    // In-memory partials, resolved before the filesystem.
    .partials = &.{
        .{ .name = "footer", .data = "-- {{company}}" },
    },
});
defer m.deinit();
```

`LoadArgs` fields: `io`, `filename`, `data`, `partials` (a
`[]const Mustache.Partial`, where `Partial` is `{ name, data }`).

### Rendering

`build` renders the compiled template against a struct and returns freshly
allocated text; the caller owns the result and frees it with `allocator.free`.

```zig
const out = try m.build(allocator, .{ .name = "World" });
defer allocator.free(out);
```

The `data` argument must be a struct. Its values are converted with
`valueify`:

| Zig value                     | Mustache meaning                         |
| ----------------------------- | ---------------------------------------- |
| struct with fields            | object (fields addressable via `{{a.b}}`) |
| tuple / slice / array         | iterable list (for `{{#items}}`)         |
| `[]const u8` (valid UTF-8)    | string                                   |
| optional                      | present value, or absent (`null`)        |
| `bool`                        | truthy / falsy for sections              |
| int / float                   | number                                   |
| enum                          | its integer value                        |
| tagged union                  | its active payload                       |

### Comptime templates

Templates can be compiled at compile time, with zero runtime parsing cost and
no allocation for the template itself. Only in-memory sources are supported
(load file contents with `@embedFile`).

```zig
const mustache = @import("mustache");

// Type wrapper mirroring the runtime ergonomics, minus `deinit`.
const T = mustache.Comptime(.{ .data = "Hello {{name}}!" });
const out = try T.build(allocator, .{ .name = "World" });
defer allocator.free(out);
```

Or compile the template directly and render it with `renderAlloc`, which
works with both comptime- and runtime-compiled templates:

```zig
const tmpl = comptime mustache.comptimeTemplate(.{ .data = "Hello {{name}}!" });
const out = try mustache.renderAlloc(allocator, &tmpl, .{ .name = "World" });
defer allocator.free(out);
```

`ComptimeArgs` fields: `data`, `filename` (names the virtual root template for
recursive partials), `partials`. A parse failure is a compile error.

### Errors

- `Mustache.Error` (`parser.LoadError`) — returned by the constructors when a
  template fails to compile or a partial cannot be loaded.
- `Mustache.BuildError` (`render.RenderError`) — returned by `build` /
  `renderAlloc`: `error{TooDeep}` (section/partial nesting limit) plus
  allocation failure.

## Testing

```sh
zig build test
```
