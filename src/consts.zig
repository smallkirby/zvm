//! This module provides sets of constants.

const std = @import("std");
const linux = std.os.linux;

pub const x64 = struct {
    /// Page size in bytes
    pub const PAGE_SIZE = 0x1000;
    /// Sector size in bytes
    pub const SECTOR_SIZE = 512;
};

pub const layout = struct {
    /// Where the kernel boot parameters are loaded, known as "zero page".
    /// Must be initialized by zeros.
    pub const BOOTPARAM = 0x0001_0000;
    /// Where the kernel cmdline is located.
    pub const CMDLINE = 0x0002_0000;
    /// Where the protected-mode kernel code is loaded
    pub const KERNEL_BASE = 0x0010_0000;
    /// Where the initial ramdisk is loaded.
    pub const INITRD = 0x3000_0000;
};

pub const ports = struct {
    /// Register to specify the PCI configuration space address.
    pub const PCI_CONFIG_ADDRESS = 0x0CF8;
    /// Register to read/write the PCI configuration space data.
    /// The data address is specified by `PCI_CONFIG_ADDRESS` register.
    pub const PCI_CONFIG_DATA = 0x0CFC;

    /// Start address of the I/O port space for virtio-net device.
    pub const VIRTIONET_IO = 0x1000;
    /// Size of the I/O port space for virtio-net device.
    pub const VIRTIONET_IO_SIZE = 0x100;
};

pub const units = struct {
    pub const KB = 1024;
    pub const MB = 1024 * KB;
    pub const GB = 1024 * MB;
};

pub const kvm = struct {
    pub const KVM_NR_INTERRUPTS = 256;

    pub const KVM_CPUID_FEATURES = 0x4000_0001;

    pub const KVM_EXIT_IO = 0x00000002;
    pub const KVM_EXIT_HLT = 0x00000005;
    pub const KVM_EXIT_SHUTDOWN = 0x00000008;

    pub const KVM_EXIT_IO_IN = 0x00000000;
    pub const KVM_EXIT_IO_OUT = 0x00000001;
};
