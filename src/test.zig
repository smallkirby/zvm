comptime {
    _ = @import("kvm.zig");
    _ = @import("zvm.zig");
    _ = @import("consts.zig");
    _ = @import("boot.zig");
    _ = @import("terminal.zig");

    _ = @import("pio.zig");
    _ = @import("pio/serial.zig");

    _ = @import("util.zig");

    @import("std").testing.refAllDecls(@This());
}
