//! This module provides a set of PIO devices.

const std = @import("std");
const ArrayList = std.ArrayList;

pub const srl = @import("pio/serial.zig");

/// Interface for PIO devices.
pub const PioInterface = union(enum) {
    serial: *srl.SerialUart8250,

    /// Handle PIO read event.
    pub fn in(self: @This(), port: u16, data: []u8) !void {
        switch (self) {
            inline else => |s| try s.in(port, data),
        }
    }

    /// Handle PIO write event.
    pub fn out(self: @This(), port: u16, data: []u8) !void {
        switch (self) {
            inline else => |s| try s.out(port, data),
        }
    }
};

/// PIO device.
pub const PioDevice = struct {
    /// Start of an address to which the device is mapped.
    addr_start: u16,
    /// Excludive end of an address to which the device is mapped.
    addr_end: u16,
    /// Device interface.
    interface: PioInterface,

    pub fn in(self: @This(), port: u16, data: []u8) !void {
        try self.interface.in(port, data);
    }

    pub fn out(self: @This(), port: u16, data: []u8) !void {
        try self.interface.out(port, data);
    }
};

/// PIO device manager.
pub const PioDeviceManager = struct {
    /// All available PIO devices
    devices: ArrayList(PioDevice),

    pub fn new(allocator: std.mem.Allocator) @This() {
        return @This(){
            .devices = ArrayList(PioDevice).init(allocator),
        };
    }

    /// Add a new device.
    pub fn add_device(self: *@This(), device: PioDevice) !void {
        try self.devices.append(device);
    }

    /// Pass I/O read event to a corresponding device.
    /// If no device is found, the event is ignored.
    pub fn in(self: *@This(), port: u16, data: []u8) !void {
        for (self.devices.items) |device| {
            if (device.addr_start <= port and port <= device.addr_end) {
                try device.interface.in(port, data);
                return;
            }
        }
    }

    /// Pass I/O write event to a corresponding device.
    /// If no device is found, the event is ignored.
    pub fn out(self: *@This(), port: u16, data: []u8) !void {
        for (self.devices.items) |device| {
            if (device.addr_start <= port and port <= device.addr_end) {
                try device.interface.out(port, data);
                return;
            }
        }
    }

    pub fn deinit(self: *@This()) void {
        self.devices.deinit();
    }
};

// =================================== //

const expect = std.testing.expect;

test "PIO Device" {
    var s = srl.SerialUart8250.new(-1);
    var device = PioDevice{
        .addr_start = 0x3F8,
        .addr_end = 0x3FF,
        .interface = PioInterface{ .serial = &s },
    };

    var data = [_]u8{0xFF} ** 0x30;
    try device.out(srl.SerialUart8250.PORTS.COM1, &data);
    try expect(device.interface.serial.*.regs.thr == 0xFF);
    try device.in(srl.SerialUart8250.PORTS.COM1, &data);
    try expect(data[0] == 0x00);
}

test "PIO Device Manager" {
    var manager = PioDeviceManager.new(std.heap.page_allocator);
    var s = srl.SerialUart8250.new(-1);

    try manager.add_device(.{
        .addr_start = srl.SerialUart8250.PORTS.COM1,
        .addr_end = srl.SerialUart8250.PORTS.COM1 + 8,
        .interface = .{ .serial = &s },
    });

    var data = [_]u8{0xFF} ** 0x30;
    try manager.out(srl.SerialUart8250.PORTS.COM1, &data);
    try expect(s.regs.thr == 0xFF);
    try manager.in(srl.SerialUart8250.PORTS.COM1, &data);
    try expect(data[0] == 0x00);
}
