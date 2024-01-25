comptime {
    _ = @import("kvm.zig");
    _ = @import("zvm.zig");
    _ = @import("consts.zig");
    _ = @import("boot.zig");

    _ = @import("util.zig");

    @import("std").testing.refAllDecls(@This());
}
