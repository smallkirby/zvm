//! This module provides a collection of utility functions.

const std = @import("std");

/// Dump the given data to the file.
pub fn dump(f: std.fs.File, data: [*]u8, size: usize) !void {
    std.debug.print("dumping: 0x{X} bytes...\n", .{size});
    try f.writeAll(data[0..size]);
}
