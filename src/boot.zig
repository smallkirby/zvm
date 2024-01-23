//! This module contains the representation of the linux kernel header.

const std = @import("std");

/// Representation of the linux kernel header.
/// This header compiles with protocol v2.15.
const KernelHeader = packed struct {
    /// RO. The number of setup sectors.
    setup_sects: u8,
    root_flags: u16,
    syssize: u32,
    ram_size: u16,
    vid_mode: u16,
    root_dev: u16,
    boot_flag: u16,
    jump: u16,
    header: u32,
    /// RO. Boot protocol version supported.
    version: u16,
    realmode_swtch: u32,
    start_sys_seg: u16,
    kernel_version: u16,
    type_of_loader: u8,
    loadflags: u8,
    setup_move_size: u16,
    code32_start: u32,
    ramdisk_image: u32,
    ramdisk_size: u32,
    bootsect_kludge: u32,
    heap_end_ptr: u16,
    ext_loader_ver: u8,
    ext_loader_type: u8,
    cmd_line_ptr: u32,
    initrd_addr_max: u32,
    kernel_alignment: u32,
    relocatable_kernel: u8,
    min_alignment: u8,
    xloadflags: u16,
    cmdline_size: u32,
    hardware_subarch: u32,
    hardware_subarch_data: u64,
    payload_offset: u32,
    payload_length: u32,
    setup_data: u64,
    pref_address: u64,
    init_size: u32,
    handover_offset: u32,
    kernel_info_offset: u32,

    /// The offset where the header starts in the bzImage.
    pub const HeaderOffset = 0x1F1;

    comptime {
        if (@sizeOf(@This()) != 128) {
            @compileError("Unexpected kernel header size");
        }
    }

    /// Instantiate a header from bzImage.
    pub fn from_bytes(bytes: []u8) @This() {
        var hdr = std.mem.bytesToValue(
            @This(),
            bytes[HeaderOffset .. HeaderOffset + @sizeOf(@This())],
        );
        if (hdr.setup_sects == 0) {
            hdr.setup_sects = 4;
        }

        return hdr;
    }

    /// Get the version string.
    /// Caller must free the returned string.
    pub fn get_version_string(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        const minor = self.version & 0xFF;
        const major = (self.version >> 8) & 0xFF;
        return try std.fmt.allocPrint(
            allocator,
            "{d}.{d}",
            .{ major, minor },
        );
    }
};

// =================================== //

const expect = std.testing.expect;

test "header compatibility" {
    const offset = KernelHeader.HeaderOffset;
    try expect(@offsetOf(KernelHeader, "setup_sects") == 0);
    try expect(@offsetOf(KernelHeader, "loadflags") == 0x0211 - offset);
    try expect(@offsetOf(KernelHeader, "initrd_addr_max") == 0x022C - offset);
}

test "load header" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile(
        "test/assets/kheader.bin",
        .{ .mode = .read_only },
    );
    const buf = try allocator.alloc(u8, (try file.stat()).size);
    defer allocator.free(buf);
    _ = try file.readAll(buf);

    var hdr = KernelHeader.from_bytes(buf);
    const vstr = try hdr.get_version_string(allocator);
    defer allocator.free(vstr);

    try expect(std.mem.eql(u8, vstr, "2.15"));
    try expect(hdr.setup_sects == 0x1B);
    try expect(hdr.init_size == 0x014AF000);
}
