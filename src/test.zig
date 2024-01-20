comptime {
    _ = @import("kvm.zig");

    @import("std").testing.refAllDecls(@This());
}
