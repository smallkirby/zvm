//! This module contains the representation of the linux kernel header.

const std = @import("std");

/// Representation of the linux kernel header.
/// This header compiles with protocol v2.15.
pub const SetupHeader = extern struct {
    /// RO. The number of setup sectors.
    setup_sects: u8 align(1),
    root_flags: u16 align(1),
    syssize: u32 align(1),
    ram_size: u16 align(1),
    vid_mode: u16 align(1),
    root_dev: u16 align(1),
    boot_flag: u16 align(1),
    jump: u16 align(1),
    header: u32 align(1),
    /// RO. Boot protocol version supported.
    version: u16 align(1),
    realmode_swtch: u32 align(1),
    start_sys_seg: u16 align(1),
    kernel_version: u16 align(1),
    /// M. The type of loader. Specify 0xFF if no ID is assigned.
    type_of_loader: u8 align(1),
    /// M. Bitmask.
    loadflags: LoadflagBitfield align(1),
    setup_move_size: u16 align(1),
    code32_start: u32 align(1),
    /// M. The 32-bit linear address of initial ramdisk or ramfs.
    /// Specify 0 if there is no ramdisk or ramfs.
    ramdisk_image: u32 align(1),
    /// M. The size of the initial ramdisk or ramfs.
    ramdisk_size: u32 align(1),
    bootsect_kludge: u32 align(1),
    /// W. Offset of the end of the setup/heap minus 0x200.
    heap_end_ptr: u16 align(1),
    /// W(opt). Extension of the loader ID.
    ext_loader_ver: u8 align(1),
    ext_loader_type: u8 align(1),
    /// W. The 32-bit linear address of the kernel command line.
    cmd_line_ptr: u32 align(1),
    /// R. Higest address that can be used for initrd.
    initrd_addr_max: u32 align(1),
    kernel_alignment: u32 align(1),
    relocatable_kernel: u8 align(1),
    min_alignment: u8 align(1),
    xloadflags: u16 align(1),
    /// R. Maximum size of the cmdline.
    cmdline_size: u32 align(1),
    hardware_subarch: u32 align(1),
    hardware_subarch_data: u64 align(1),
    payload_offset: u32 align(1),
    payload_length: u32 align(1),
    setup_data: u64 align(1),
    pref_address: u64 align(1),
    init_size: u32 align(1),
    handover_offset: u32 align(1),
    kernel_info_offset: u32 align(1),

    /// Bitfield for loadflags.
    const LoadflagBitfield = packed struct(u8) {
        /// If true, the protected-mode code is loaded at 0x100000.
        LOADED_HIGH: bool = false,
        /// If true, KASLR enabled.
        KASLR_FLAG: bool = false,
        _unused: u3 = 0,
        /// If false, print early messages.
        QUIET_FLAG: bool = false,
        /// If false, reload the segment registers in the 32bit entry point.
        KEEP_SEGMENTS: bool = false,
        /// Set true to indicate that the value entered in the `heap_end_ptr` is valid.
        CAN_USE_HEAP: bool = false,

        /// Convert to u8.
        pub fn to_u8(self: @This()) u8 {
            return @bitCast(self);
        }
    };

    /// The offset where the header starts in the bzImage.
    pub const HeaderOffset = 0x1F1;

    comptime {
        if (@sizeOf(@This()) != 0x7B) {
            @compileError("Unexpected SetupHeader size");
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

    /// Get the offset of the protected-mode kernel code.
    /// Real-mode code consists of the boot sector (1 sector == 512 bytes)
    /// plus the setup code (`setup_sects` sectors).
    pub fn get_protected_code_offset(self: @This()) usize {
        return (@as(usize, self.setup_sects) + 1) * 512;
    }
};

pub const E820Entry = extern struct {
    addr: u64 align(1),
    size: u64 align(1),
    type: Type align(1),

    pub const Type = enum(u32) {
        /// RAM.
        RAM = 1,
        /// Reserved.
        RESERVED = 2,
        /// ACPI reclaimable memory.
        ACPI = 3,
        /// ACPI NVS memory.
        NVS = 4,
        /// Unusable memory region.
        UNUSABLE = 5,
    };

    comptime {
        std.debug.assert(@bitSizeOf(@This()) == 0x14 * 8);
    }
};

/// Port of struct boot_params in linux kernel.
/// Note that fields prefixed with `_` are not implemented and have incorrect types.
pub const BootParams = extern struct {
    /// Maximum number of entries in the E820 map.
    const E280MAX = 128;

    _screen_info: [0x40]u8 align(1),
    _apm_bios_info: [0x14]u8 align(1),
    _pad2: [4]u8 align(1),
    tboot_addr: u64 align(1),
    ist_info: [0x10]u8 align(1),
    _pad3: [0x10]u8 align(1),
    hd0_info: [0x10]u8 align(1),
    hd1_info: [0x10]u8 align(1),
    _sys_desc_table: [0x10]u8 align(1),
    _olpc_ofw_header: [0x10]u8 align(1),
    _pad4: [0x80]u8 align(1),
    _edid_info: [0x80]u8 align(1),
    _efi_info: [0x20]u8 align(1),
    alt_mem_k: u32 align(1),
    scratch: u32 align(1),
    /// Number of entries in the E820 map.
    e820_entries: u8 align(1),
    eddbuf_entries: u8 align(1),
    edd_mbr_sig_buf_entries: u8 align(1),
    kbd_status: u8 align(1),
    _pad6: [5]u8 align(1),
    /// Setup header.
    hdr: SetupHeader,
    _pad7: [0x290 - SetupHeader.HeaderOffset - @sizeOf(SetupHeader)]u8 align(1),
    _edd_mbr_sig_buffer: [0x10]u32 align(1),
    /// System memory map that can be retrieved by INT 15, E820h.
    e820_map: [E280MAX]E820Entry align(1),
    _unimplemented: [0x330]u8 align(1), // TODO: implement this.

    comptime {
        if (@sizeOf(@This()) != 0x1000) {
            @compileError("Unexpected BootParams size");
        }
    }

    /// Instantiate a boot params from bzImage.
    pub fn from_bytes(bytes: []u8) @This() {
        return std.mem.bytesToValue(
            @This(),
            bytes[0..@sizeOf(@This())],
        );
    }

    /// Add an entry to the E820 map.
    pub fn add_e820_entry(
        self: *@This(),
        addr: u64,
        size: u64,
        type_: E820Entry.Type,
    ) void {
        self.e820_map[self.e820_entries].addr = addr;
        self.e820_map[self.e820_entries].size = size;
        self.e820_map[self.e820_entries].type = type_;
        self.e820_entries += 1;
    }
};

// =================================== //

const expect = std.testing.expect;

test "header compatibility" {
    const offset = SetupHeader.HeaderOffset;
    try expect(@offsetOf(SetupHeader, "setup_sects") == 0);
    try expect(@offsetOf(SetupHeader, "root_flags") == 0x1F2 - offset);
    try expect(@offsetOf(SetupHeader, "syssize") == 0x01F4 - offset);
    try expect(@offsetOf(SetupHeader, "jump") == 0x0200 - offset);
    try expect(@offsetOf(SetupHeader, "loadflags") == 0x0211 - offset);
    try expect(@offsetOf(SetupHeader, "initrd_addr_max") == 0x022C - offset);
}

test "boot_params compatibility" {
    const offset = SetupHeader.HeaderOffset;
    try expect(@offsetOf(BootParams, "hd1_info") == 0x090);
    try expect(@offsetOf(BootParams, "_efi_info") == 0x1C0);
    try expect(@offsetOf(BootParams, "e820_entries") == 0x1E8);
    try expect(@offsetOf(BootParams, "eddbuf_entries") == 0x1E9);
    try expect(@offsetOf(BootParams, "edd_mbr_sig_buf_entries") == 0x1EA);
    try expect(@offsetOf(BootParams, "hdr") == offset);
    try expect(@bitOffsetOf(BootParams, "hdr") == offset * 8);
    try expect(@offsetOf(BootParams, "_edd_mbr_sig_buffer") == 0x290);
}

test "loadflags compatibility" {
    var loadflags = SetupHeader.LoadflagBitfield{};

    loadflags.LOADED_HIGH = true;
    loadflags.KEEP_SEGMENTS = true;
    try expect(loadflags.to_u8() == 0b0100_0001);
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

    var hdr = SetupHeader.from_bytes(buf);
    const vstr = try hdr.get_version_string(allocator);
    defer allocator.free(vstr);

    try expect(std.mem.eql(u8, vstr, "2.15"));
    try expect(hdr.setup_sects == 0x1B);
    try expect(hdr.init_size == 0x014AF000);
}

test "load boot_params" {
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

    var hdr = SetupHeader.from_bytes(buf);
    var params = BootParams.from_bytes(buf);
    try expect(params.hdr.setup_sects == hdr.setup_sects);
    try expect(params.hdr.init_size == hdr.init_size);

    const v1 = try params.hdr.get_version_string(allocator);
    const v2 = try hdr.get_version_string(allocator);
    defer allocator.free(v1);
    defer allocator.free(v2);
    try expect(std.mem.eql(u8, v1, v2));
}
