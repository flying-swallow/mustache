//! Test root: pulls in every test file so `zig build test` runs them all.
//!
//! - core.zig — library API surface, filesystem partials, load errors
//! - spec/ — the official mustache spec (mustache/spec), one file per module
//! - mustachejs/ — ports of the mustache.js test suite, one file per feature

test {
    _ = @import("core.zig");
    _ = @import("spec/comments.zig");
    _ = @import("spec/delimiters.zig");
    _ = @import("spec/interpolation.zig");
    _ = @import("spec/inverted.zig");
    _ = @import("spec/partials.zig");
    _ = @import("spec/sections.zig");
    _ = @import("comments.zig");
    _ = @import("context.zig");
    _ = @import("data.zig");
    _ = @import("delimiters.zig");
    _ = @import("interpolation.zig");
    _ = @import("partials.zig");
    _ = @import("sections.zig");
    _ = @import("whitespace.zig");
}
