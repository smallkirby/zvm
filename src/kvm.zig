//! This module provides a collection of KVM API bindings.

const std = @import("std");
const os = std.os;
const linux = os.linux;
const c = @cImport({
    @cInclude("linux/kvm.h");
    @cInclude("fcntl.h");
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
    present: u8,
    dpl: u8,
    db: u8,
    s: u8,
    l: u8,
    g: u8,
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
};

/// KVM VM API which query and set attributes affecting an entire virtual machine.
pub const vm = struct {
    const KvmUserspaceMemoryRegion = packed struct {
        slot: u32,
        flags: u32,
        guest_phys_addr: u64,
        memory_size: u64,
        userspace_addr: u64,

        pub fn new(size: usize, addr: u64) @This() {
            return .{
                .slot = 0,
                .flags = 0,
                .guest_phys_addr = 0,
                .memory_size = @intCast(size),
                .userspace_addr = addr,
            };
        }
    };

    /// Set a memory region for the virtual machine allocationg specified size of memory.
    /// NOTE: should take an allocator?
    pub fn set_user_memory_region(fd: vm_fd_t, size: usize) !void {
        const mem = linux.mmap(
            null,
            size,
            os.PROT.READ | os.PROT.WRITE,
            os.MAP.PRIVATE | os.MAP.ANONYMOUS | os.MAP.NORESERVE,
            -1,
            0,
        );
        if (mem == -1) {
            return error.KvmError.NoMemory;
        }

        const region = KvmUserspaceMemoryRegion.new(size, mem);
        const ret = ioctl(
            fd,
            c.KVM_SET_USER_MEMORY_REGION,
            @intFromPtr(&region),
        );

        if (ret < 0) {
            return KvmError.IoctlFailed;
        } else {
            return;
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

    try vm.set_user_memory_region(vm_fd, 4096);
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
