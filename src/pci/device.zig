const std = @import("std");
pub const DeviceHeader = @import("../pci.zig").DeviceHeaderType0;

pub const PciDevice = @This();
pub const Error = error{Unknown};

ptr: *anyopaque,
vtable: *const VTable,
io_port_start: u64,
io_port_end: u64,
configuration: DeviceHeader,

pub const VTable = struct {
    in: *const fn (ctx: *anyopaque, port: u64, data: []u8) void,
    out: *const fn (ctx: *anyopaque, port: u64, data: []u8) void,
    configuration_in: *const fn (ctx: *anyopaque, offset: u64, data: []u8) void,
    configuration_out: *const fn (ctx: *anyopaque, offset: u64, data: []u8) void,
    deinit: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
};

pub fn in(self: *@This(), port: u64, data: []u8) Error!void {
    self.vtable.in(self.ptr, port, data);
}

pub fn out(self: *@This(), port: u64, data: []u8) Error!void {
    self.vtable.out(self.ptr, port, data);
}

pub fn configuration_in(self: *@This(), offset: u64, data: []u8) Error!void {
    self.vtable.configuration_in(self.ptr, offset, data);
}

pub fn configuration_out(self: *@This(), offset: u64, data: []u8) Error!void {
    self.vtable.configuration_out(self.ptr, offset, data);
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.vtable.deinit(self.ptr, allocator);
}
