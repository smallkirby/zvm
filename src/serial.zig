//! This module provides the serial 8250 UART device emulation.

const std = @import("std");

/// Serial 8250 UART.
/// This UART does not provide any FIFO buffers.
/// ref: https://en.wikibooks.org/wiki/Serial_Programming/8250_UART_Programming
pub const SerialUart8250 = struct {
    /// Port I/O addresses.
    const PORTS = struct {
        pub const COM1 = 0x3F8;
        pub const COM2 = 0x2F8;
        pub const COM3 = 0x3E8;
        pub const COM4 = 0x2E8;
    };
    const DIVISOR_LATCH_NUMERATOR = 115200;
    const DEFAULT_BAUD_RATE = 9600;

    regs: Regs,

    /// UART registers
    const Regs = struct {
        /// Transmitter Holding Buffer
        thr: u8 = 0,
        /// Receiver Buffer
        rbr: u8 = 0,
        /// Divisor Latch
        dl: u16 = @intCast(DIVISOR_LATCH_NUMERATOR / DEFAULT_BAUD_RATE),
        /// Interrupt Enable Register
        ier: u8 = 0,
        /// Line Control Register
        lcr: LineControlRegister = LineControlRegister{},
        /// Line Status Register
        lsr: LineStatusRegister = LineStatusRegister{},

        const LineControlRegister = packed struct(u8) {
            /// Word Length Select
            wl: u2 = 0,
            /// Stop Bit Select
            sb: u1 = 0,
            /// Parity Select
            parity: u3 = 0,
            /// Set Break Enable
            sbe: bool = false,
            /// Divisor Latch Access Bit
            dlab: bool = false,
        };

        const LineStatusRegister = packed struct(u8) {
            /// Data Ready
            dr: bool = false,
            /// Overrun Error
            oe: bool = false,
            /// Parity Error
            pe: bool = false,
            /// Framing Error
            fe: bool = false,
            /// Break Interrupt
            bi: bool = false,
            /// Transmitter Holding Register Empty
            thre: bool = true,
            /// Data Holding Register Empty
            dhre: bool = true, // TODO: correct?
            /// FIFO Error
            fifo_err: bool = false,
        };
    };

    fn dlab(self: *@This()) bool {
        return self.regs.lcr.dlab;
    }

    /// Create a new serial UART device.
    pub fn new() @This() {
        return @This(){
            .regs = Regs{},
        };
    }

    /// Handle PIO read event.
    pub fn in(self: *@This(), port: u16, data: []u8) !void {
        // TODO: only COM1 is supported for now.
        std.debug.assert(PORTS.COM1 <= port and port < PORTS.COM1 + 8);

        const com1_port = port - PORTS.COM1;
        switch (com1_port) {
            0 => if (!self.dlab()) { // RBR
                data[0] = self.regs.rbr; // TODO: read input from terminal
            } else { // DLL
                data[0] = @intCast(self.regs.dl & 0xFF);
            },
            1 => if (!self.dlab()) { // IER
                // TODO: unimplemented
            } else { // DLH
                data[0] = @intCast(self.regs.dl >> 8);
            },
            2 => { // IIR
                // TODO: unimplemented
            },
            3 => { // LCR
                data[0] = @bitCast(self.regs.lcr);
            },
            4 => { // MCR
                // TODO: unimplemented
            },
            5 => { // LSR
                data[0] = @bitCast(self.regs.lsr);
            },
            6 => { // MSR
                // TODO: unimplemented
            },
            7 => { // SR
                // TODO: unimplemented
            },
            else => {
                unreachable;
            },
        }
    }

    /// Handle PIO write event.
    pub fn out(self: *@This(), port: u16, data: []u8) !void {
        // TODO: only COM1 is supported for now.
        std.debug.assert(PORTS.COM1 <= port and port < PORTS.COM1 + 8);

        const com1_port = port - PORTS.COM1;
        switch (com1_port) {
            0 => if (!self.dlab()) { // RBR
                std.debug.print("{s}", .{data});
                self.regs.thr = data[0];
            } else { // DLL
                self.regs.dl = (self.regs.dl & 0xFF00) | data[0];
            },
            1 => if (!self.dlab()) { // IER
                // TODO: unimplemented
            } else { // DLH
                self.regs.dl = (self.regs.dl & 0x00FF) | (@as(u16, data[0]) << 8);
            },
            2 => { // FCR
                // we don't support FIFO.
            },
            3 => { // LCR
                self.regs.lcr = @bitCast(data[0]);
            },
            4 => { // MCR
                // TODO: unimplemented
            },
            5, 6 => { // LSR, MSR (read only)
                unreachable;
            },
            7 => { // SR
                // TODO: unimplemented
            },
            else => {
                unreachable;
            },
        }
    }
};

// =================================== //

const expect = std.testing.expect;

test "LCR repr" {
    try expect(@bitSizeOf(SerialUart8250.Regs.LineControlRegister) == 8);

    var lcr = SerialUart8250.Regs.LineControlRegister{};
    lcr.wl = 0b00;
    lcr.sb = 0b1;
    lcr.parity = 0b110;
    lcr.sbe = false;
    lcr.dlab = true;
    try expect(@as(u8, @bitCast(lcr)) == 0b1011_0100);
}

test "LSR repr" {
    try expect(@bitSizeOf(SerialUart8250.Regs.LineStatusRegister) == 8);

    var lsr = SerialUart8250.Regs.LineStatusRegister{};
    lsr.dr = true;
    lsr.oe = true;
    lsr.pe = false;
    lsr.fe = true;
    lsr.bi = true;
    lsr.thre = false;
    lsr.dhre = false;
    lsr.fifo_err = true;
    try expect(@as(u8, @bitCast(lsr)) == 0b1001_1011);
}

test "UART I/O" {
    var uart = SerialUart8250.new();
    var data = [_]u8{0} ** 0x30;
    const com = SerialUart8250.PORTS.COM1;

    // RBR
    data[0] = 0xFF;
    try uart.in(com + 0, data[0..1]);
    try expect(data[0] == 0);
    clear_data(&data);

    // THR
    // TODO: this OUR shows `std.debug.print` output in the test.
    data[0] = 0xFF;
    try uart.out(com + 0, data[0..1]);
    try expect(uart.regs.thr == 0xFF);
    clear_data(&data);

    // DLL / DLH
    data[0] = 0x12;
    data[1] = 0x34;
    uart.regs.lcr.dlab = true;
    try uart.out(com + 0, data[0..1]);
    try uart.out(com + 1, data[1..2]);
    uart.regs.lcr.dlab = false;
    try expect(uart.regs.dl == 0x3412);
    clear_data(&data);

    // IER
    // unimplemented

    // LCR
    data[0] = 0b1011_0100;
    try uart.out(com + 3, data[0..1]);
    try expect(uart.regs.lcr.wl == 0b00);
    try expect(uart.regs.lcr.sb == 0b1);
    try expect(uart.regs.lcr.parity == 0b110);
    try expect(uart.regs.lcr.sbe == false);
    try expect(uart.regs.lcr.dlab == true);
    clear_data(&data);
    try uart.in(com + 3, data[0..1]);
    try expect(data[0] == 0b1011_0100);
    clear_data(&data);

    // LSR
    try uart.in(com + 5, data[0..1]);
    try expect(uart.regs.lsr.dr == false);
    try expect(uart.regs.lsr.oe == false);
    try expect(uart.regs.lsr.pe == false);
    try expect(uart.regs.lsr.fe == false);
    try expect(uart.regs.lsr.bi == false);
    try expect(uart.regs.lsr.thre == true);
    try expect(uart.regs.lsr.dhre == true);
    try expect(uart.regs.lsr.fifo_err == false);
    clear_data(&data);
}

fn clear_data(data: []u8) void {
    for (data) |*d| {
        d.* = 0;
    }
}
