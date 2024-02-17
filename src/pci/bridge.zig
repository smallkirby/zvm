const std = @import("std");
const dev = @import("device.zig");
const DeviceHeader = dev.DeviceHeader;
const PciDevice = dev.PciDevice;

pub const HostBridge = struct {
    const Self = @This();

    io_port_start: u64 = 0,
    io_port_end: u64 = 0xFFFF,
    // Linux checks if mechanism #1 is available during PCI initialization.
    // One of the below conditions must be satisfied to pass the check:
    //  - The device class and subclass is a host bridge.
    //  - The device class and subclass is a VGA compatible controller.
    //  - The vendor ID is Intel (0x8086).
    //  - The vendor ID is Compaq (0x0E11).
    configuration: DeviceHeader = .{
        .vendor_id = 0x1AE0, // Google
        .device_id = 0,
        .header_type = 1,
        .class_code = 0x06, // Bridge
        .subclass = 0x00, // Host bridge
        // necessary to suppress invalid configuration of bridge warning.
        .bar2 = DeviceHeader.IoBar.from_u32(
            0x00_FF_FF_00, // type1: secondary latency, subordinate bus, secondary bus, primary bus
        ),
    },

    pub fn device(self: *Self) PciDevice {
        return .{
            .ptr = self,
            .io_port_start = self.io_port_start,
            .io_port_end = self.io_port_end,
            .configuration = self.configuration,
            .vtable = &.{
                .in = in,
                .out = out,
                .configuration_in = configuration_in,
                .configuration_out = configuration_out,
                .deinit = deinit,
            },
        };
    }

    fn in(_: *anyopaque, _: u64, _: []u8) void {}
    fn out(_: *anyopaque, _: u64, _: []u8) void {}
    fn configuration_in(_: *anyopaque, _: u64, _: []u8) void {}
    fn configuration_out(_: *anyopaque, _: u64, _: []u8) void {}
    fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};
