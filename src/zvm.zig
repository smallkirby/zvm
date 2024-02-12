//! This module provides a main feature of VMM

const std = @import("std");
const kvm = @import("kvm.zig");
const consts = @import("consts.zig");
const cid = @import("cpuid.zig");
const boot = @import("boot.zig");
const builtin = @import("builtin");
const terminal = @import("terminal.zig");
const pio = @import("pio.zig");
const pci = @import("pci.zig");
const virtio = @import("virtio.zig");
const linux = std.os.linux;

pub const VMError = error{
    /// VM or vCPU is not ready for the operations
    NotReady,
    /// KVM API is not compatible
    ApiIncompatible,
    /// Guest physical memory is not enough
    GMemNotEnough,
};

/// Instance of a VMM
pub const VM = struct {
    /// File descriptor for /dev/kvm
    kvm_fd: kvm.kvm_fd_t,
    /// File descriptor for the VM
    vm_fd: kvm.vm_fd_t,
    /// List of vCPUs
    vcpus: []VCPU,
    /// Memory allocator used by the VM
    page_allocator: std.mem.Allocator,
    /// Memory allocator used by the VMM for internal use
    general_allocator: std.mem.Allocator,
    /// Guest physical memory.
    guest_mem: []u8,
    /// 8250 serial console
    serial: pio.srl.SerialUart8250,
    /// PS/2 controller
    ps2: pio.ps2.Ps2Controller,
    /// PCI
    pci: pci.Pci,
    /// Device manager
    device_manager: pio.PioDeviceManager,
    /// TTY
    tty: terminal.Tty,

    pub const VMOption = struct {
        /// Memory allocator used by the VM
        page_allocator: std.mem.Allocator,
        /// Memory allocator used by the VMM for internal use
        general_allocator: std.mem.Allocator,
        /// Guest physical memory size in bytes
        mem_size_bytes: usize,
    };

    /// Instantiate a new VM class
    pub fn new() !@This() {
        comptime {
            switch (builtin.target.os.tag) {
                .linux => {},
                else => @compileError("The OS is not supported.\n"),
            }
        }

        return .{
            .kvm_fd = undefined,
            .vm_fd = undefined,
            .vcpus = &.{},
            .page_allocator = undefined,
            .general_allocator = undefined,
            .guest_mem = undefined,
            .serial = undefined,
            .ps2 = undefined,
            .pci = undefined,
            .device_manager = undefined,
            .tty = undefined,
        };
    }

    /// Setup a VM
    pub fn init(self: *@This(), option: VMOption) !void {
        self.page_allocator = option.page_allocator;
        self.general_allocator = option.general_allocator;

        // Initialize a VM
        self.kvm_fd = try kvm.system.open_kvm_fd();
        try self.check_compatiblity();
        self.vm_fd = try kvm.system.create_vm(self.kvm_fd);

        //// Setup TSS
        try self.setup_tss();

        //// Setup identity map
        try self.setup_identity_map();

        // Setup interrupt controller
        try self.init_pic_model();

        // Setup PIT
        try self.init_pit();

        // Allocate guest physical memory
        const user_mem = try kvm.vm.set_user_memory_region(
            self.vm_fd,
            option.mem_size_bytes,
            option.page_allocator,
        );

        std.debug.assert(option.mem_size_bytes == user_mem.len);
        self.guest_mem = user_mem;

        // Create vCPUs
        // TODO: num of vCPUs should be configurable
        var vcpus = try self.general_allocator.alloc(VCPU, 1);
        vcpus[0] = try VCPU.new(self.kvm_fd, self.vm_fd, 0);
        self.vcpus = vcpus;

        // Set CPUID
        try self.init_cpuid();

        // Init protected mode
        try self.init_protected_mode();

        // Init serial console
        self.serial = pio.srl.SerialUart8250.new(self.vm_fd);

        // Init PS/2 controller
        self.ps2 = pio.ps2.Ps2Controller.new();

        // Init PCI
        self.pci = try pci.Pci.new(self.general_allocator);
        try self.pci.add_device(.{ .virtio_net = virtio.VirtioNet{} });

        // Init device manager
        self.device_manager = pio.PioDeviceManager.new(self.general_allocator);
        try self.device_manager.add_device(.{
            .addr_start = pio.srl.SerialUart8250.PORTS.COM1,
            .addr_end = pio.srl.SerialUart8250.PORTS.COM1 + 8,
            .interface = .{ .serial = &self.serial },
        });
        try self.device_manager.add_device(.{
            .addr_start = pio.ps2.Ps2Controller.PIO_START,
            .addr_end = pio.ps2.Ps2Controller.PIO_END,
            .interface = .{ .ps2 = &self.ps2 },
        });
        try self.device_manager.add_device(.{
            .addr_start = 0,
            .addr_end = 0xFFFF, // Map all available I/O ports and delegates all requests to PCI
            .interface = .{ .pci = &self.pci },
        });
    }

    /// Clear all segment registers of all vCPUs
    /// TODO: conflicting with `init_protected_mode`. Remove this?
    pub fn clear_segment_registers(self: *@This()) !void {
        if (self.vcpus.len == 0) {
            return VMError.NotReady;
        }

        for (self.vcpus) |vcpu| {
            var sregs = try kvm.vcpu.get_sregs(vcpu.vcpu_fd);
            sregs.cs.selector = 0;
            sregs.cs.base = 0;
            sregs.ss.selector = 0;
            sregs.ss.base = 0;
            sregs.ds.selector = 0;
            sregs.ds.base = 0;
            sregs.es.selector = 0;
            sregs.es.base = 0;
            sregs.fs.selector = 0;
            sregs.fs.base = 0;
            sregs.gs.selector = 0;
            sregs.gs.base = 0;
        }
    }

    /// Get segment registers of given vCPU
    pub fn get_sregs(self: *@This(), cpuid: usize) !kvm.KvmSregs {
        return try kvm.vcpu.get_sregs(self.vcpus[cpuid].vcpu_fd);
    }

    /// Set segment registers of given vCPU
    pub fn set_sregs(self: *@This(), cpuid: usize, sregs: kvm.KvmSregs) !void {
        try kvm.vcpu.set_sregs(self.vcpus[cpuid].vcpu_fd, sregs);
    }

    /// Get registers of given vCPU
    pub fn get_regs(self: *@This(), cpuid: usize) !kvm.KvmRegs {
        return try kvm.vcpu.get_regs(self.vcpus[cpuid].vcpu_fd);
    }

    /// Set registers of given vCPU
    pub fn set_regs(self: *@This(), cpuid: usize, regs: kvm.KvmRegs) !void {
        try kvm.vcpu.set_regs(self.vcpus[cpuid].vcpu_fd, regs);
    }

    /// Load an image to the guest physical memory
    fn load_image(self: *@This(), image: []u8, addr: usize) !void {
        if (self.guest_mem.len < addr + image.len) {
            return VMError.GMemNotEnough;
        }

        @memcpy(self.guest_mem[addr .. addr + image.len], image);
    }

    /// Run the VM until it exits once.
    /// TODO: for now, this function assumes that there is only one vCPU.
    pub fn run_single(self: *@This()) !void {
        var vcpu = self.vcpus[0];
        try kvm.vcpu.run(vcpu.vcpu_fd);
    }

    /// Enter the main loop of the VM.
    /// TODO: for now, this function assumes that there is only one vCPU.
    pub fn run_loop(self: *@This()) !void {
        // set up TTY
        self.tty = try terminal.Tty.new();
        try self.tty.set_raw_mode();
        defer self.tty.deinit();

        // start input loop
        const loop_hdr = try std.Thread.spawn(
            .{},
            terminal.Tty.loop_input,
            .{ &self.tty, &self.serial },
        );
        loop_hdr.detach();

        // enter main loop
        var vcpu = self.vcpus[0];
        const map = vcpu.kvm_run;

        while (true) {
            try self.run_single();

            switch (map.exit_reason) {
                0x61 => { // NMI
                    if (map.uni.io.direction == consts.kvm.KVM_EXIT_IO_IN) {
                        var bytes = map.as_bytes();
                        bytes[map.uni.io.data_offset] = 0x20;
                    }
                },
                consts.kvm.KVM_EXIT_IO => {
                    const port = map.uni.io.port;
                    const size = map.uni.io.size;
                    const offset = map.uni.io.data_offset;
                    var bytes = map.as_bytes()[offset .. offset + size];
                    if (map.uni.io.direction == consts.kvm.KVM_EXIT_IO_OUT) {
                        try self.device_manager.out(port, bytes);
                    } else {
                        try self.device_manager.in(port, bytes);
                    }
                },
                consts.kvm.KVM_EXIT_SHUTDOWN => {
                    std.log.info("VM shutdown", .{});
                    return;
                },
                consts.kvm.KVM_EXIT_HLT => {
                    std.log.info("VM halted", .{});
                    return;
                },
                else => {
                    std.log.err("Unknown exit reason: {d}", .{map.exit_reason});
                    return;
                },
            }
        }
    }

    /// Check if the KVM API is compatible
    fn check_compatiblity(self: *@This()) !void {
        const api_version = try kvm.system.get_api_version(self.kvm_fd);
        if (api_version != 12) {
            return VMError.ApiIncompatible;
        }
    }

    /// Register 3 pages of TSS (task state segmet) right after the guest physical memory.
    /// The region is hidden from VM itself,
    /// but needed for the guest to emulate real-mode.
    /// ref: https://lwn.net/Articles/658511/
    fn setup_tss(self: *@This()) !void {
        // The region must within the first 4GB.
        // We assume that the guest physical memory is less than 4GB - 4 pages.
        if (self.guest_mem.len >= 0x1_0000_0000 - consts.x64.PAGE_SIZE * 4) {
            return VMError.GMemNotEnough;
        }

        // TODO: add to layout consts
        try kvm.vm.set_tss_addr(self.vm_fd, self.guest_mem.len);
    }

    /// Register 1 page of identity map right after TSS.
    /// The region is hidden from VM itself.
    /// This function must be called before any vCPU is created.
    fn setup_identity_map(self: *@This()) !void {
        // The region must within the first 4GB.
        // We assume that the guest physical memory is less than 4GB - 4 pages.
        if (self.guest_mem.len >= 0x1_0000_0000 - consts.x64.PAGE_SIZE * 4) {
            return VMError.GMemNotEnough;
        }

        // This function must be called before any vCPU is created.
        if (self.vcpus.len != 0) {
            return VMError.NotReady;
        }

        try kvm.vm.set_identity_map_addr(
            self.vm_fd,
            // TODO: add to layout consts
            self.guest_mem.len + consts.x64.PAGE_SIZE * 3,
        );
    }

    /// Create an interrupt controller model
    /// (I/O APIC for external interrupts, local vPIC for internal interrupts).
    /// It is necessary for future vCPUs to have a local APIC.
    /// This function must be called before any vCPU is created.
    fn init_pic_model(self: *@This()) !void {
        if (self.vcpus.len != 0) {
            return VMError.NotReady;
        }

        try kvm.vm.create_irqchip(self.vm_fd);
    }

    /// Create i8254 PIT (programmable interval timer).
    /// This function must be called after IRQ chip is created.
    fn init_pit(self: *@This()) !void {
        try kvm.vm.create_pit2(self.vm_fd);
    }

    /// Switch all vCPUs to protected mode by setting segment registers.
    /// All segment registers are set to 0 with mxiimum limit (4KB granularity).
    fn init_protected_mode(self: *@This()) !void {
        for (self.vcpus) |vcpu| {
            var sregs = try kvm.vcpu.get_sregs(vcpu.vcpu_fd);

            // CS, DS, ES, FS, GS, SS
            sregs.cs.base = 0;
            sregs.cs.limit = std.math.maxInt(u32);
            sregs.cs.g = 1;
            sregs.ds.base = 0;
            sregs.ds.limit = std.math.maxInt(u32);
            sregs.ds.g = 1;
            sregs.es.base = 0;
            sregs.es.limit = std.math.maxInt(u32);
            sregs.es.g = 1;
            sregs.fs.base = 0;
            sregs.fs.limit = std.math.maxInt(u32);
            sregs.fs.g = 1;
            sregs.gs.base = 0;
            sregs.gs.limit = std.math.maxInt(u32);
            sregs.gs.g = 1;
            sregs.ss.base = 0;
            sregs.ss.limit = std.math.maxInt(u32);
            sregs.ss.g = 1;

            sregs.cs.db = 1; // 32-bit
            sregs.ss.db = 1; // 32-bit

            sregs.cr0 |= 1 << 0; // PE

            try kvm.vcpu.set_sregs(vcpu.vcpu_fd, sregs);
        }
    }

    /// Load a protected kernel image and cmdline to the guest physical memory.
    pub fn load_kernel_and_initrd(self: *@This(), kernel: []u8, initrd: []u8) !void {
        if (self.guest_mem.len < 1 * consts.units.GB) {
            return VMError.GMemNotEnough;
        }
        if (kernel.len > self.guest_mem.len - consts.layout.KERNEL_BASE) {
            return VMError.GMemNotEnough;
        }

        var boot_params = boot.BootParams.from_bytes(kernel);

        // setup necessary fields
        boot_params.hdr.type_of_loader = 0xFF;
        boot_params.hdr.ext_loader_ver = 0;
        boot_params.hdr.loadflags.LOADED_HIGH = true; // load kernel at 0x10_0000
        boot_params.hdr.loadflags.CAN_USE_HEAP = true; // use memory 0..BOOTPARAM as heap
        boot_params.hdr.heap_end_ptr = consts.layout.BOOTPARAM - 0x200;
        boot_params.hdr.loadflags.KEEP_SEGMENTS = true; // for 32-bit boot protocol
        boot_params.hdr.cmd_line_ptr = consts.layout.CMDLINE;
        boot_params.hdr.vid_mode = 0xFFFF; // VGA

        // setup E820 map
        boot_params.add_e820_entry(0, consts.layout.KERNEL_BASE, .RAM);
        boot_params.add_e820_entry(
            consts.layout.KERNEL_BASE,
            self.guest_mem.len - consts.layout.KERNEL_BASE,
            .RAM,
        );

        // load initrd
        try self.load_initrd(initrd, &boot_params);

        // setup cmdline
        const cmdline = self.guest_mem[consts.layout.CMDLINE .. consts.layout.CMDLINE + boot_params.hdr.cmdline_size];
        const cmdline_val = "console=ttyS0"; // TODO: make configurable
        @memset(cmdline, 0);
        @memcpy(cmdline[0..cmdline_val.len], cmdline_val);

        // copy boot_params
        try self.load_image(std.mem.asBytes(&boot_params), consts.layout.BOOTPARAM);

        // load protected-mode kernel code
        const code_offset = boot_params.hdr.get_protected_code_offset();
        const code_size = kernel.len - code_offset;
        try self.load_image(
            kernel[code_offset .. code_offset + code_size],
            consts.layout.KERNEL_BASE,
        );

        // set registers
        var regs = try self.get_regs(0); // TODO: which vCPU?
        regs.rflags = 0x2;
        regs.rip = consts.layout.KERNEL_BASE;
        regs.rsi = consts.layout.BOOTPARAM;
        try self.set_regs(0, regs);
    }

    /// Load initrd to the guest physical memory.
    fn load_initrd(
        self: *@This(),
        initrd: []u8,
        boot_params: *boot.BootParams,
    ) !void {
        if (self.guest_mem.len - consts.layout.INITRD < initrd.len) {
            // initrd is larger than reserved space
            return VMError.GMemNotEnough;
        }
        if (boot_params.hdr.initrd_addr_max < consts.layout.INITRD + initrd.len) {
            // initrd's loaded addr exceeds the limit of the specified addr
            return VMError.GMemNotEnough; // TODO: appropriate error
        }

        if (initrd.len == 0) {
            boot_params.hdr.ramdisk_image = 0;
            boot_params.hdr.ramdisk_size = 0;
        } else {
            boot_params.hdr.ramdisk_image = consts.layout.INITRD;
            boot_params.hdr.ramdisk_size = @truncate(initrd.len);
            try self.load_image(initrd, consts.layout.INITRD);
        }
    }

    /// Initialize CPUID.
    /// This function set the response of CPUID_SIGNATURE to the KVM signature.
    /// ZVM passthroughs the host CPU to the guest except for some features.
    fn init_cpuid(self: *@This()) !void {
        var cpuid = try kvm.system.get_supported_cpuid(self.kvm_fd);
        const f = cid.functions;

        var set = false;
        for (0..cpuid.nent) |i| {
            var entry = &cpuid.entries[i];
            switch (entry.function) {
                f.KVM_CPUID_SIGNATURE => {
                    entry.eax = consts.kvm.KVM_CPUID_FEATURES;
                    // This ID is defined by Linux. We cannot choose arbitrary value.
                    entry.ebx = 0x4B4D564B; // "KVMK"
                    entry.ecx = 0x564B4D56; // "VMKV"
                    entry.edx = 0x0000004D; // "M\x00\x00\x00"
                    set = true;
                },
                f.FEATURE_INFORMATION => {
                    // `hypervisor` is available in latest chipsets.
                    // Linux kernel seems to check this flag
                    // to determine if it initializes uncore.
                    // We declare that the guest is running on a hypervisor
                    // to avoid unnecessary uncore initialization.
                    var flags_ecx: cid.CpuidFeatureFlagEcx = @bitCast(entry.ecx);
                    var flags_edx: cid.CpuidFeatureFlagEdx = @bitCast(entry.edx);

                    flags_ecx.hypervisor = true;

                    entry.ecx = @bitCast(flags_ecx);
                    entry.edx = @bitCast(flags_edx);
                },
                f.STRUCTURE_EXTENDED_FEATURE_FLAGS => {
                    // HACK
                    // This is a dirty workaround for a Intel FSRM alternative instructions.
                    // This oneline code disables the alternative instructions.
                    // Refer to [/hacks/FSRM.md] for more details.
                    entry.edx &= ~(@as(u32, 1) << 4); // X86_FEATURE_FSRM
                },
                else => {},
            }
        }
        if (!set) {
            return VMError.NotReady;
        }

        for (self.vcpus) |*vcpu| {
            try kvm.vcpu.set_cpuid(vcpu.vcpu_fd, &cpuid);
        }
    }

    /// Print a stacktrace.
    /// This function is for debugging purpose.
    /// XXX: not implemented
    pub fn print_stacktrace(self: *@This()) !void {
        // TODO: multi-core support
        const regs = try self.get_regs(0);
        const FALLBACK_KBASE = 0xFFFFFFFF80000000; // TODO: KASLR support
        const mem = self.guest_mem;

        var rsp: u64 = regs.rsp;
        var rbp: u64 = regs.rbp;
        var rip: u64 = regs.rip;
        var i: usize = 0;
        while (true) : (i += 1) {
            if (rbp % 8 != 0 or rsp % 8 != 0) {
                std.log.err(
                    "Invalid RSP or RBP alignment: RSP=0x{X:0>16} RBP=0x{X:0>16}",
                    .{ rsp, rbp },
                );
                std.log.err("Stacktrace aborted.", .{});
                return;
            }

            std.debug.print("#{d:0>3}: ", .{i});
            std.debug.print("0x{X:0>16} ", .{rip});
            const b = try self.translate_with_fallback(rbp, FALLBACK_KBASE);
            rsp = rbp + 0x10;
            rip = @as(*u64, @ptrCast(@alignCast(mem[b + 8 .. b + 0x10].ptr))).*;
            rbp = @as(*u64, @ptrCast(@alignCast(mem[b + 0 .. b + 8].ptr))).*;
            std.os.exit(0); // XXX
        }
    }

    /// Translate guest virtual address to guest physical address.
    /// If the translation fails, it uses the given fallback base address.
    fn translate_with_fallback(self: *@This(), guest_virt: u64, fallback_base: u64) !u64 {
        return kvm.vcpu.translate(self.vcpus[0].vcpu_fd, guest_virt) catch {
            return guest_virt - fallback_base;
        };
    }

    /// Deinitialize the VM and corresponding vCPUs.
    /// Caller must defer this function after initializing the VM.
    pub fn deinit(self: *@This()) void {
        // deinit vCPUs
        for (self.vcpus) |vcpu| {
            vcpu.deinit() catch unreachable;
        }
        self.general_allocator.free(self.vcpus);

        // deinit devices
        self.device_manager.deinit();

        // deinit PCI
        self.pci.deinit();

        // TODO: other deinitializations
    }
};

/// Instance of a vCPU
pub const VCPU = struct {
    /// File descriptor for the vCPU
    vcpu_fd: kvm.vcpu_fd_t,
    /// Sharad memory mapping vCPU state
    kvm_run: *kvm.KvmRun,
    /// Size of run state
    kvm_run_size: usize,

    /// Instantiate a new vCPU
    pub fn new(kvm_fd: kvm.kvm_fd_t, vm_fd: kvm.vm_fd_t, id: usize) !@This() {
        // Create a vCPU
        const vcpu_fd = try kvm.vm.create_vcpu(vm_fd, id);

        // Get run state of the vCPU
        const map_size = try kvm.system.get_vcpu_mmap_size(kvm_fd);
        const map = try kvm.vcpu.get_vcpu_run_state(vcpu_fd, map_size);

        return .{
            .vcpu_fd = vcpu_fd,
            .kvm_run = map,
            .kvm_run_size = map_size,
        };
    }

    pub fn deinit(self: @This()) !void {
        _ = linux.munmap(@ptrCast(self.kvm_run), self.kvm_run_size);
        // TODO: close vCPU fd?
    }
};

// =================================== //

const expect = std.testing.expect;

test "Run simple assembly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // instantiate VM
    var vm = try VM.new();
    defer _ = vm.deinit();

    // initialize VM
    try vm.init(.{
        .page_allocator = std.heap.page_allocator,
        .general_allocator = gpa.allocator(),
        .mem_size_bytes = consts.x64.PAGE_SIZE * 0x10,
    });
    try vm.clear_segment_registers();

    // load simple image
    // the binary just `out` to port 0x10 with the loop counter
    const image_file = try std.fs.cwd().openFile(
        "test/assets/simple-bin",
        .{ .mode = .read_only },
    );
    const image_stat = try image_file.stat();
    const buf = try gpa.allocator().alloc(u8, image_stat.size);
    _ = try image_file.readAll(buf);
    try vm.load_image(buf, 0);
    gpa.allocator().free(buf);

    // set registers just for paranoia checks
    var regs = kvm.KvmRegs.new_empty();
    regs.rip = 0;
    regs.rflags = 0x2; // always set 1st bit to 1
    try vm.set_regs(0, regs);

    // test
    var count: u32 = 0;
    while (count < 3) {
        try vm.run_single();
        const map = vm.vcpus[0].kvm_run;

        switch (map.exit_reason) {
            consts.kvm.KVM_EXIT_IO => {
                try expect(map.uni.io.port == 0x10);
                const map_u8: [*]u8 = @ptrCast(map);
                const data_p: *u32 = @alignCast(
                    @ptrCast(&map_u8[map.uni.io.data_offset]),
                );
                try expect(data_p.* == count);
                count += 1;
            },
            else => {
                unreachable;
            },
        }
    }
}

test "Load dummy kernel & Set CPUID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // instantiate VM
    var vm = try VM.new();
    defer _ = vm.deinit();

    // initialize VM
    try vm.init(.{
        .page_allocator = std.heap.page_allocator,
        .general_allocator = allocator,
        .mem_size_bytes = 1 * consts.units.GB,
    });

    // read kernel image
    const file = try std.fs.cwd().openFile(
        "test/assets/bzImage",
        .{ .mode = .read_only },
    );
    const buf = try allocator.alloc(u8, (try file.stat()).size);
    defer allocator.free(buf);
    _ = try file.readAll(buf);

    // load kernel image
    try vm.load_kernel_and_initrd(buf, &.{});

    // check if cmdline is set correctly
    const cmdline = vm.guest_mem[consts.layout.CMDLINE .. consts.layout.CMDLINE + 0x100];
    const p_cmdline = std.mem.span(@as([*:0]u8, @ptrCast(cmdline.ptr)));
    try expect(std.mem.eql(u8, p_cmdline, "console=ttyS0"));

    // check if CPUID is set correctly
    const cpuid = try kvm.vcpu.get_cpuid(vm.vcpus[0].vcpu_fd);
    var found = false;
    for (0..cpuid.nent) |i| {
        var entry = &cpuid.entries[i];
        switch (entry.function) {
            consts.kvm.KVM_CPUID_SIGNATURE => {
                try expect(entry.eax == consts.kvm.KVM_CPUID_FEATURES);
                try expect(entry.ebx == 0x4B4D564B);
                try expect(entry.ecx == 0x564B4D56);
                try expect(entry.edx == 0x0000004D);
                found = true;
            },
            else => {},
        }
    }
    try expect(found);
}
