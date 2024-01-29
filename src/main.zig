const std = @import("std");
const kvm = @import("kvm.zig");
const zvm = @import("zvm.zig");
const util = @import("util.zig");
const consts = @import("consts.zig");
const clap = @import("clap");
const Chameleon = @import("chameleon").Chameleon;

pub const std_options = struct {
    pub const log_level = .info; // Edit here to chnage log level
    pub const logFn = logFunc;
};

pub fn logFunc(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    comptime var cham = Chameleon.init(.Auto);
    const ch_debug = comptime cham.bgMagenta().bold();
    const ch_info = comptime cham.bgGreen().bold();
    const ch_warn = comptime cham.bgYellow().bold();
    const ch_err = comptime cham.bgRed().bold();
    const prefix = "[" ++ comptime level.asText() ++ "]";

    const ch = comptime switch (level) {
        .debug => ch_debug,
        .info => ch_info,
        .warn => ch_warn,
        .err => ch_err,
    };

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(ch.fmt(prefix) ++ " " ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // build cmdline arguments
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-k, --kernel <str>     Kenel bzImage path.
        \\-i, --initrd <str>     initramfs or initrd path.
        \\-m, --memory <str>     Memory size. (eg. 100MB, 1G, 2000B)
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
    var mem_size: usize = undefined;
    if (res.args.memory) |mem_size_str| {
        mem_size = util.convert_mem_unit(mem_size_str) catch {
            std.log.err("Failed to parse memory size: {s}", .{mem_size_str});
            std.os.exit(1);
        };
    } else {
        std.log.info("No memory size specified. Using 1GB as default.", .{});
        mem_size = 1 * consts.units.GB;
    }

    // instantiate VM
    var vm = try zvm.VM.new();
    defer _ = vm.deinit();

    // initialize VM
    try vm.init(.{
        .page_allocator = std.heap.page_allocator,
        .general_allocator = allocator,
        .mem_size_bytes = mem_size,
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

    // start a loop
    try vm.run_loop();
}
