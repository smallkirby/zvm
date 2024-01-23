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
    pub const CMDLINE = 0x0001_0000;
    /// Where the kernel code is loaded
    pub const KERNEL_BASE = 0x0010_0000;
};
