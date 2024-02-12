//! TODO: doc

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
/// Note that legacy driver uses the subsystem device ID instead.
/// For modern devices, the device ID minus 0x1040 is used as an device ID.
const PCI_VIRTIONET_DEVICE_ID = 0x1040;

/// virtio-net PCI device
pub const VirtioNet = struct {
    const Self = @This();

    /// Offset of the capability structure in the PCI configuration space.
    const CAP_OFFSET = @sizeOf(pci.DeviceHeaderType0);

    io_port_start: u64 = cports.VIRTIONET_IO,
    io_port_end: u64 = cports.VIRTIONET_IO + cports.VIRTIONET_IO_SIZE,
    allocator: std.mem.Allocator = undefined,
    configuration: pci.DeviceHeaderType0 = .{
        .vendor_id = PCI_VIRTIO_VENDOR_ID,
        .device_id = PCI_VIRTIONET_DEVICE_ID,
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
            .address = cports.VIRTIONET_IO >> 2,
        },
    },
    /// Virtio PCI capability
    capabilities: [3]VirtioPciCap = [_]VirtioPciCap{
        .{
            .cfg_type = VirtioConfigurationType.COMMON_CFG,
            .bar = 0,
            .offset = CAP_OFFSET,
            .cap_next = CAP_OFFSET + @sizeOf(VirtioPciCap),
            .length = @sizeOf(VirtioPciCommonConfig),
        },
        .{
            .cfg_type = VirtioConfigurationType.NOTIFY_CFG,
            .bar = 0,
            .offset = CAP_OFFSET + @sizeOf(VirtioPciCap),
            .cap_next = CAP_OFFSET + 2 * @sizeOf(VirtioPciCap),
            .length = 4,
        },
        .{
            .cfg_type = VirtioConfigurationType.ISR_CFG,
            .bar = 0,
            .offset = CAP_OFFSET + 2 * @sizeOf(VirtioPciCap),
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

    fn in(_: *anyopaque, port: u64, data: []u8) void {
        std.log.debug("virtio-net: in port={X}, data.len={X}", .{ port, data.len });
    }

    fn out(_: *anyopaque, _: u64, _: []u8) void {}

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
    device_features_sel: u32 = 0,
    device_features: u32 = 0,
    driver_features_sel: u32 = 0,
    driver_features: u32 = 0,
    msix_config: u16 = 0,
    num_queues: u16 = 0x1,
    device_status: u8 = 0,
    config_generation: u8 = 0,

    queue_select: u16 = 0,
    queue_size: u16 = 0,
    queue_msix_vector: u16 = 0,
    queue_enable: u16 = 0,
    queue_notify_off: u16 = 0,
    queue_desc: u64 = 0,
    queue_avail: u64 = 0,
    queue_used: u64 = 0,
};
