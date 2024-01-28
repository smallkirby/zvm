//! This module presents PCI and basic PCI devices.

const std = @import("std");
const ArrayList = std.ArrayList;
const consts = @import("consts.zig");
const assert = std.debug.assert;

/// PCI (Peripheral Component Interconnect) and connected devices.
/// We supoort only configuration space access mechanism #1.
pub const Pci = struct {
    /// PCI configuration address register
    config_address: ConfigAddress,
    /// Connected PCI devices
    /// Bus number is always 0.
    /// Device number is assigned by the order of `devices` array.
    /// Function number is always 0.
    devices: ArrayList(PciDevice),

    /// Initialize PCI.
    /// Caller must call `deinit` after use.
    pub fn new(allocator: std.mem.Allocator) !@This() {
        var self = @This(){
            .config_address = .{},
            .devices = ArrayList(PciDevice).init(allocator),
        };

        try self.devices.append(.{ .bridge = PciHostBridge{} });

        return self;
    }

    /// Handle PCI PIO read event.
    pub fn in(self: *@This(), port: u64, data: []u8) !void {
        switch (port) {
            consts.ports.PCI_CONFIG_ADDRESS...(consts.ports.PCI_CONFIG_ADDRESS + 4) - 1 => {
                // TODO: should we consider offset and allow non-4byte read?
                @memcpy(data, std.mem.asBytes(&self.config_address));
            },
            consts.ports.PCI_CONFIG_DATA...(consts.ports.PCI_CONFIG_DATA + 4) - 1 => {
                if (self.config_address.bus != 0) return;
                if (self.config_address.function != 0) return;
                if (self.config_address.device >= self.devices.items.len) return;
                if (self.config_address.enable == false) return;

                const offset = port - consts.ports.PCI_CONFIG_DATA;
                switch (self.devices.items[self.config_address.device]) {
                    inline else => |d| {
                        const reg = self.config_address.offset;
                        @memcpy(
                            data,
                            std.mem.asBytes(&d.configuration)[reg + offset .. reg + offset + data.len],
                        );
                    },
                }
            },
            else => {},
        }
    }

    /// Handle PCI PIO write event.
    pub fn out(self: *@This(), port: u16, data: []u8) !void {
        switch (port) {
            consts.ports.PCI_CONFIG_ADDRESS...(consts.ports.PCI_CONFIG_ADDRESS + 4) - 1 => {
                const offset = port - consts.ports.PCI_CONFIG_ADDRESS;
                var v = std.mem.asBytes(&self.config_address);
                for (0..data.len) |i| {
                    if (i + offset >= 4) break;
                    v[i + offset] = data[i];
                }
                self.config_address = ConfigAddress.from_u32(std.mem.readIntLittle(u32, v));
            },
            consts.ports.PCI_CONFIG_DATA => {}, // TODO
            else => {},
        }
    }

    fn data_to_u32(data: []u8) u32 {
        // PIC configuration space is little endian regardless of the host endian.
        switch (data.len) {
            1 => return @intCast(data[0]),
            2 => return std.mem.readIntLittle(u16, data[0..2]),
            4 => return std.mem.readIntLittle(u32, data[0..4]),
            else => unreachable,
        }
    }

    /// Deinitialize PCI.
    pub fn deinit(self: *@This()) void {
        self.devices.deinit();
    }
};

/// Configration address register.
const ConfigAddress = packed struct {
    offset: u8 = 0,
    function: u3 = 0,
    device: u5 = 0,
    bus: u8 = 0,
    reserved: u7 = 0,
    /// Enable bit.
    /// If this bit is set, the configuration space of the device is accessible.
    enable: bool = false,

    comptime {
        if (@sizeOf(@This()) != 4) {
            @compileError("Invalid size of ConfigAddress");
        }
    }

    pub fn as_u32(self: @This()) u32 {
        return @as(u32, @bitCast(self));
    }

    pub fn from_u32(v: u32) @This() {
        return @as(@This(), @bitCast(v));
    }
};

/// PCI device header of type 0x0 in a configuration register.
const DeviceHeaderType0 = packed struct {
    vendor_id: u16 = 0xFFFF, // invalid, not exist
    device_id: u16 = 0,
    command: u16 = 0,
    status: u16 = 0,
    revision_id: u8 = 0,
    prog_if: u8 = 0,
    subclass: u8 = 0,
    class_code: u8 = 0,
    cache_line_size: u8 = 0,
    latency_timer: u8 = 0,
    header_type: u8 = 0,
    bist: u8 = 0,
    bar0: u32 = 0,
    bar1: u32 = 0,
    bar2: u32 = 0,
    bar3: u32 = 0,
    bar4: u32 = 0,
    bar5: u32 = 0,
    cardbus_cis_pointer: u32 = 0,
    subsystem_vendor_id: u16 = 0,
    subsystem_id: u16 = 0,
    expansion_rom_base_address: u32 = 0,
    capabilities_pointer: u8 = 0,
    reserved: u56 = 0,
    interrupt_line: u8 = 0,
    interrupt_pin: u8 = 0,
    min_grant: u8 = 0,
    max_latency: u8 = 0,

    comptime {
        if (@sizeOf(@This()) != 64) {
            @compileError("Invalid size of ConfigurationRegisterType0");
        }
    }
};

/// PCI device interface.
const PciDevice = union(enum) {
    bridge: PciHostBridge,
    // Add other device interfaces here.
};

const PciHostBridge = struct {
    // Linux checks if mechanism #1 is available during PCI initialization.
    // One of the below conditions must be satisfied to pass the check:
    //  - The device class and subclass is a host bridge.
    //  - The device class and subclass is a VGA compatible controller.
    //  - The vendor ID is Intel (0x8086).
    //  - The vendor ID is Compaq (0x0E11).
    configuration: DeviceHeaderType0 = .{
        .vendor_id = 0x1AE0, // Google
        .device_id = 0,
        .header_type = 1,
        .class_code = 0x06, // Bridge
        .subclass = 0x00, // Host bridge
    },

    pub fn in(self: @This(), port: u64, data: []u8) !void {
        _ = self;
        _ = port;
        _ = data;
        return;
    }

    pub fn out(self: @This(), port: u64, data: []u8) !void {
        _ = self;
        _ = port;
        _ = data;
        return;
    }
};

// =================================== //
