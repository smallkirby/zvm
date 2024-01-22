comptime {
    _ = @import("kvm.zig");
    _ = @import("vm.zig");

    @import("std").testing.refAllDecls(@This());
}
