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

Loading templates (and partials) from the filesystem requires a `std.Io`:

```zig
var m = try Mustache.fromFile(allocator, io, "templates/index.html");
```

## Testing

```sh
zig build test
```
