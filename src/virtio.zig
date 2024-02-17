//! virtio-net PCI device.
//! This module provides a modern (non-transitional) virtio device implementation.

const std = @import("std");
const pci = @import("pci.zig");
const dev = @import("pci/device.zig");
const PciDevice = dev.PciDevice;
const consts = @import("consts.zig");
const cports = consts.ports;
const Bar = pci.DeviceHeaderType0.IoBar;

/// PCI vendor ID for virtio devices
const PCI_VIRTIO_VENDOR_ID = 0x1AF4;
/// PCI device ID for virtio-net.
/// Note that legacy(transitional) driver uses the subsystem device ID instead.
/// For modern devices, the device ID minus 0x1040 is used as an device ID.
const PCI_VIRTIONET_DEVICE_ID = 0x1041;

/// virtio-net PCI device
pub const VirtioNet = struct {
    const Self = @This();

    /// Offset of the capability structure in the PCI configuration space.
    /// The first capability is located right after the PCI configuration header,
    /// so the offset is the size of the header.
    const CAP_OFFSET = @sizeOf(pci.DeviceHeaderType0);
    /// The address BAR0 of the virtio-net device points to.
    const BAR0 = cports.VIRTIONET_IO;

    io_port_start: u64 = cports.VIRTIONET_IO,
    io_port_end: u64 = cports.VIRTIONET_IO + cports.VIRTIONET_IO_SIZE,
    allocator: std.mem.Allocator = undefined,
    configuration: pci.DeviceHeaderType0 = .{
        .vendor_id = PCI_VIRTIO_VENDOR_ID,
        .device_id = PCI_VIRTIONET_DEVICE_ID,
        // this is a non-transitional device, so no-need to set subsystem device ID.
        .header_type = 0,
        .command = .{
            .enable_io_space = true,
            .enable_memory_space = false,
        },
        .status = .{
            .capabilities_list = true,
        },
        .capabilities_pointer = CAP_OFFSET,
        .bar0 = Bar{
            .use_io_space = true,
            .address = BAR0 >> 2,
        },
    },
    /// Virtio PCI capability.
    /// This structures are located right after the PCI configuration header
    /// as header's `capabilities_pointer` indicates.
    /// Each of the capability is a descriptor pointing to the actual configuration structure located at BAR0.
    /// TODO: Need more flexible way to automatically calculate the offset of each capability.
    capabilities: [3]VirtioPciCap = [_]VirtioPciCap{
        .{
            .cfg_type = VirtioConfigurationType.COMMON_CFG,
            .bar = 0,
            .offset = 0,
            .cap_next = CAP_OFFSET + @sizeOf(VirtioPciCap),
            .length = @sizeOf(VirtioPciCommonConfig),
        },
        .{
            .cfg_type = VirtioConfigurationType.NOTIFY_CFG,
            .bar = 0,
            .offset = @sizeOf(VirtioPciCommonConfig),
            .cap_next = CAP_OFFSET + 2 * @sizeOf(VirtioPciCap),
            .length = 4,
        },
        .{
            .cfg_type = VirtioConfigurationType.ISR_CFG,
            .bar = 0,
            // TODO: must fix this offset after implementing ISR configuration structure
            .offset = @sizeOf(VirtioPciCommonConfig) + 0,
            .cap_next = 0,
            .length = 1,
        },
    },
    /// Common configuration structure
    cfg_common: VirtioPciCommonConfig = .{},

    /// Allocate a new virtio-net PCI device.
    /// Caller must ensure calling `deinit` after the device is no longer used.
    pub fn new(allocator: std.mem.Allocator) !*Self {
        const vnet = &(try allocator.alloc(Self, 1))[0];
        vnet.* = Self{
            .allocator = allocator,
        };

        return vnet;
    }

    pub fn device(self: *Self) PciDevice {
        return PciDevice{
            .ptr = self,
            .io_port_start = self.io_port_start,
            .io_port_end = self.io_port_end,
            .configuration = self.configuration,
            .vtable = &.{
                .in = in,
                .out = out,
                .configurationIn = configurationIn,
                .configurationOut = configurationOut,
                .deinit = deinit,
            },
        };
    }

    fn in(ctx: *anyopaque, port: u64, data: []u8) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        std.log.debug("virtio-net: in port={X}, data.len={X}", .{ port, data.len });

        if (self.get_configuration(port)) |cfg_off| {
            @memcpy(data, cfg_off.cfg[cfg_off.offset .. cfg_off.offset + data.len]);
        } else {
            std.log.warn("virtio-net: in: invalid port={X}", .{port});
            return;
        }
    }

    fn out(_: *anyopaque, port: u64, data: []u8) void {
        std.log.debug("virtio-net: out port={X}, data.len={X}", .{ port, data.len });
    }

    const ConfigWithOffset = struct {
        cfg: []u8,
        offset: usize,
    };

    /// Get the backing bytes of the configuration structure from the given port.
    fn get_configuration(self: *Self, port: u64) ?ConfigWithOffset {
        switch (port) {
            BAR0...BAR0 + 1 * @sizeOf(VirtioPciCommonConfig) => return .{
                .cfg = std.mem.asBytes(&self.cfg_common),
                .offset = port - BAR0,
            },
            else => return null,
        }
    }

    /// Handle a read event on the PCI configuration space except for the header.
    fn configurationIn(ctx: *anyopaque, offset: u64, data: []u8) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var cap: VirtioPciCap = undefined;
        var cap_offset: usize = 0;

        switch (offset) {
            CAP_OFFSET...CAP_OFFSET + @sizeOf(VirtioPciCap) - 1 => {
                // common configuration
                std.log.debug("virtio-net: Reading common capability: offset={X}, len={X}", .{ offset, data.len });
                cap = self.capabilities[0];
                cap_offset = offset - CAP_OFFSET;
            },
            CAP_OFFSET + @sizeOf(VirtioPciCap)...CAP_OFFSET + 2 * @sizeOf(VirtioPciCap) - 1 => {
                // notify configuration
                std.log.debug("virtio-net: Reading notify capability: offset={X}, len={X}", .{ offset, data.len });
                cap = self.capabilities[1];
                cap_offset = offset - (CAP_OFFSET + @sizeOf(VirtioPciCap));
            },
            CAP_OFFSET + 2 * @sizeOf(VirtioPciCap)...CAP_OFFSET + 3 * @sizeOf(VirtioPciCap) - 1 => {
                // ISR configuration
                std.log.debug("virtio-net: Reading ISR capability: offset={X}, len={X}", .{ offset, data.len });
                cap_offset = offset - (CAP_OFFSET + 2 * @sizeOf(VirtioPciCap));
                cap = self.capabilities[2];
            },
            else => unreachable,
        }

        @memcpy(
            data,
            std.mem.asBytes(&cap)[cap_offset .. cap_offset + data.len],
        );
    }

    /// Handle a write event on the PCI configuration space except for the header.
    fn configurationOut(_: *anyopaque, _: u64, _: []u8) void {}

    fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        allocator.destroy(self);
    }
};

/// virtio PCI capability structure located in the PCI configuration space.
pub const VirtioPciCap = packed struct {
    /// (Generic PCI field) Capability ID
    cap_vndr: u8 = 0x9, // PCI_CAP_ID_VNDR
    /// (Generic PCI field) Next capability pointer
    cap_next: u8 = 0,
    /// (Generic PCI field) Length of capability structure
    cap_len: u8 = @sizeOf(@This()),
    /// Identifies the structure of the virtio configuration
    cfg_type: VirtioConfigurationType,
    /// Which bar to access the configuration structure
    bar: u8 = 0,
    /// Padding
    _padding: u24 = 0,
    /// Offset within the bar
    offset: u32,
    /// Length of the configuration structure
    length: u32,
};

/// Type of virtio configuration structure
const VirtioConfigurationType = enum(u8) {
    COMMON_CFG = 0x1,
    NOTIFY_CFG = 0x2,
    ISR_CFG = 0x3,
};

/// virtio configuration structure for common type
const VirtioPciCommonConfig = packed struct {
    /// RW. Selects which bits are used in `device_features`.
    /// If 0, bits 31:0 are used. If 1, bits 63:32 are used.
    device_features_sel: u32 = 0,
    /// RO for driver. Device features bits.
    device_features: u32 = 0,
    /// RW. Selects which bits are used in `driver_features`.
    /// If 0, bits 31:0 are used. If 1, bits 63:32 are used.
    driver_features_sel: u32 = 0,
    /// RW. Driver features bits.
    driver_features: u32 = 0,
    /// RW. Configuration Vector for MSI-X.
    msix_config: u16 = 0,
    /// RO for driver. The maximum number of virtqueues supported by the device.
    num_queues: u16 = 0x1,
    /// RW. Device status.
    /// Writing 0 to this field resets the device.
    device_status: u8 = 0,
    /// RO for driver. Configuration atomicity value.
    /// The device changes this value when the configuration noticeably changes.
    config_generation: u8 = 0,

    /// RW. The driver selects which virtqueue is being referenced in the following fields.
    queue_select: u16 = 0,
    /// RW. Queue size.
    /// If set to 0, the queue is unavailable.
    /// On reset, the maximum queue size supported by the device.
    queue_size: u16 = 0,
    /// RW. Queue vector for MSI-X.
    queue_msix_vector: u16 = 0,
    /// RW. If set to 1, the queue is enabled.
    queue_enable: u16 = 0,
    /// RO for driver. Offset from start of `notification structure`. Not in bytes.
    queue_notify_off: u16 = 0,
    /// RW. Physical address of the descriptor area.
    queue_desc: u64 = 0,
    /// RW.
    queue_avail: u64 = 0,
    /// RW
    queue_used: u64 = 0,
};
