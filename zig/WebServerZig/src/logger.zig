//! 文件日志（指定目录）+ 可选 stderr；供连接日志等调用。

const std = @import("std");

var global: ?*Logger = null;

pub const Logger = struct {
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    file: std.fs.File,
    also_stderr: bool,

    pub fn init(alloc: std.mem.Allocator, log_dir: []const u8, log_file: []const u8, also_stderr: bool) !Logger {
        try std.fs.cwd().makePath(log_dir);
        const path = try std.fs.path.join(alloc, &.{ log_dir, log_file });
        defer alloc.free(path);
        var f = try std.fs.cwd().createFile(path, .{ .truncate = false });
        errdefer f.close();
        try f.seekFromEnd(0);
        return .{
            .alloc = alloc,
            .mutex = .{},
            .file = f,
            .also_stderr = also_stderr,
        };
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }

    pub fn setGlobal(self: *Logger) void {
        global = self;
    }

    fn writeLine(self: *Logger, level: []const u8, comptime fmt: []const u8, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ts = std.time.timestamp();
        const body = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        defer self.alloc.free(body);
        const line = std.fmt.allocPrint(self.alloc, "[{d}] [{s}] {s}\n", .{ ts, level, body }) catch return;
        defer self.alloc.free(line);

        self.file.writeAll(line) catch return;
        if (self.also_stderr) {
            std.fs.File.stderr().writeAll(line) catch {};
        }
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.writeLine("INFO", fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.writeLine("WARN", fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.writeLine("ERROR", fmt, args);
    }
};

pub fn clearGlobal() void {
    global = null;
}

/// 连接建立（在 setGlobal 之后调用）。
pub fn peerConnected(addr_text: []const u8) void {
    if (global) |g| {
        g.info("新连接 {s}", .{addr_text});
    } else {
        std.debug.print("新连接 {s}\n", .{addr_text});
    }
}
