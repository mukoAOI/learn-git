//! HTTP/1.x：静态文件、视频 MIME、Range 分段（供浏览器 `<video>` 拖动与流式播放）。

const std = @import("std");
const builtin = @import("builtin");

/// Windows 上 `File.pread` 通过带 offset 的 `ReadFile`+OVERLAPPED 实现，要求句柄以
/// `FILE_FLAG_OVERLAPPED` 打开；`Dir.openFile` 得到的是同步句柄，会触发 GetLastError(998)。
/// Linux 等仍用真正的 pread。单连接顺序读同一文件句柄，seek+read 安全。
pub fn readFileAtAll(file: std.fs.File, buffer: []u8, offset: u64) !usize {
    if (builtin.os.tag == .windows) {
        try file.seekTo(offset);
        return try file.readAll(buffer);
    }
    return try file.preadAll(buffer, offset);
}

/// 小响应整包分配的上限；更大则走分块发送。
pub const max_simple = 512 * 1024;
/// 单次读文件并发送的最大字节数（含首包正文）。
pub const stream_chunk = 1024 * 1024;

pub const Prepared = union(enum) {
    simple: []u8,
    stream: struct {
        file: std.fs.File,
        first_buf: []u8,
        /// 下次从文件中读取的字节偏移（已发送正文末尾的下一个字节）。
        next: u64,
        /// 本次请求在文件中的结束偏移（不包含）。
        end: u64,
        chunk_buf: []u8,
    },
};

/// Extract path from "GET /path HTTP/1.x" style buffer (headers may be partial).
pub fn parseGetPath(req: []const u8) ?[]const u8 {
    if (req.len < 5) return null;
    if (!std.mem.startsWith(u8, req, "GET ")) return null;
    const rest = req[4..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    if (space == 0) return null;
    return rest[0..space];
}

pub fn hasFullHttpHead(buf: []const u8) bool {
    return std.mem.indexOf(u8, buf, "\r\n\r\n") != null;
}

pub fn pathSafe(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] != '/') return false;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, "..")) return false;
    }
    return true;
}

fn headerSection(req: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return req;
    return req[0..end];
}

fn headerRangeValue(headers: []const u8) ?[]const u8 {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.ascii.eqlIgnoreCase(name, "Range")) continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

/// 解析 `Range: bytes=...`，返回文件内 [start, end)（左闭右开）。无 Range 时返回 null。
fn parseBytesRange(range_value: []const u8, file_size: u64) ?struct { start: u64, end: u64 } {
    const prefix = "bytes=";
    if (!std.mem.startsWith(u8, range_value, prefix)) return null;
    const spec = range_value[prefix.len..];
    const comma = std.mem.indexOfScalar(u8, spec, ',');
    const first = if (comma) |c| spec[0..c] else spec;
    if (first.len == 0) return null;

    if (std.mem.startsWith(u8, first, "-")) {
        const suffix_len = std.fmt.parseUnsigned(u64, first[1..], 10) catch return null;
        if (suffix_len == 0 or file_size == 0) return null;
        const s = file_size -| suffix_len;
        return .{ .start = s, .end = file_size };
    }

    const dash = std.mem.indexOfScalar(u8, first, '-') orelse return null;
    const start_s = first[0..dash];
    const end_s = first[dash + 1 ..];

    const start = if (start_s.len == 0) 0 else std.fmt.parseUnsigned(u64, start_s, 10) catch return null;

    const end: u64 = blk: {
        if (end_s.len == 0) {
            break :blk file_size;
        }
        break :blk (std.fmt.parseUnsigned(u64, end_s, 10) catch return null) + 1;
    };

    return .{ .start = start, .end = end };
}

pub fn prepareGet(
    alloc: std.mem.Allocator,
    doc_root: std.fs.Dir,
    url_path: []const u8,
    request: []const u8,
) !Prepared {
    if (!pathSafe(url_path)) {
        return .{ .simple = try allocPrintHttp(alloc, 400, "text/plain", "Bad Request") };
    }
    var rel = url_path[1..];
    while (rel.len > 0 and rel[rel.len - 1] == '/') {
        rel = rel[0 .. rel.len - 1];
    }
    if (rel.len == 0) rel = "index.html";

    const needs_dir_redirect = url_path.len > 1 and url_path[url_path.len - 1] != '/';

    var file_owned: ?std.fs.File = null;
    errdefer if (file_owned) |f| f.close();

    var mime: []const u8 = undefined;

    if (doc_root.openFile(rel, .{})) |f| {
        file_owned = f;
        mime = guessMime(rel);
    } else |err| switch (err) {
        error.IsDir => {
            if (needs_dir_redirect) {
                const loc = try std.fmt.allocPrint(alloc, "{s}/", .{url_path});
                defer alloc.free(loc);
                return .{ .simple = try allocPrintHttpRedirect(alloc, loc) };
            }
            const idx = try std.fmt.allocPrint(alloc, "{s}/index.html", .{rel});
            defer alloc.free(idx);
            file_owned = try doc_root.openFile(idx, .{});
            mime = guessMime(idx);
        },
        error.FileNotFound => {
            const idx = try std.fmt.allocPrint(alloc, "{s}/index.html", .{rel});
            defer alloc.free(idx);
            file_owned = doc_root.openFile(idx, .{}) catch |e2| switch (e2) {
                error.FileNotFound => return .{ .simple = try allocPrintHttp(alloc, 404, "text/plain", "Not Found") },
                else => |e| return e,
            };
            mime = guessMime(idx);
        },
        else => |e| return e,
    }

    const size = try file_owned.?.getEndPos();
    const hdrs = headerSection(request);

    const range_val = headerRangeValue(hdrs);
    var start: u64 = 0;
    var end: u64 = size;
    var partial = false;

    if (range_val) |rv| {
        if (parseBytesRange(rv, size)) |r| {
            if (r.start >= size or r.end > size or r.start >= r.end) {
                if (file_owned) |f| f.close();
                file_owned = null;
                return .{ .simple = try rangeNotSatisfiable(alloc, size) };
            }
            start = r.start;
            end = r.end;
            partial = true;
        }
    }

    const seg_len = end - start;
    if (seg_len == 0) {
        if (file_owned) |f| f.close();
        file_owned = null;
        return .{ .simple = try allocPrintHttp(alloc, 400, "text/plain", "Empty range") };
    }

    // 小文件整段一次读完
    if (seg_len <= max_simple) {
        const body = try alloc.alloc(u8, seg_len);
        errdefer alloc.free(body);
        _ = try readFileAtAll(file_owned.?, body, start);
        if (file_owned) |f| f.close();
        file_owned = null;

        const header = if (partial)
            try std.fmt.allocPrint(
                alloc,
                "HTTP/1.1 206 Partial Content\r\nAccept-Ranges: bytes\r\nContent-Type: {s}\r\nContent-Range: bytes {d}-{d}/{d}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                .{ mime, start, end - 1, size, seg_len },
            )
        else
            try std.fmt.allocPrint(
                alloc,
                "HTTP/1.1 200 OK\r\nAccept-Ranges: bytes\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                .{ mime, seg_len },
            );
        defer alloc.free(header);

        const out = try alloc.alloc(u8, header.len + body.len);
        @memcpy(out[0..header.len], header);
        @memcpy(out[header.len..], body);
        alloc.free(body);
        return .{ .simple = out };
    }

    // 大文件分块
    const first_body = @min(stream_chunk, seg_len);
    const header_s = if (partial)
        try std.fmt.allocPrint(
            alloc,
            "HTTP/1.1 206 Partial Content\r\nAccept-Ranges: bytes\r\nContent-Type: {s}\r\nContent-Range: bytes {d}-{d}/{d}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ mime, start, end - 1, size, seg_len },
        )
    else
        try std.fmt.allocPrint(
            alloc,
            "HTTP/1.1 200 OK\r\nAccept-Ranges: bytes\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ mime, seg_len },
        );
    defer alloc.free(header_s);

    const first_buf = try alloc.alloc(u8, header_s.len + first_body);
    errdefer alloc.free(first_buf);
    @memcpy(first_buf[0..header_s.len], header_s);
    _ = try readFileAtAll(file_owned.?, first_buf[header_s.len..], start);

    const chunk_buf = try alloc.alloc(u8, stream_chunk);
    errdefer alloc.free(chunk_buf);

    const next = start + first_body;

    const f = file_owned.?;
    file_owned = null;
    return .{
        .stream = .{
            .file = f,
            .first_buf = first_buf,
            .next = next,
            .end = end,
            .chunk_buf = chunk_buf,
        },
    };
}

fn rangeNotSatisfiable(alloc: std.mem.Allocator, size: u64) ![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */{d}\r\nContent-Type: text/plain\r\nContent-Length: 15\r\nConnection: close\r\n\r\nRange Not Valid",
        .{size},
    );
}

pub fn errorResponse(alloc: std.mem.Allocator, status: u16, msg: []const u8) ![]u8 {
    return allocPrintHttp(alloc, status, "text/plain", msg);
}

fn allocPrintHttp(alloc: std.mem.Allocator, status: u16, ctype: []const u8, msg: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
        .{ status, statusText(status), ctype, msg.len, msg },
    );
}

/// 目录 URL 无尾斜杠时重定向到带 `/` 的 URL，便于浏览器解析相对路径（如子目录静态站发布）。
fn allocPrintHttpRedirect(alloc: std.mem.Allocator, location: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "HTTP/1.1 301 Moved Permanently\r\nLocation: {s}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        .{location},
    );
}

fn statusText(s: u16) []const u8 {
    return switch (s) {
        400 => "Bad Request",
        404 => "Not Found",
        413 => "Payload Too Large",
        else => "Error",
    };
}

pub fn guessMime(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return "application/octet-stream";
    const exts = [_][]const u8{
        ".html", ".htm", ".css",  ".js",    ".png",  ".jpg",  ".jpeg", ".gif",
        ".svg",  ".ico",  ".txt", ".json", ".mp4",   ".webm", ".ogv",  ".ogg",  ".mov",
        ".m4v",  ".mkv", ".avi",  ".mpeg",  ".mpg",
    };
    const mimes = [_][]const u8{
        "text/html", "text/html", "text/css", "application/javascript",
        "image/png", "image/jpeg", "image/jpeg", "image/gif",
        "image/svg+xml", "image/x-icon", "text/plain", "application/json",
        "video/mp4", "video/webm", "video/ogg", "video/ogg",
        "video/quicktime", "video/x-m4v", "video/x-matroska", "video/x-msvideo",
        "video/mpeg", "video/mpeg",
    };
    for (exts, mimes) |e, m| {
        if (std.ascii.eqlIgnoreCase(ext, e)) return m;
    }
    return "application/octet-stream";
}
