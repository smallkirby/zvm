const std = @import("std");
const kvm = @import("kvm.zig");
const zvm = @import("zvm.zig");
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
        \\-n, --kernel <str>     An option parameter, which takes a value.
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
    if (res.args.kernel == null) {
        std.log.err("No bzImage specified. Use --kernel option.\n", .{});
        std.os.exit(9);
    }
    const bzimage = res.args.kernel.?;

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
    const file = std.fs.cwd().openFile(
        bzimage,
        .{ .mode = .read_only },
    ) catch |err| {
        std.log.err("Failed to open bzImage: {s}", .{bzimage});
        std.log.err("{}", .{err});
        std.os.exit(9);
    };
    const buf = try allocator.alloc(u8, (try file.stat()).size);
    defer allocator.free(buf);
    _ = try file.readAll(buf);

    // load kernel image
    try vm.load_kernel_and_initrd(buf, &.{});

    // start a loop
    while (true) {
        try vm.run();
        const run = vm.vcpus[0].kvm_run;

        switch (run.exit_reason) {
            c.KVM_EXIT_IO => {
                // TODO: define constants for ports num
                switch (run.uni.io.port) {
                    0x61 => { // NMI
                        if (run.uni.io.direction == c.KVM_EXIT_IO_IN) {
                            var bytes = run.as_bytes();
                            bytes[run.uni.io.data_offset] = 0x20;
                        }
                    },
                    0x3F8 => { // VGA
                        if (run.uni.io.direction == c.KVM_EXIT_IO_OUT) {
                            const size = run.uni.io.size;
                            const offset = run.uni.io.data_offset;
                            const bytes = run.as_bytes()[offset .. offset + size];
                            std.debug.print("{s}", .{bytes});
                        }
                    },
                    0x3F8 + 5 => { // TODO: doc
                        var bytes = run.as_bytes();
                        bytes[run.uni.io.data_offset] = 0x20;
                    },
                    else => {},
                }
            },
            c.KVM_EXIT_SHUTDOWN => {
                std.log.warn("SHUTDOWN\n", .{});

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
