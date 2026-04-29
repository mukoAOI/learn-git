//! Windows: IOCP + 重叠 WSARecv / WSASend；连接池 fixed/dynamic、空闲 shutdown 释放槽位与缓冲。

const std = @import("std");
const posix = std.posix;
const windows = std.os.windows;
const ws2_32 = windows.ws2_32;
const http = @import("http.zig");
const peer_log = @import("peer_log.zig");
const ServerOptions = @import("config.zig").ServerOptions;

const StreamState = struct {
    file: std.fs.File,
    next: u64,
    end: u64,
    chunk_buf: []u8,
};

const Conn = struct {
    socket: posix.socket_t = undefined,
    recv_ov: windows.OVERLAPPED = std.mem.zeroes(windows.OVERLAPPED),
    send_ov: windows.OVERLAPPED = std.mem.zeroes(windows.OVERLAPPED),
    buf: []u8 = &.{},
    buf_owned: bool = false,
    read_len: usize = 0,
    write_buf: ?[]u8 = null,
    write_buf_owned: bool = false,
    stream: ?StreamState = null,
    last_activity_ms: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
};

const Ctx = struct {
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    opts: ServerOptions,
    iocp: windows.HANDLE,
    listen_fd: posix.socket_t,
    conns: []Conn,
    used: []bool,
    doc_root: std.fs.Dir,
};

fn touchActivity(conn: *Conn) void {
    _ = conn.last_activity_ms.store(std.time.milliTimestamp(), .monotonic);
}

fn idleSweeper(ctx: *Ctx) void {
    const interval_ns = std.time.ns_per_s;
    while (true) {
        std.Thread.sleep(interval_ns);
        if (ctx.opts.idle_timeout_seconds == 0) continue;

        const now_ms = std.time.milliTimestamp();
        const timeout_ms: i64 = @intCast(ctx.opts.idle_timeout_seconds * std.time.ms_per_s);

        ctx.mutex.lock();
        var i: usize = 0;
        while (i < ctx.conns.len) : (i += 1) {
            if (!ctx.used[i]) continue;
            const conn = &ctx.conns[i];
            const last = conn.last_activity_ms.load(.monotonic);
            if (now_ms -| last > timeout_ms) {
                _ = posix.shutdown(conn.socket, .both) catch {};
            }
        }
        ctx.mutex.unlock();
    }
}

fn setupListen(port: u16) !posix.socket_t {
    var wsa_data: ws2_32.WSADATA = undefined;
    if (ws2_32.WSAStartup(0x0202, &wsa_data) != 0) return error.WsaStartupFailed;
    errdefer _ = ws2_32.WSACleanup();

    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    errdefer posix.close(sockfd);

    const yes: u32 = 1;
    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&yes));

    const addr = try std.net.Address.parseIp4("0.0.0.0", port);
    try posix.bind(sockfd, &addr.any, addr.getOsSockLen());
    try posix.listen(sockfd, 128);
    return sockfd;
}

pub fn run(alloc: std.mem.Allocator, port: u16, root_path: []const u8, opts: ServerOptions) !void {
    const listen_fd = try setupListen(port);
    defer posix.close(listen_fd);
    defer _ = ws2_32.WSACleanup();

    const iocp = try windows.CreateIoCompletionPort(windows.INVALID_HANDLE_VALUE, null, 0, 0);

    const max_c = opts.max_connections;
    const conns = try alloc.alloc(Conn, max_c);
    defer alloc.free(conns);

    for (conns) |*c| {
        c.* = Conn{
            .last_activity_ms = std.atomic.Value(i64).init(0),
        };
    }

    var buffers: ?[]u8 = null;
    defer if (buffers) |b| alloc.free(b);

    switch (opts.pool_mode) {
        .fixed => {
            const slab = try alloc.alloc(u8, max_c * opts.recv_buffer_size);
            buffers = slab;
            var i: usize = 0;
            while (i < max_c) : (i += 1) {
                const off = i * opts.recv_buffer_size;
                conns[i].buf = slab[off..][0..opts.recv_buffer_size];
                conns[i].buf_owned = false;
            }
        },
        .dynamic => {
            var i: usize = 0;
            while (i < opts.initial_connections and i < max_c) : (i += 1) {
                conns[i].buf = try alloc.alloc(u8, opts.recv_buffer_size);
                conns[i].buf_owned = true;
            }
        },
    }

    const used = try alloc.alloc(bool, max_c);
    defer alloc.free(used);
    @memset(used, false);

    const ctx_ptr = try alloc.create(Ctx);
    errdefer alloc.destroy(ctx_ptr);
    ctx_ptr.* = .{
        .alloc = alloc,
        .mutex = .{},
        .opts = opts,
        .iocp = iocp,
        .listen_fd = listen_fd,
        .conns = conns,
        .used = used,
        .doc_root = try std.fs.cwd().openDir(root_path, .{}),
    };
    defer ctx_ptr.doc_root.close();
    defer alloc.destroy(ctx_ptr);

    const accept_t = try std.Thread.spawn(.{}, acceptLoop, .{ctx_ptr});
    defer accept_t.join();

    const idle_thread: ?std.Thread = if (opts.idle_timeout_seconds > 0)
        try std.Thread.spawn(.{}, idleSweeper, .{ctx_ptr})
    else
        null;
    defer if (idle_thread) |t| t.join();

    var entries: [64]windows.OVERLAPPED_ENTRY = undefined;
    while (true) {
        const n = try windows.GetQueuedCompletionStatusEx(iocp, &entries, null, false);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const e = entries[i];
            const idx: usize = @intCast(e.lpCompletionKey);
            const conn = &ctx_ptr.conns[idx];
            const bytes: usize = @intCast(e.dwNumberOfBytesTransferred);

            if (e.lpOverlapped == &conn.recv_ov) {
                try onRecvComplete(ctx_ptr, idx, conn, bytes);
            } else if (e.lpOverlapped == &conn.send_ov) {
                onSendComplete(ctx_ptr, idx, conn, bytes);
            }
        }
    }
}

fn ensureRecvBuf(ctx: *Ctx, conn: *Conn) !void {
    if (conn.buf.len != 0) return;
    conn.buf = try ctx.alloc.alloc(u8, ctx.opts.recv_buffer_size);
    conn.buf_owned = true;
}

fn acceptLoop(ctx: *Ctx) void {
    while (true) {
        const client = posix.accept(ctx.listen_fd, null, null, 0) catch continue;

        ctx.mutex.lock();
        const idx: ?usize = blk: {
            for (ctx.used, 0..) |u, i| {
                if (!u) {
                    ctx.used[i] = true;
                    break :blk i;
                }
            }
            break :blk null;
        };
        ctx.mutex.unlock();

        if (idx == null) {
            posix.close(client);
            continue;
        }
        const i = idx.?;

        const conn = &ctx.conns[i];
        ensureRecvBuf(ctx, conn) catch {
            posix.close(client);
            ctx.mutex.lock();
            ctx.used[i] = false;
            ctx.mutex.unlock();
            continue;
        };

        conn.socket = client;
        conn.recv_ov = std.mem.zeroes(windows.OVERLAPPED);
        conn.send_ov = std.mem.zeroes(windows.OVERLAPPED);
        conn.read_len = 0;
        conn.write_buf = null;
        conn.write_buf_owned = false;
        conn.stream = null;
        touchActivity(conn);

        _ = windows.CreateIoCompletionPort(
            @as(windows.HANDLE, @ptrCast(client)),
            ctx.iocp,
            i,
            0,
        ) catch {
            posix.close(client);
            finishConn(ctx, i, conn);
            continue;
        };

        peer_log.printPeer(client);

        issueRecv(ctx, i) catch {
            finishConn(ctx, i, conn);
        };
    }
}

fn issueRecv(ctx: *Ctx, idx: usize) !void {
    const conn = &ctx.conns[idx];
    conn.recv_ov = std.mem.zeroes(windows.OVERLAPPED);
    var wsa = ws2_32.WSABUF{
        .buf = @ptrCast(conn.buf[conn.read_len..].ptr),
        .len = @intCast(conn.buf.len - conn.read_len),
    };
    var flags: u32 = 0;
    const r = ws2_32.WSARecv(
        conn.socket,
        @ptrCast(&wsa),
        1,
        null,
        &flags,
        &conn.recv_ov,
        null,
    );
    if (r != 0) {
        if (ws2_32.WSAGetLastError() != .WSA_IO_PENDING) {
            return error.WsaRecvFailed;
        }
    }
}

fn issueSend(ctx: *Ctx, idx: usize, data: []const u8) !void {
    const conn = &ctx.conns[idx];
    conn.send_ov = std.mem.zeroes(windows.OVERLAPPED);
    var wsa = ws2_32.WSABUF{
        .buf = @constCast(data.ptr),
        .len = @intCast(data.len),
    };
    const r = ws2_32.WSASend(
        conn.socket,
        @ptrCast(&wsa),
        1,
        null,
        0,
        &conn.send_ov,
        null,
    );
    if (r != 0) {
        if (ws2_32.WSAGetLastError() != .WSA_IO_PENDING) {
            return error.WsaSendFailed;
        }
    }
}

fn onRecvComplete(ctx: *Ctx, idx: usize, conn: *Conn, bytes: usize) !void {
    if (bytes == 0) {
        finishConn(ctx, idx, conn);
        return;
    }
    touchActivity(conn);
    conn.read_len += bytes;
    const data = conn.buf[0..conn.read_len];

    if (!http.hasFullHttpHead(data)) {
        if (conn.read_len >= conn.buf.len) {
            finishConn(ctx, idx, conn);
            return;
        }
        try issueRecv(ctx, idx);
        return;
    }

    const path = http.parseGetPath(data) orelse {
        const resp = try http.errorResponse(ctx.alloc, 400, "Bad Request");
        conn.write_buf = resp;
        conn.write_buf_owned = true;
        try issueSend(ctx, idx, resp);
        return;
    };

    const prep = http.prepareGet(ctx.alloc, ctx.doc_root, path, data) catch {
        finishConn(ctx, idx, conn);
        return;
    };
    switch (prep) {
        .simple => |buf| {
            conn.write_buf = buf;
            conn.write_buf_owned = true;
            conn.stream = null;
            try issueSend(ctx, idx, buf);
        },
        .stream => |s| {
            conn.write_buf = s.first_buf;
            conn.write_buf_owned = true;
            conn.stream = .{
                .file = s.file,
                .next = s.next,
                .end = s.end,
                .chunk_buf = s.chunk_buf,
            };
            try issueSend(ctx, idx, s.first_buf);
        },
    }
}

fn onSendComplete(ctx: *Ctx, idx: usize, conn: *Conn, bytes: usize) void {
    _ = bytes;
    touchActivity(conn);
    if (conn.write_buf) |w| {
        if (conn.write_buf_owned) ctx.alloc.free(w);
        conn.write_buf = null;
        conn.write_buf_owned = false;
    }
    if (conn.stream) |*sm| {
        if (sm.next >= sm.end) {
            sm.file.close();
            ctx.alloc.free(sm.chunk_buf);
            conn.stream = null;
            posix.close(conn.socket);
            releaseSlotAfterSend(ctx, idx, conn);
            return;
        }
        const to_read = @min(sm.chunk_buf.len, sm.end - sm.next);
        const n = http.readFileAtAll(sm.file, sm.chunk_buf[0..to_read], sm.next) catch {
            sm.file.close();
            ctx.alloc.free(sm.chunk_buf);
            conn.stream = null;
            posix.close(conn.socket);
            releaseSlotAfterSend(ctx, idx, conn);
            return;
        };
        if (n == 0) {
            sm.file.close();
            ctx.alloc.free(sm.chunk_buf);
            conn.stream = null;
            posix.close(conn.socket);
            releaseSlotAfterSend(ctx, idx, conn);
            return;
        }
        sm.next += n;
        conn.write_buf = sm.chunk_buf[0..n];
        conn.write_buf_owned = false;
        issueSend(ctx, idx, conn.write_buf.?) catch {
            sm.file.close();
            ctx.alloc.free(sm.chunk_buf);
            conn.stream = null;
            posix.close(conn.socket);
            releaseSlotAfterSend(ctx, idx, conn);
        };
        return;
    }
    posix.close(conn.socket);
    releaseSlotAfterSend(ctx, idx, conn);
}

fn releaseSlotAfterSend(ctx: *Ctx, idx: usize, conn: *Conn) void {
    ctx.mutex.lock();
    if (!ctx.used[idx]) {
        ctx.mutex.unlock();
        return;
    }
    if (ctx.opts.pool_mode == .dynamic and conn.buf_owned) {
        ctx.alloc.free(conn.buf);
        conn.buf = &.{};
        conn.buf_owned = false;
    }
    ctx.used[idx] = false;
    ctx.mutex.unlock();
}

fn finishConn(ctx: *Ctx, idx: usize, conn: *Conn) void {
    ctx.mutex.lock();
    if (!ctx.used[idx]) {
        ctx.mutex.unlock();
        return;
    }

    if (conn.write_buf) |w| {
        if (conn.write_buf_owned) ctx.alloc.free(w);
        conn.write_buf = null;
        conn.write_buf_owned = false;
    }
    if (conn.stream) |*sm| {
        sm.file.close();
        ctx.alloc.free(sm.chunk_buf);
        conn.stream = null;
    }
    posix.close(conn.socket);

    if (ctx.opts.pool_mode == .dynamic and conn.buf_owned) {
        ctx.alloc.free(conn.buf);
        conn.buf = &.{};
        conn.buf_owned = false;
    }

    ctx.used[idx] = false;
    ctx.mutex.unlock();
}
