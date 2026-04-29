//! 跨平台 Proactor：Linux 使用 io_uring 完成队列，Windows 使用 IOCP。

const std = @import("std");
const builtin = @import("builtin");
const ServerOptions = @import("config.zig").ServerOptions;

pub fn run(alloc: std.mem.Allocator, port: u16, root: []const u8, opts: ServerOptions) !void {
    switch (builtin.os.tag) {
        .linux => return @import("proactor_linux.zig").run(alloc, port, root, opts),
        .windows => return @import("proactor_windows.zig").run(alloc, port, root, opts),
        else => @compileError("Proactor 仅支持 Linux (io_uring) 与 Windows (IOCP)"),
    }
}
