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
| `[]const u8`                  | string (bytes pass through verbatim; no UTF-8 validation) |
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

The benchmark renders small templates one million times across three output
modes — a fixed buffer (`Buffer`), an allocating build (`Alloc`), and a
discarding writer (`Writer`) — comparing a runtime-parsed and a comptime-parsed
template against an equivalent `std.fmt` baseline, plus a section-heavy render
and a parse-only pass.

Reproduce with:

```sh
zig build bench -Doptimize=ReleaseFast
```

Absolute numbers are machine-specific — the signal is the *ratio* between paths.
The comptime path is the headline: the template is parsed at compile time, so
rendering pays zero parse cost and allocates nothing for the template itself,
landing within ~1.4–1.8× of hand-written `std.fmt` while remaining fully
data-driven.

Numbers below were taken on an Apple M3 (macOS 15.7, Zig `0.17.0-dev`,
`ReleaseFast`, 1,000,000 iterations).

### Simple template

| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |
| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |
| Zig fmt (baseline)             | Buffer |    28.5 |   35074592 | 3779.8 |       - |
| Mustache pre-parsed (runtime)  | Buffer |    48.4 |   20663042 | 2226.8 |  1.70x |
| Mustache pre-parsed (comptime) | Buffer |    47.2 |   21170817 | 2281.5 |  1.66x |
| Zig fmt (baseline)             | Alloc  |    51.5 |   19405449 | 2091.2 |       - |
| Mustache pre-parsed (runtime)  | Alloc  |    72.1 |   13871806 | 1494.9 |  1.40x |
| Mustache pre-parsed (comptime) | Alloc  |    71.5 |   13986430 | 1507.3 |  1.39x |
| Zig fmt (baseline)             | Writer |    27.6 |   36187252 | 3899.7 |       - |
| Mustache pre-parsed (runtime)  | Writer |    48.6 |   20562029 | 2215.9 |  1.76x |
| Mustache pre-parsed (comptime) | Writer |    48.4 |   20677926 | 2228.4 |  1.75x |

### Partials

| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |
| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |
| Mustache pre-parsed partials   | Buffer |   102.2 |    9786300 | 1409.3 |       - |
| Mustache pre-parsed partials   | Alloc  |   123.0 |    8128162 | 1170.5 |       - |
| Mustache pre-parsed partials   | Writer |   101.7 |    9837654 | 1416.7 |       - |

### Sections

A blog-style template — a `{{#posts}}` loop over three posts — rendered
against a concrete struct type, exercising the monomorphic static section
path (loops dispatch with no vtable).

| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |
| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |
| Mustache sections (runtime)    | Buffer |   323.2 |    3093581 | 1820.3 |       - |
| Mustache sections (comptime)   | Buffer |   316.0 |    3164726 | 1862.2 |       - |
| Mustache sections (runtime)    | Alloc  |   369.4 |    2707306 | 1593.0 |       - |
| Mustache sections (comptime)   | Alloc  |   376.4 |    2656771 | 1563.3 |       - |
| Mustache sections (runtime)    | Writer |   322.7 |    3098537 | 1823.2 |       - |
| Mustache sections (comptime)   | Writer |   318.0 |    3144652 | 1850.4 |       - |

### Parse

| Run                            | Mode   | ns/iter |      ops/s |   MB/s | vs fmt |
| ------------------------------ | ------ | ------: | ---------: | -----: | -----: |
| Parse (compile + discard)      | -      |   456.8 |    2189365 |  551.2 |       - |

Parsing a small multi-section template (compile + discard) runs at ~457 ns/iter
(≈2.2M ops/s), a cost the comptime path removes entirely.

## Testing

```sh
zig build test
```
