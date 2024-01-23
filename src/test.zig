comptime {
    _ = @import("kvm.zig");
    _ = @import("vm.zig");
    _ = @import("consts.zig");
    _ = @import("boot.zig");

    @import("std").testing.refAllDecls(@This());
}
