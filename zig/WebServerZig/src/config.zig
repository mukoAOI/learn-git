//! JSON 配置：端口、站点根目录、日志、连接池与空闲超时等。

const std = @import("std");

pub const PoolMode = enum {
    /// 启动时按 max_connections 分配接收缓冲（单块 slab），常驻内存稳定。
    fixed,
    /// 槽位按需分配接收缓冲，连接关闭后释放缓冲，可把内存还给分配器。
    dynamic,
};

pub const ServerOptions = struct {
    pool_mode: PoolMode,
    max_connections: usize,
    /// 仅 dynamic：启动时预先为前 N 个槽分配缓冲，减少首次连接时的分配。
    initial_connections: usize,
    recv_buffer_size: usize,
    /// 0 表示不启用空闲断开。
    idle_timeout_seconds: u64,
};

const Json = struct {
    port: ?u16 = null,
    document_root: ?[]const u8 = null,
    log_directory: ?[]const u8 = null,
    log_file_name: ?[]const u8 = null,
    log_to_stderr: ?bool = null,
    connection_pool: ?[]const u8 = null,
    max_connections: ?u32 = null,
    initial_connections: ?u32 = null,
    recv_buffer_size: ?u32 = null,
    idle_timeout_seconds: ?u32 = null,
};

pub const Config = struct {
    port: u16,
    document_root: []u8,
    log_directory: []u8,
    log_file_name: []u8,
    log_to_stderr: bool,
    pool_mode: PoolMode,
    max_connections: usize,
    initial_connections: usize,
    recv_buffer_size: usize,
    idle_timeout_seconds: u64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.document_root);
        self.allocator.free(self.log_directory);
        self.allocator.free(self.log_file_name);
    }

    pub fn serverOptions(self: Config) ServerOptions {
        return .{
            .pool_mode = self.pool_mode,
            .max_connections = self.max_connections,
            .initial_connections = self.initial_connections,
            .recv_buffer_size = self.recv_buffer_size,
            .idle_timeout_seconds = self.idle_timeout_seconds,
        };
    }
};

fn parsePoolMode(s: []const u8) !PoolMode {
    if (std.ascii.eqlIgnoreCase(s, "fixed")) return .fixed;
    if (std.ascii.eqlIgnoreCase(s, "dynamic")) return .dynamic;
    return error.InvalidConnectionPool;
}

fn defaults(alloc: std.mem.Allocator) !Config {
    return .{
        .port = 8080,
        .document_root = try alloc.dupe(u8, "."),
        .log_directory = try alloc.dupe(u8, "logs"),
        .log_file_name = try alloc.dupe(u8, "webserver.log"),
        .log_to_stderr = true,
        .pool_mode = .fixed,
        .max_connections = 256,
        .initial_connections = 0,
        .recv_buffer_size = 65536,
        .idle_timeout_seconds = 300,
        .allocator = alloc,
    };
}

/// 从 `path` 读取 JSON。`file_required == false` 且文件不存在时用内置默认；为 true 则返回 `error.FileNotFound`。
pub fn loadPath(alloc: std.mem.Allocator, path: []const u8, file_required: bool) !Config {
    const data = std.fs.cwd().readFileAlloc(alloc, path, 256 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            if (file_required) return err;
            return defaults(alloc);
        },
        else => |e| return e,
    };
    defer alloc.free(data);

    var parsed = try std.json.parseFromSlice(Json, alloc, data, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const j = parsed.value;

    const doc = try alloc.dupe(u8, j.document_root orelse ".");
    errdefer alloc.free(doc);
    const ldir = try alloc.dupe(u8, j.log_directory orelse "logs");
    errdefer alloc.free(ldir);
    const lname = try alloc.dupe(u8, j.log_file_name orelse "webserver.log");
    errdefer alloc.free(lname);

    const pool_mode: PoolMode = if (j.connection_pool) |s|
        try parsePoolMode(s)
    else
        .fixed;

    var max_c: u32 = j.max_connections orelse 256;
    if (max_c < 1) max_c = 1;
    if (max_c > 65535) max_c = 65535;

    var init_c: u32 = j.initial_connections orelse 0;
    if (init_c > max_c) init_c = max_c;

    var recv_sz: u32 = j.recv_buffer_size orelse 65536;
    if (recv_sz < 4096) recv_sz = 4096;
    if (recv_sz > 1024 * 1024) recv_sz = 1024 * 1024;

    const idle_s: u64 = j.idle_timeout_seconds orelse 300;

    return .{
        .port = j.port orelse 8080,
        .document_root = doc,
        .log_directory = ldir,
        .log_file_name = lname,
        .log_to_stderr = j.log_to_stderr orelse true,
        .pool_mode = pool_mode,
        .max_connections = max_c,
        .initial_connections = init_c,
        .recv_buffer_size = recv_sz,
        .idle_timeout_seconds = idle_s,
        .allocator = alloc,
    };
}
