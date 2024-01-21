const std = @import("std");
const kvm = @import("kvm.zig");

pub fn main() !void {
    const fd = try kvm.system.open_kvm_fd();
    const vm_fd = try kvm.system.create_vm(fd);
    const vcpu_fd = try kvm.vm.create_vcpu(vm_fd, 0);

    const sregs = try kvm.vcpu.get_sregs(vcpu_fd);
    std.debug.print("{?}\n", .{sregs});
}
