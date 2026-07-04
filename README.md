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
comptime helpers (`Comptime`, `comptimeTemplate`), and the low-level `render`
(streaming) and `renderAlloc` functions.

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

The `data` argument must be a struct. There is no intermediate value tree:
rendering reads the data in place through accessors generated at compile time
for its type.

| Zig value                     | Mustache meaning                         |
| ----------------------------- | ---------------------------------------- |
| struct with fields            | object (fields addressable via `{{a.b}}`) |
| tuple / slice / array         | iterable list (for `{{#items}}`)         |
| `[]const u8` (valid UTF-8)    | string (otherwise a list of bytes)       |
| optional                      | present value, or absent (`null`)        |
| `bool`                        | truthy / falsy for sections              |
| int / float                   | number                                   |
| enum                          | its integer value                        |
| tagged union                  | its active payload                       |
| error value                   | its name as a string                     |

To stream instead of allocating, render into any `std.Io.Writer`:

```zig
var w: std.Io.Writer = .fixed(&buf); // or a file/socket writer
try m.render(.{ .name = "World" }, &w);
```

Nothing is flushed; the caller owns the writer's buffering. The free function
`mustache.render(&template, data, writer)` does the same for an
already-compiled template, and neither restricts `data` to a struct — a bare
string, number or list also works as the root value.

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
- `Mustache.BuildError` (`RenderAllocError`) — returned by `build` /
  `renderAlloc`: `error{TooDeep}` (section/partial nesting limit) plus
  allocation failure.
- `RenderError` — returned by the streaming `render`: `error{TooDeep}` plus
  `error{WriteFailed}` from the writer.

## Benchmarks

The benchmark renders a small template one million times across three output
modes — a fixed buffer (`Buffer`), an allocating build (`Alloc`), and a
discarding writer (`Writer`) — comparing a runtime-parsed and a comptime-parsed
template against an equivalent `std.fmt` baseline, plus a parse-only pass.

Reproduce with:

```sh
zig build bench -Doptimize=ReleaseFast
```

Absolute numbers are machine-specific — the signal is the *ratio* between paths.
The comptime path is the headline: the template is parsed at compile time, so
rendering pays zero parse cost and allocates nothing for the template itself,
landing within ~1.6–2.4× of hand-written `std.fmt` while remaining fully
data-driven.

Numbers below were taken on an Apple M3 (macOS 15.7, Zig `0.17.0-dev`,
`ReleaseFast`, 1,000,000 iterations).

### Simple template

| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |
| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |
| Zig fmt (baseline)             | Buffer |    27.8 |   35921369 | 3871.1 |      - |
| Mustache pre-parsed (runtime)  | Buffer |    67.3 |   14854960 | 1600.8 |  2.42x |
| Mustache pre-parsed (comptime) | Buffer |    67.9 |   14735778 | 1588.0 |  2.44x |
| Zig fmt (baseline)             | Alloc  |    56.0 |   17850064 | 1923.6 |      - |
| Mustache pre-parsed (runtime)  | Alloc  |    91.7 |   10902609 | 1174.9 |  1.64x |
| Mustache pre-parsed (comptime) | Alloc  |    86.9 |   11502268 | 1239.5 |  1.55x |
| Zig fmt (baseline)             | Writer |    25.6 |   38994588 | 4202.3 |      - |
| Mustache pre-parsed (runtime)  | Writer |    61.2 |   16336466 | 1760.5 |  2.39x |
| Mustache pre-parsed (comptime) | Writer |    60.3 |   16576429 | 1786.4 |  2.35x |

### Partials

| Run                          | Mode   | ns/iter |     ops/s |   MB/s |
| ---------------------------- | ------ | ------: | --------: | -----: |
| Mustache pre-parsed partials | Buffer |   108.8 |   9192222 | 1323.7 |
| Mustache pre-parsed partials | Alloc  |   142.7 |   7007447 | 1009.1 |
| Mustache pre-parsed partials | Writer |   121.1 |   8259750 | 1189.4 |

Parsing a small multi-section template (compile + discard) runs at ~453 ns/iter
(≈2.2M ops/s), a cost the comptime path removes entirely.

## Testing

```sh
zig build test
```
