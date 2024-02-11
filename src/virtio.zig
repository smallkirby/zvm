//! TODO: doc

const pci = @import("pci.zig");
const consts = @import("consts.zig");
const cports = consts.ports;
const Bar = pci.DeviceHeaderType0.IoBar;

/// PCI vendor ID for virtio devices
const PCI_VIRTIO_VENDOR_ID = 0x1AF4;
/// PCI device ID for virtio-net.
/// Note that legacy driver uses the subsystem device ID instead.
/// For modern devices, the device ID minus 0x1040 is used as an device ID.
const PCI_VIRTIONET_DEVICE_ID = 0x1041;

/// virtio-net PCI device
pub const VirtioNet = struct {
    configuration: pci.DeviceHeaderType0 = .{
        .vendor_id = PCI_VIRTIO_VENDOR_ID,
        .device_id = PCI_VIRTIONET_DEVICE_ID,
        .header_type = 0,
        .command = .{
            .enable_io_space = true,
            .enable_memory_space = false,
        },
        .bar0 = Bar{
            .use_io_space = true,
            .address = cports.VIRTIONET_IO >> 2,
        },
    },
    // Size of I/O space.
    iospace_size: u32 = cports.VIRTIONET_IO_SIZE,

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
