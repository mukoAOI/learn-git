const std = @import("std");
const proactor = @import("proactor.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var port: ?u16 = null;
    var root: ?[]const u8 = null;
    var config_path: ?[]const u8 = null;
    var config_required = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if ((std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--config")) and i + 1 < args.len) {
            i += 1;
            config_path = args[i];
            config_required = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            i += 1;
            port = try std.fmt.parseUnsigned(u16, args[i], 10);
            continue;
        }
        if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            i += 1;
            root = args[i];
            continue;
        }
    }

    const cfg_path = config_path orelse "config.json";
    var cfg = try config.loadPath(alloc, cfg_path, config_required);
    defer cfg.deinit();

    if (port) |p| cfg.port = p;
    if (root) |r| {
        cfg.allocator.free(cfg.document_root);
        cfg.document_root = try cfg.allocator.dupe(u8, r);
    }

    var log = try logger.Logger.init(alloc, cfg.log_directory, cfg.log_file_name, cfg.log_to_stderr);
    defer log.deinit();
    log.setGlobal();
    defer logger.clearGlobal();

    log.info("WebServer-Zig 启动，监听 :{d}，站点根目录 \"{s}\"，日志目录 \"{s}/{s}\"，连接池 {s} max={d} recv={d} idle={d}s", .{
        cfg.port,
        cfg.document_root,
        cfg.log_directory,
        cfg.log_file_name,
        @tagName(cfg.pool_mode),
        cfg.max_connections,
        cfg.recv_buffer_size,
        cfg.idle_timeout_seconds,
    });

    try proactor.run(alloc, cfg.port, cfg.document_root, cfg.serverOptions());
}
