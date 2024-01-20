//! This module provides a collection of KVM API bindings.

const std = @import("std");
const os = std.os;
const linux = os.linux;
const c = @cImport({
    @cInclude("linux/kvm.h");
    @cInclude("fcntl.h");
});

const fd_t = linux.fd_t;

pub const KvmError = error{
    IoctlFailed,
};

/// KVM system API which qery and set global attributes of the whole KVM subsystem.
pub const system = struct {
    pub const kvm_fd_t = fd_t;

    /// Get a handle to the KVM subsystem.
    pub fn open_kvm_fd() !kvm_fd_t {
        const file = std.fs.openFileAbsolute("/dev/kvm", .{}) catch |err| return err;
        return file.handle;
    }

    /// Get the API version.
    /// The return value must be 12.
    pub fn get_api_version(fd: kvm_fd_t) !usize {
        const ret = linux.ioctl(fd, c.KVM_GET_API_VERSION, 0);
        if (ret == -1) {
            return error.KvmError.IoctlFailed;
        } else {
            return ret;
        }
    }
};

// =================================== //

const expect = std.testing.expect;

test "KVM_GET_API_VERSION" {
    const fd = try open_kvm_fd();
    defer _ = linux.close(fd);

    const api_version = try system.get_api_version(fd);
    try expect(api_version == 12);
}
