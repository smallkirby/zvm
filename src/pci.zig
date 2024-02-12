//! This module presents PCI and basic PCI devices.

const std = @import("std");
const ArrayList = std.ArrayList;
const consts = @import("consts.zig");
const virtio = @import("virtio.zig");
const dev = @import("pci/device.zig");
const PciDevice = dev.PciDevice;
const HostBridge = @import("pci/bridge.zig").HostBridge;
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
    /// General allocator used for this struct.
    allocator: std.mem.Allocator,

    /// Initialize PCI.
    /// Caller must call `deinit` after use.
    pub fn new(allocator: std.mem.Allocator) !@This() {
        var self = @This(){
            .config_address = .{},
            .devices = ArrayList(PciDevice).init(allocator),
            .allocator = allocator,
        };

        const bridge = &(try allocator.alloc(HostBridge, 1))[0];
        bridge.* = HostBridge{};
        try self.devices.append(bridge.device());

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
                if (self.config_address.bus != 0 // bus number is always 0
                or self.config_address.function != 0 // function number is always 0
                or self.config_address.device >= self.devices.items.len // exceed the number of devices
                ) {
                    for (0..data.len) |i| {
                        data[i] = 0xFF;
                    }
                    return;
                }
                if (self.config_address.enable == false) return;

                const reg = self.config_address.offset;
                const offset = port - consts.ports.PCI_CONFIG_DATA;
                std.log.debug(
                    "PCI configuration read @ {X:0>4}:{X:0>2}:{X:0>2}: reg={X}, offset={X}",
                    .{
                        self.config_address.bus,
                        self.config_address.device,
                        self.config_address.function,
                        reg,
                        offset,
                    },
                );

                const d = &self.devices.items[self.config_address.device];
                if (get_bar(d.configuration, reg, offset)) |bar| {
                    if (bar.to_u32() == 0xFFFF_FFFF and data.len == 4 and reg == @offsetOf(DeviceHeaderType0, "bar0")) {
                        // they are asking the size of I/O space.
                        // for now, we respond only to BAR0 request.
                        std.mem.writeIntLittle(u32, data[0..4], @as(u32, @intCast(d.io_port_end - d.io_port_start)));
                        std.log.debug("Responding I/O space size: {X}", .{d.io_port_end - d.io_port_start});
                        return;
                    }
                }

                if (reg + offset >= @sizeOf(DeviceHeaderType0)) {
                    try d.configurationIn(reg + offset, data);
                } else {
                    @memcpy(
                        data,
                        std.mem.asBytes(&d.configuration)[reg + offset .. reg + offset + data.len],
                    );
                }
            },
            else => {
                std.log.debug("PCI: in  :unknown port: 0x{X:0>4}", .{port});
            },
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
            consts.ports.PCI_CONFIG_DATA => {
                if (self.config_address.bus != 0 // bus number is always 0
                or self.config_address.function != 0 // function number is always 0
                or self.config_address.device >= self.devices.items.len // exceed the number of devices
                ) return;
                if (self.config_address.enable == false) return;

                const offset = port - consts.ports.PCI_CONFIG_DATA;
                const reg = self.config_address.offset;
                std.log.debug(
                    "PCI configuration write @ {X:0>4}:{X:0>2}:{X:0>2}: reg={X}, offset={X}",
                    .{
                        self.config_address.bus,
                        self.config_address.device,
                        self.config_address.function,
                        reg,
                        offset,
                    },
                );

                const d = &self.devices.items[self.config_address.device];
                var v = @constCast(std.mem.asBytes(&d.configuration));
                for (0..data.len) |i| {
                    v[i + offset + reg] = data[i];
                }
                d.configuration = std.mem.bytesToValue(DeviceHeaderType0, v);
            },
            else => {
                std.log.debug("PCI: out :unknown port: 0x{X:0>4}", .{port});
            },
        }
    }

    /// Get the BAR which is referred by the given reg and offset.
    /// Note that offset must be 4-byte aligned,
    /// otherwise this function returns null.
    fn get_bar(
        header: DeviceHeaderType0,
        reg: u16,
        offset: u64,
    ) ?DeviceHeaderType0.IoBar {
        if ( //
        @offsetOf(DeviceHeaderType0, "bar0") <= reg + offset //
        and reg + offset < @offsetOf(DeviceHeaderType0, "bar5") + @sizeOf(DeviceHeaderType0.IoBar) //
        and offset % 4 != 0) {
            return null;
        }

        switch (reg + offset) {
            @offsetOf(DeviceHeaderType0, "bar0") => return header.bar0,
            @offsetOf(DeviceHeaderType0, "bar1") => return header.bar1,
            @offsetOf(DeviceHeaderType0, "bar2") => return header.bar2,
            @offsetOf(DeviceHeaderType0, "bar3") => return header.bar3,
            @offsetOf(DeviceHeaderType0, "bar4") => return header.bar4,
            @offsetOf(DeviceHeaderType0, "bar5") => return header.bar5,
            else => return null,
        }
    }

    /// Connect a PCI device.
    pub fn add_device(self: *@This(), device: PciDevice) !void {
        try self.devices.append(device);
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
        for (self.devices.items) |*device| {
            device.deinit(self.allocator);
        }
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
pub const DeviceHeaderType0 = packed struct {
    vendor_id: u16 = 0xFFFF, // invalid, not exist
    device_id: u16 = 0,
    command: CommandRegister = .{},
    status: StatusRegister = .{},
    revision_id: u8 = 0,
    prog_if: u8 = 0,
    subclass: u8 = 0,
    class_code: u8 = 0,
    cache_line_size: u8 = 0,
    latency_timer: u8 = 0,
    header_type: u8 = 0,
    bist: u8 = 0,
    bar0: IoBar = .{},
    bar1: IoBar = .{},
    bar2: IoBar = .{},
    bar3: IoBar = .{},
    bar4: IoBar = .{},
    bar5: IoBar = .{},
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

    /// I/O Space Base Address Register
    pub const IoBar = packed struct(u32) {
        /// If true, the device uses I/O space.
        /// If false, the device uses memory space.
        /// We only support I/O space BAR, so this bit must be set.
        use_io_space: bool = false,
        /// Reserved for I/O space BAR.
        reserved: u1 = 0,
        /// 4-byte aligned base address.
        address: u30 = 0,

        pub fn to_u32(self: @This()) u32 {
            return @bitCast(self);
        }

        pub fn from_u32(v: u32) @This() {
            return @bitCast(v);
        }
    };

    /// Command register.
    pub const CommandRegister = packed struct(u16) {
        /// If set true, device responds to I/O space accesses.
        enable_io_space: bool = true,
        /// If set true, device responds to memory space accesses.
        enable_memory_space: bool = false,
        /// If set true, device behaves as a bus master.
        bus_master: bool = false,
        /// If set true, device can monitor special cycle operations.
        special_cycles: bool = false,
        /// If set true, device can generate memory write and invalidate operations.
        mem_write_and_invalidate_enable: bool = false,
        /// If set true, device does not respond to palette register writes.
        vga_palette_snoop: bool = false,
        /// If set true, device takes normal action for a parity error.
        parity_error_response: bool = false,
        _reserved1: bool = false,
        /// If set true, SERR# driver is enabled.
        serr_enable: bool = false,
        /// If set true, device is allowed to generate fast back-to-back transactions.
        fast_back_to_back_enable: bool = false,
        /// If set true, INTx# signal is not asserted.
        interrupt_disable: bool = false,
        _reserved2: u5 = 0,
    };

    pub const StatusRegister = packed struct(u16) {
        _reserved1: u3 = 0,
        interrupt_status: bool = false,
        /// If set to true, the device inmpllements the pointer for a New Capabilities List.
        capabilities_list: bool = false,
        mhz66_capable: bool = false,
        _reserved2: u1 = 0,
        fast_back_to_back_capable: bool = false,
        master_data_parity_error: bool = false,
        devsel_timing: u2 = 0,
        signaled_target_abort: bool = false,
        received_target_abort: bool = false,
        received_master_abort: bool = false,
        signaled_system_error: bool = false,
        detected_parity_error: bool = false,
    };
};

// =================================== //

const expect = std.testing.expect;

test "PCI Configuration BAR0 size read" {
    const allocator = std.heap.page_allocator;
    var pci = try Pci.new(allocator);
    defer pci.deinit();

    const vnet = try virtio.VirtioNet.new(allocator);
    try pci.add_device(vnet.device());

    var addr = ConfigAddress{
        .offset = @offsetOf(DeviceHeaderType0, "bar0"),
        .device = 1,
        .enable = true,
    };

    // set addr to PCI_CONFIG_ADDRESS
    try pci.out(consts.ports.PCI_CONFIG_ADDRESS, std.mem.asBytes(&addr));
    try expect(pci.config_address.as_u32() == addr.as_u32());

    // read BAR0 original value
    var data = [_]u8{ 0, 0, 0, 0 };
    try pci.in(consts.ports.PCI_CONFIG_DATA, &data);
    const original_bar0 = std.mem.readIntLittle(u32, &data);
    try expect(original_bar0 == 0x1001);

    // set BAR0 to 0xFFFF_FFFF
    std.mem.writeIntLittle(u32, &data, 0xFFFF_FFFF);
    try pci.out(consts.ports.PCI_CONFIG_DATA, &data);
    try expect(pci.devices.items[1].configuration.bar0.to_u32() == 0xFFFF_FFFF);

    // read BAR0 size
    try pci.in(consts.ports.PCI_CONFIG_DATA, &data);
    try expect(std.mem.readIntLittle(u32, &data) == consts.ports.VIRTIONET_IO_SIZE);

    // set BAR0 to original value
    std.mem.writeIntLittle(u32, &data, original_bar0);
    try pci.out(consts.ports.PCI_CONFIG_DATA, &data);
    try expect(pci.devices.items[1].configuration.bar0.to_u32() == original_bar0);
}
