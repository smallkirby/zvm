//! This module provides a main feature of VMM

const std = @import("std");
const kvm = @import("kvm.zig");
const consts = @import("consts.zig");
const builtin = @import("builtin");
const linux = std.os.linux;
const c = @cImport({
    @cInclude("linux/kvm.h");
});

pub const VMError = error{
    /// VM or vCPU is not ready for the operations
    NotReady,
    /// KVM API is not compatible
    ApiIncompatible,
    /// Guest physical memory is not enough
    GMemNotEnough,
};

/// Instance of a VMM
const VM = struct {
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
            .vcpus = undefined,
            .page_allocator = undefined,
            .general_allocator = undefined,
            .guest_mem = undefined,
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

        // Allocate guest physical memory
        const user_mem = try kvm.vm.set_user_memory_region(
            self.vm_fd,
            option.mem_size_bytes,
            option.page_allocator,
        );
        self.guest_mem = user_mem;

        // Setup TSS
        try self.setup_tss();

        // Setup identity map
        try self.setup_identity_map();

        // Setup interrupt controller
        try self.init_pic_model();

        // Setup PIT
        try self.init_pit();

        // Create vCPUs
        // TODO: num of vCPUs should be configurable
        var vcpus = try self.general_allocator.alloc(VCPU, 1);
        vcpus[0] = try VCPU.new(self.kvm_fd, self.vm_fd, 0);
        self.vcpus = vcpus;

        // Init protected mode
        try self.init_protected_mode();
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
            try kvm.vcpu.set_sregs(vcpu.vcpu_fd, sregs);
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
    pub fn load_image(self: *@This(), image: []u8, addr: usize) !void {
        if (self.guest_mem.len < addr + image.len) {
            return VMError.GMemNotEnough;
        }

        @memcpy(self.guest_mem[addr .. addr + image.len], image);
    }

    /// Run the VM.
    /// TODO: for now, this function assumes that there is only one vCPU.
    pub fn run(self: *@This()) !void {
        var vcpu = self.vcpus[0];
        try kvm.vcpu.run(vcpu.vcpu_fd);
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

    /// Deinitialize the VM and corresponding vCPUs.
    /// Caller must defer this function after initializing the VM.
    pub fn deinit(self: @This()) void {
        for (self.vcpus) |vcpu| {
            vcpu.deinit() catch unreachable;
        }

        self.general_allocator.free(self.vcpus);
        // TODO: other deinitializations
    }
};

/// Instance of a vCPU
const VCPU = struct {
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
        try vm.run();
        const map = vm.vcpus[0].kvm_run;

        switch (map.exit_reason) {
            c.KVM_EXIT_IO => {
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
