const std = @import("std");
const kvm = @import("kvm.zig");
const zvm = @import("zvm.zig");
const serial = @import("serial.zig");
const consts = @import("consts.zig");
const clap = @import("clap");
const c = @cImport({
    @cInclude("linux/kvm.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // build cmdline arguments
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-k, --kernel <str>     Kenel bzImage path.
        \\-i, --initrd <str>     initramfs or initrd path.
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // parse cmdline arguments
    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // instantiate VM
    var vm = try zvm.VM.new();
    defer _ = vm.deinit();

    // initialize VM
    try vm.init(.{
        .page_allocator = std.heap.page_allocator,
        .general_allocator = allocator,
        .mem_size_bytes = 1 * consts.units.GB,
    });

    // read kernel image
    const file_kernel = if (res.args.kernel) |bzimage_path| blk: {
        break :blk std.fs.cwd().openFile(
            bzimage_path,
            .{ .mode = .read_only },
        ) catch |err| {
            std.log.err("Failed to open bzImage: {s}", .{bzimage_path});
            std.log.err("{}", .{err});
            std.os.exit(9);
        };
    } else {
        std.log.err("No bzImage specified. Use --kernel option.", .{});
        std.os.exit(9);
    };
    const buf_kernel = try allocator.alloc(u8, (try file_kernel.stat()).size);
    defer allocator.free(buf_kernel);
    _ = try file_kernel.readAll(buf_kernel);

    // read initrd
    // TODO: modulize these loads
    const file_initrd = if (res.args.initrd) |initrd_path| blk: {
        break :blk std.fs.cwd().openFile(
            initrd_path,
            .{ .mode = .read_only },
        ) catch |err| {
            std.log.err("Failed to open initrd: {s}", .{initrd_path});
            std.log.err("{}", .{err});
            std.os.exit(9);
        };
    } else blk: {
        std.log.info("No initrd specified. Booting without initrd.", .{});
        break :blk null;
    };
    var buf_initrd: []u8 = &.{};
    if (file_initrd) |f| {
        buf_initrd = try allocator.alloc(u8, (try f.stat()).size);
        _ = try f.readAll(buf_initrd);
    }
    defer allocator.free(buf_initrd);

    // load kernel and initrd image
    try vm.load_kernel_and_initrd(buf_kernel, buf_initrd);

    // initialize UART
    // TODO: hide inside VM
    var uart = serial.SerialUart8250.new();

    // start a loop
    while (true) {
        try vm.run();
        const run = vm.vcpus[0].kvm_run;

        switch (run.exit_reason) {
            c.KVM_EXIT_IO => {
                const port = run.uni.io.port;
                switch (port) {
                    0x61 => { // NMI
                        if (run.uni.io.direction == c.KVM_EXIT_IO_IN) {
                            var bytes = run.as_bytes();
                            bytes[run.uni.io.data_offset] = 0x20;
                        }
                    },
                    else => {
                        // TODO: modulize
                        if (serial.SerialUart8250.PORTS.COM1 <= port and port < serial.SerialUart8250.PORTS.COM1 + 8) {
                            const size = run.uni.io.size;
                            const offset = run.uni.io.data_offset;
                            var bytes = run.as_bytes()[offset .. offset + size];
                            if (run.uni.io.direction == c.KVM_EXIT_IO_OUT) {
                                try uart.out(port, bytes);
                            } else {
                                try uart.in(port, bytes);
                            }
                        }
                    },
                }
            },
            c.KVM_EXIT_SHUTDOWN => {
                std.log.warn("SHUTDOWN\n", .{});

                const regs = try vm.get_regs(0);
                regs.debug_print();
                try vm.print_stacktrace();

                break;
            },
            c.KVM_EXIT_HLT => {
                std.log.warn("HLT\n", .{});

                const regs = try vm.get_regs(0);
                regs.debug_print();
                try vm.print_stacktrace();

                break;
            },
            else => {
                std.log.warn("EXIT_REASON: {}\n", .{run.exit_reason});
                std.os.exit(99);
            },
        }
    }
}
