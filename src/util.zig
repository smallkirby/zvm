//! This module provides a collection of utility functions.

const std = @import("std");
const consts = @import("consts.zig");

pub const UtilError = error{
    /// Memory string is invalid.
    InvalidMemoryUnit,
};

/// Dump the given data to the file.
pub fn dump(f: std.fs.File, data: [*]u8, size: usize) !void {
    std.debug.print("dumping: 0x{X} bytes...\n", .{size});
    try f.writeAll(data[0..size]);
}

/// Convert the given memory unit string to bytes.
pub fn convert_mem_unit(s: []const u8) !usize {
    var trimed = std.mem.trim(u8, s, "\n ");
    if (trimed[trimed.len - 1] == 'B' or trimed[trimed.len - 1] == 'b') {
        trimed = trimed[0 .. trimed.len - 1];
    }
    if (trimed.len <= 1) {
        return UtilError.InvalidMemoryUnit;
    }

    const unit_c = trimed[trimed.len - 1];
    var unit: usize = undefined;
    switch (unit_c) {
        'k', 'K' => unit = consts.units.KB,
        'm', 'M' => unit = consts.units.MB,
        'g', 'G' => unit = consts.units.GB,
        else => return UtilError.InvalidMemoryUnit,
    }

    const num_c = trimed[0 .. trimed.len - 1];
    const num = try std.fmt.parseInt(usize, num_c, 10);

    return num * unit;
}

// =================================== //

const expect = std.testing.expect;

test "Unit Convertion" {
    const units = consts.units;

    try expect(try convert_mem_unit(" 32GB ") == 32 * units.GB);
    try expect(try convert_mem_unit("10kb") == 10 * units.KB);
    try expect(try convert_mem_unit("  1m") == 1 * units.MB);
}
