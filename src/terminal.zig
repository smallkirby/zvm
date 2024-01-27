//! This module provides a TTY utility.

const std = @import("std");
const fs = std.fs;
const os = std.os;
const linux = os.linux;

/// TTY wrapper.
pub const Tty = struct {
    /// File descriptor of TTY.
    tty: fs.File,
    /// Original termios settings.
    original_termios: os.termios,
    /// Current termios settings.
    termios: os.termios,

    /// Initialize a new TTY.
    pub fn new() !@This() {
        const tty = try fs.cwd().openFile(
            "/dev/tty",
            .{ .mode = .read_write },
        );
        const original_termios = try os.tcgetattr(tty.handle);

        return @This(){
            .tty = tty,
            .original_termios = original_termios,
            .termios = original_termios,
        };
    }

    /// Set TTY to raw mode.
    /// Caller must call `deinit` to restore original settings.
    pub fn set_raw_mode(self: *@This()) !void {
        var termios = self.termios;

        termios.lflag &= ~@as(
            os.system.tcflag_t,
            linux.ECHO // Stop terminal from showing input.
            | linux.ICANON // Disable canonical mode and read byte-by-byte.
            | linux.IEXTEN, // Disable Ctrl-V.
            // NOTE: We don't disable Ctrl-C and Ctrl-Z.
            // It is desirable that we can still kill ZVM in raw mode.
        );
        termios.iflag &= ~@as(
            os.system.tcflag_t,
            linux.IXON // Disable Ctrl-S and Ctrl-Q.
            | linux.ICRNL // Disable Ctrl-Mi and Ctrl-M.
            | linux.BRKINT // Disable converting break to SIGINT.
            | linux.INPCK // Disable parity checking.
            | linux.ISTRIP, // Disable stripping 8th bit.
        );
        termios.cflag |= linux.CS8; // Set character size to 8 bits.

        termios.cc[linux.V.TIME] = 0; // Timeout in deciseconds for read.
        termios.cc[linux.V.MIN] = 0; // Minimum number of bytes to read.

        try os.tcsetattr(
            self.tty.handle,
            .FLUSH,
            termios,
        );
    }

    /// Loop over waiting keyboard inputs.
    pub fn loop_input(self: *@This(), notifier: anytype) !void {
        var buf: [0x100]u8 = undefined;
        var remaining: usize = 0;

        while (true) {
            remaining = try self.tty.read(&buf);
            while (remaining > 0) {
                remaining -= try notifier.input(buf[0]);
                std.time.sleep(1000);
            }
            std.time.sleep(1000);
        }
    }

    /// Deinitialize a TTY.
    pub fn deinit(self: @This()) void {
        _ = os.tcsetattr(
            self.tty.handle,
            .FLUSH,
            self.original_termios,
        ) catch {};
        _ = self.tty.close();
    }
};

// =================================== //

test "Raw TTY" {
    var tty = try Tty.new();
    defer tty.deinit();
    try tty.set_raw_mode();
}
