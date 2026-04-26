//! Terminal width and TTY detection (Windows + POSIX), Zig 0.16 `std.Io` APIs.

const std = @import("std");
const builtin = @import("builtin");

pub fn isStdoutTty(io: std.Io) bool {
    return std.Io.File.stdout().isTty(io) catch false;
}

pub fn terminalColumns(io: std.Io, max_fallback: u16) u16 {
    const file = std.Io.File.stdout();
    if (builtin.os.tag == .windows) {
        var get_console_info = std.os.windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
        switch (get_console_info.operate(io, file)) {
            .SUCCESS => {
                const w = get_console_info.Data.dwWindowSize.X;
                if (w > 0) return @intCast(@min(w, max_fallback));
            },
            else => {},
        }
    } else {
        var winsize: std.posix.winsize = .{
            .row = 0,
            .col = 0,
            .xpixel = 0,
            .ypixel = 0,
        };
        const op = io.operate(.{ .device_io_control = .{
            .file = file,
            .code = std.posix.T.IOCGWINSZ,
            .arg = &winsize,
        } }) catch return max_fallback;
        if (op.device_io_control >= 0 and winsize.col > 0) {
            return @min(winsize.col, max_fallback);
        }
    }
    return max_fallback;
}
