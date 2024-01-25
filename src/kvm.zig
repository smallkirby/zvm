//! This module provides a collection of KVM API bindings.

const std = @import("std");
const os = std.os;
const linux = os.linux;
const c = @cImport({
    @cInclude("linux/kvm.h");
    @cInclude("fcntl.h");
    @cInclude("errno.h");
});

const fd_t = linux.fd_t;
pub const kvm_fd_t = fd_t;
pub const vm_fd_t = fd_t;
pub const vcpu_fd_t = fd_t;

fn ioctl(fd: fd_t, request: u32, arg: u64) i32 {
    const ret = linux.ioctl(fd, request, arg);
    return @as(i32, @bitCast(@as(u32, @truncate(ret))));
}

pub const KvmError = error{
    IoctlFailed,
    NoMemory,
};

pub const KvmSegment = extern struct {
    base: u64,
    limit: u32,
    selector: u16,
    type: u8,
    /// Segment present
    present: u8,
    dpl: u8,
    /// Default operation size (0=16-bit seg, 1=32-bit seg)
    db: u8,
    /// Segment unusable (0=usable, 1=unusable)
    s: u8,
    /// 64-bit mode active (for CS only)
    l: u8,
    /// Granularity (0=byte gran, 1=page gran)
    g: u8,
    /// Available for system use
    avl: u8,
    _unusable: u8,
    _padding: u8,

    pub fn new() @This() {
        return .{
            .base = 0,
            .limit = 0,
            .selector = 0,
            .type = 0,
            .present = 0,
            .dpl = 0,
            .db = 0,
            .s = 0,
            .l = 0,
            .g = 0,
            .avl = 0,
            ._unusable = 0,
            ._padding = 0,
        };
    }
};

pub const KvmDtable = extern struct {
    base: u64,
    limit: u16,
    _padding: [3]u16,

    pub fn new() @This() {
        return .{
            .base = 0,
            .limit = 0,
            ._padding = [_]u16{0} ** 3,
        };
    }
};

pub const KvmSregs = extern struct {
    pub const BITMAP_SIZE = (c.KVM_NR_INTERRUPTS + 63) / 64;

    cs: KvmSegment,
    ds: KvmSegment,
    es: KvmSegment,
    fs: KvmSegment,
    gs: KvmSegment,
    ss: KvmSegment,
    tr: KvmSegment,
    ldt: KvmSegment,
    gdt: KvmDtable,
    idt: KvmDtable,
    cr0: u64,
    cr2: u64,
    cr3: u64,
    cr4: u64,
    cr8: u64,
    efer: u64,
    apic_base: u64,
    interrupt_bitmap: [BITMAP_SIZE]u64,

    pub fn new() @This() {
        return .{
            .cs = KvmSegment.new(),
            .ds = KvmSegment.new(),
            .es = KvmSegment.new(),
            .fs = KvmSegment.new(),
            .gs = KvmSegment.new(),
            .ss = KvmSegment.new(),
            .tr = KvmSegment.new(),
            .ldt = KvmSegment.new(),
            .gdt = KvmDtable.new(),
            .idt = KvmDtable.new(),
            .cr0 = 0,
            .cr2 = 0,
            .cr3 = 0,
            .cr4 = 0,
            .cr8 = 0,
            .efer = 0,
            .apic_base = 0,
            .interrupt_bitmap = [_]u64{0} ** BITMAP_SIZE,
        };
    }
};

pub const KvmRegs = extern struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rsp: u64,
    rbp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rip: u64,
    rflags: u64,

    pub fn new() @This() {
        return .{
            .rax = 0,
            .rbx = 0,
            .rcx = 0,
            .rdx = 0,
            .rsi = 0,
            .rdi = 0,
            .rsp = 0,
            .rbp = 0,
            .r8 = 0,
            .r9 = 0,
            .r10 = 0,
            .r11 = 0,
            .r12 = 0,
            .r13 = 0,
            .r14 = 0,
            .r15 = 0,
            .rip = 0,
            .rflags = 0,
        };
    }

    pub fn new_empty() @This() {
        return .{
            .rax = undefined,
            .rbx = undefined,
            .rcx = undefined,
            .rdx = undefined,
            .rsi = undefined,
            .rdi = undefined,
            .rsp = undefined,
            .rbp = undefined,
            .r8 = undefined,
            .r9 = undefined,
            .r10 = undefined,
            .r11 = undefined,
            .r12 = undefined,
            .r13 = undefined,
            .r14 = undefined,
            .r15 = undefined,
            .rip = undefined,
            .rflags = undefined,
        };
    }
};

pub const KvmRun = extern struct {
    request_interrupt_window: u8,
    immediate_exit: u8,
    _padding1: [6]u8,
    exit_reason: u32,
    ready_for_interrupt_injection: u8,
    if_flag: u8,
    flags: u16,
    cr8: u64,
    apic_base: u64,
    uni: extern union {
        io: extern struct {
            direction: u8,
            size: u8,
            port: u16,
            count: u32,
            data_offset: u64,
        },
    },

    /// Get a multi-item pointer to backed bytes of this type.
    /// Note that this cast discards the size information.
    /// NOTE: should take `size` argument return slice?
    pub fn as_bytes(self: *@This()) [*]u8 {
        const tmp = @as(
            *anyopaque,
            @ptrCast(std.mem.asBytes(self).ptr),
        );
        return @as([*]u8, @ptrCast(tmp));
    }
};

const KvmPitConfig = extern struct {
    /// The only valid value is 0x0 and 0x1.
    /// When set to 1, it emulates speaker port stub.
    flags: u32,
    channels: [15]u32,
};

const KvmCpuidEntry2 = extern struct {
    /// EAX value to obtain the entry.
    function: u32,
    /// ECX value to obtain the entry.
    index: u32,
    flags: u32,
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    padding: [3]u32,

    comptime {
        std.debug.assert(@bitOffsetOf(@This(), "index") == 32 * 1);
        std.debug.assert(@bitOffsetOf(@This(), "flags") == 32 * 2);
        std.debug.assert(@bitOffsetOf(@This(), "eax") == 32 * 3);
        std.debug.assert(@bitOffsetOf(@This(), "ebx") == 32 * 4);
    }

    pub fn new() @This() {
        return .{
            .function = 0,
            .index = 0,
            .flags = 0,
            .eax = 0,
            .ebx = 0,
            .ecx = 0,
            .edx = 0,
            .padding = [_]u8{0} ** 3,
        };
    }
};

pub const KvmCpuid = extern struct {
    /// Number of the entry
    nent: u32 align(1),
    padding: u32 align(1) = 0,
    entries: [NENTRIES]KvmCpuidEntry2 align(0x1),

    pub const NENTRIES = 0x50; // TODO: should adjust, or repeat until correct size for each host

    comptime {
        std.debug.assert(@bitOffsetOf(@This(), "padding") == 32);
        std.debug.assert(@bitOffsetOf(@This(), "entries") == 64);
    }

    pub fn new() @This() {
        return .{
            .nent = NENTRIES,
            .padding = 0,
            .entries = undefined,
        };
    }
};

/// KVM system API which qery and set global attributes of the whole KVM subsystem.
pub const system = struct {
    /// Get a handle to the KVM subsystem.
    pub fn open_kvm_fd() !kvm_fd_t {
        const file = std.fs.openFileAbsolute(
            "/dev/kvm",
            .{
                .mode = .read_write,
            },
        ) catch |err| return err;
        return file.handle;
    }

    /// Get the API version.
    /// The return value must be 12.
    pub fn get_api_version(fd: kvm_fd_t) !usize {
        const ret = ioctl(
            fd,
            c.KVM_GET_API_VERSION,
            0,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return @intCast(ret);
        }
    }

    /// Create a virtual machine.
    pub fn create_vm(fd: kvm_fd_t) !vm_fd_t {
        const ret = ioctl(
            fd,
            c.KVM_CREATE_VM,
            0,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return @intCast(ret);
        }
    }

    /// Get the size of the shared memory region through which we can access a vCPU's state.
    pub fn get_vcpu_mmap_size(fd: kvm_fd_t) !usize {
        const ret = ioctl(
            fd,
            c.KVM_GET_VCPU_MMAP_SIZE,
            0,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return @intCast(ret);
        }
    }

    /// Get x86 CPUID features supported by the host.
    /// It adjusts `nent` to the number of entries actually returned.
    pub fn get_supported_cpuid(fd: kvm_fd_t) !KvmCpuid {
        var cpuid = KvmCpuid.new();
        const ret = ioctl(
            fd,
            c.KVM_GET_SUPPORTED_CPUID,
            @intFromPtr(&cpuid),
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return cpuid;
        }
    }
};

/// KVM VM API which query and set attributes affecting an entire virtual machine.
pub const vm = struct {
    pub const KvmUserspaceMemoryRegion = packed struct {
        slot: u32,
        flags: u32,
        guest_phys_addr: u64,
        memory_size: u64,
        userspace_addr: u64,

        pub fn new(size: usize, addr: [*]u8) @This() {
            return .{
                .slot = 0,
                .flags = 0,
                .guest_phys_addr = 0,
                .memory_size = @intCast(size),
                .userspace_addr = @intFromPtr(addr),
            };
        }
    };

    /// Set a memory region for the virtual machine allocationg specified size of memory.
    /// NOTE: should take an allocator?
    pub fn set_user_memory_region(
        fd: vm_fd_t,
        size: usize,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const mem = try allocator.alloc(u8, size);
        @memset(mem, 0);
        const region = KvmUserspaceMemoryRegion.new(size, mem.ptr);
        const ret = ioctl(
            fd,
            c.KVM_SET_USER_MEMORY_REGION,
            @intFromPtr(&region),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return mem;
        }
    }

    /// Set TSS addr.
    pub fn set_tss_addr(fd: vm_fd_t, addr: u64) !void {
        const ret = ioctl(
            fd,
            c.KVM_SET_TSS_ADDR,
            addr,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Set identity map
    pub fn set_identity_map_addr(fd: vm_fd_t, addr: u64) !void {
        var v_addr = addr;
        const ret = ioctl(
            fd,
            c.KVM_SET_IDENTITY_MAP_ADDR,
            @intFromPtr(&v_addr),
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Create a vCPU with the specified ID.
    pub fn create_vcpu(fd: vm_fd_t, cpuid: usize) !vcpu_fd_t {
        const ret = ioctl(
            fd,
            c.KVM_CREATE_VCPU,
            // NOTE: should check recommended/mamimux vCPU count
            //  that can be retrieved by KVM_CHECK_EXTENSION.
            cpuid,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return @intCast(ret);
        }
    }

    /// Setup the interrupt controller.
    pub fn create_irqchip(fd: vm_fd_t) !void {
        const ret = ioctl(
            fd,
            c.KVM_CREATE_IRQCHIP,
            0,
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Init the PIT.
    pub fn create_pit2(fd: vm_fd_t) !void {
        var config = KvmPitConfig{
            .flags = 0,
            .channels = [_]u32{0} ** 15,
        };
        const ret = ioctl(
            fd,
            c.KVM_CREATE_PIT2,
            @intFromPtr(&config),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }
};

/// KVM vCPU API which query and set attributes of a single vCPU.
pub const vcpu = struct {
    /// Read special registers from the vCPU.
    pub fn get_sregs(fd: vcpu_fd_t) !KvmSregs {
        var sregs = KvmSregs.new();
        const ret = ioctl(
            fd,
            c.KVM_GET_SREGS,
            @intFromPtr(&sregs),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return sregs;
        } else {
            unreachable;
        }
    }

    /// Write special registers to the vCPU.
    pub fn set_sregs(fd: vcpu_fd_t, sregs: KvmSregs) !void {
        const ret = linux.ioctl(
            fd,
            c.KVM_SET_SREGS,
            @intFromPtr(&sregs),
        );
        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Read general registers from the vCPU.
    pub fn get_regs(fd: vcpu_fd_t) !KvmRegs {
        var regs = KvmRegs.new();
        const ret = ioctl(
            fd,
            c.KVM_GET_REGS,
            @intFromPtr(&regs),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return regs;
        } else {
            unreachable;
        }
    }

    /// Write general registers to the vCPU.
    pub fn set_regs(fd: vcpu_fd_t, regs: KvmRegs) !void {
        const ret = ioctl(
            fd,
            c.KVM_SET_REGS,
            @intFromPtr(&regs),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Run a vCPU.
    pub fn run(fd: vcpu_fd_t) !void {
        const ret = ioctl(
            fd,
            c.KVM_RUN,
            0,
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Get the pointer to the vCPU's state.
    /// Callee owns the returned pointer.
    pub fn get_vcpu_run_state(fd: vcpu_fd_t, map_size: usize) !*KvmRun {
        const addr = linux.mmap(
            null,
            map_size,
            os.PROT.READ | os.PROT.WRITE,
            os.MAP.SHARED,
            fd,
            0,
        );
        if (addr == std.math.maxInt(usize)) {
            return KvmError.NoMemory;
        }

        return @as(
            *KvmRun,
            @ptrFromInt(addr),
        );
    }

    /// Get CPUID of the vCPU.
    pub fn get_cpuid(fd: vcpu_fd_t) !KvmCpuid {
        var cpuid = KvmCpuid.new();
        const ret = ioctl(
            fd,
            c.KVM_GET_CPUID2,
            @intFromPtr(&cpuid),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return cpuid;
        } else {
            unreachable;
        }
    }

    /// Set the vCPU's CPUID, which is returned to the guest when it executes CPUID inst.
    pub fn set_cpuid(fd: vcpu_fd_t, cpuid: *KvmCpuid) !void {
        const ret = ioctl(
            fd,
            c.KVM_SET_CPUID2,
            @intFromPtr(cpuid),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            return;
        } else {
            unreachable;
        }
    }

    /// Translate a guest linear address to a guest physical address.
    pub fn translate(fd: vcpu_fd_t, addr: u64) !u64 {
        // TODO: define zig struct
        var t = c.kvm_translation{
            .linear_address = addr,
            .physical_address = 0,
            .valid = 0,
            .writeable = 0,
            .usermode = 0,
            .pad = [_]u8{0} ** 5,
        };
        const ret = ioctl(
            fd,
            c.KVM_TRANSLATE,
            @intFromPtr(&t),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else if (ret == 0) {
            if (t.valid == 0) {
                return KvmError.IoctlFailed;
            } else {
                return t.physical_address;
            }
        } else {
            unreachable;
        }
    }
};

// =================================== //

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "KVM_GET_API_VERSION" {
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const api_version = try system.get_api_version(fd);
    try expect(api_version == 12);
}

test "KVM_CREATE_VM" {
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const vm_fd = try system.create_vm(fd);
    defer _ = linux.close(vm_fd);

    try expect(vm_fd != -1);
}

test "KVM_SET_USER_MEMORY_REGION" {
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const vm_fd = try system.create_vm(fd);
    defer _ = linux.close(vm_fd);

    const allocator = std.heap.page_allocator;
    _ = try vm.set_user_memory_region(vm_fd, 4096, allocator);
}

test "KVM_CREATE_VCPU" {
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const vm_fd = try system.create_vm(fd);
    defer _ = linux.close(vm_fd);

    const vcpu_fd = try vm.create_vcpu(vm_fd, 0);
    defer _ = linux.close(vcpu_fd);

    try expect(vcpu_fd != -1);
}

test "KVM_{GET/SET}_SREGS" {
    // compatibility check
    try expectEqual(KvmSregs.BITMAP_SIZE, 4);
    try expectEqual(@sizeOf(KvmSegment), @sizeOf(c.kvm_segment));
    try expectEqual(@sizeOf(KvmSregs), @sizeOf(c.kvm_sregs));
    try expectEqual(@offsetOf(KvmSregs, "cs"), @offsetOf(c.kvm_sregs, "cs"));
    try expectEqual(@offsetOf(KvmSregs, "cr0"), @offsetOf(c.kvm_sregs, "cr0"));

    // normal test
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const vm_fd = try system.create_vm(fd);
    defer _ = linux.close(vm_fd);

    const vcpu_fd = try vm.create_vcpu(vm_fd, 0);
    defer _ = linux.close(vcpu_fd);

    var sregs = try vcpu.get_sregs(vcpu_fd);
    try expect(sregs.cr0 != 0);

    sregs.cr0 = 0xDEADBEEF;
    sregs.efer = 0xCAFEBABE;
    try vcpu.set_sregs(vcpu_fd, sregs);
    const new_sregs = try vcpu.get_sregs(vcpu_fd);

    try expect(new_sregs.cr0 == 0xDEADBEEF);
    try expect(new_sregs.efer == 0xCAFEBABE);
    try expect(new_sregs.cr2 == 0);
}

test "Get vCPU state" {
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    const vm_fd = try system.create_vm(fd);
    defer _ = linux.close(vm_fd);

    const vcpu_fd = try vm.create_vcpu(vm_fd, 0);
    defer _ = linux.close(vcpu_fd);

    const map_size = try system.get_vcpu_mmap_size(fd);
    const run = try vcpu.get_vcpu_run_state(vcpu_fd, map_size);
    defer _ = linux.munmap(@ptrCast(run), map_size);
}

test "GET_SUPPORTED_CPUID" {
    // compatibility check
    var cpuid = KvmCpuid.new();
    try expect(@intFromPtr(&cpuid.entries[0]) == @intFromPtr(&cpuid) + 0x8);
    try expect(@intFromPtr(&cpuid.entries[2]) == @intFromPtr(&cpuid.entries[1]) + 0x28);

    // normal test
    const fd = try system.open_kvm_fd();
    defer _ = linux.close(fd);

    cpuid = try system.get_supported_cpuid(fd);
    try expect(cpuid.nent > 0);
}
