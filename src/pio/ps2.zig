//! PS/2 Controller mimicing Intel 8042.
//! See https://wiki.osdev.org/%228042%22_PS/2_Controller for more information.
//! This is just a mock of the controller and does nothing.
//! To register PS/2 controller properly,
//! we have to enable PnP (Plug and Play) ACPI and indicate the presence of the controller.

const std = @import("std");

/// PS/2 Controller.
/// I/O Ports:
///  - 0x60: Data Port
///  - 0x64: Status Register for R / Command Register for W
pub const Ps2Controller = struct {
    /// Status register.
    status: StatusRegister = .{},
    /// Configuration byte.
    cbyte: ConfigurationByte = .{},
    /// Data
    data: u8 = 0,

    pub const PIO_START: u8 = 0x60;
    pub const PIO_END: u8 = 0x64;

    const StatusRegister = packed struct(u8) {
        /// True if output buffer is full advising the system to read from.
        /// Must be set before reading from 0x60.
        output_buffer_status: bool = true,
        /// True if input buffer is full allowing the system to write next data.
        /// Must be clear before writing to 0x60 and 0x64.
        input_buffer_status: bool = false,
        /// Must be clear on reset.
        /// Must be set if the system passes the POST (self-tests).
        system_flag: bool = false,
        /// True if written data to input buffer is a command for the controller.
        /// False if written data to input buffer is a data.
        command_data: bool = false,
        /// Chipset specific.
        _unknown1: bool = false,
        /// Chipset specific.
        _unknown2: bool = false,
        /// True on timeout error.
        timeout_error: bool = false,
        /// True on parity error.
        parity_error: bool = false,
    };

    const ConfigurationByte = packed struct(u8) {
        first_interrupt: bool = false,
        second_interrupt: bool = false,
        /// True if the system passes the POST.
        system_flag: bool = true,
        /// Must be set to false.
        _reserved1: bool = false,
        first_clock: bool = false,
        second_clock: bool = false,
        translation: bool = false,
        /// Must be set to false.
        _reserved2: bool = false,
    };

    pub fn new() @This() {
        return .{};
    }

    pub fn in(self: *@This(), port: u16, data: []u8) !void {
        switch (port) {
            0x60 => { // data port
                data[0] = self.data;
            },
            0x64 => { // status register
                data[0] = @bitCast(self.status);
            },
            else => {},
        }
    }

    pub fn out(self: *@This(), port: u16, data: []u8) !void {
        switch (port) {
            0x60 => { // data port
                self.data = data[0];
            },
            0x64 => { // command register
                self.handle_command(data[0]);
            },
            else => {},
        }
    }

    fn handle_command(self: *@This(), command: u8) void {
        switch (command) {
            0x20 => { // Read "byte 0" from internal RAM
                self.data = @bitCast(self.cbyte);
            },
            else => unreachable,
        }
    }
};
