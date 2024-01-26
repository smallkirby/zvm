//! This module provides sets of constants.

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
    /// TODO: should adjust depending on the given memory size.
    pub const INITRD = 0x00A0_0000;
    /// Available highest address of the initial ramdisk.
    pub const INITRD_MAX = 0x0100_0000;
};

pub const units = struct {
    pub const KB = 1024;
    pub const MB = 1024 * KB;
    pub const GB = 1024 * MB;
};

pub const kvm = struct {
    pub const KVM_CPUID_SIGNATURE = 0x4000_0000;
};
