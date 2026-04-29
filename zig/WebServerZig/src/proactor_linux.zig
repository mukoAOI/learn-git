//! Linux: io_uring；连接池 fixed/dynamic、空闲 shutdown 释放槽位与缓冲。

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const IoUring = linux.IoUring;
const http = @import("http.zig");
const peer_log = @import("peer_log.zig");
const ServerOptions = @import("config.zig").ServerOptions;

const OpTag = enum(u8) {
    accept = 1,
    recv = 2,
    send = 3,
};

fn ud(op: OpTag, idx: u32) u64 {
    return (@as(u64, @intFromEnum(op)) << 32) | idx;
}

fn parse_ud(x: u64) struct { op: OpTag, idx: u32 } {
    return .{
        .op = @enumFromInt(@as(u8, @truncate(x >> 32))),
        .idx = @truncate(x),
    };
}

const StreamState = struct {
    file: std.fs.File,
    next: u64,
    end: u64,
    chunk_buf: []u8,
};

const Conn = struct {
    fd: posix.fd_t = -1,
    buf: []u8 = &.{},
    buf_owned: bool = false,
    read_len: usize = 0,
    write_buf: ?[]u8 = null,
    write_buf_owned: bool = false,
    stream: ?StreamState = null,
    last_activity_ms: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
};

const State = struct {
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    opts: ServerOptions,
    ring: IoUring,
    listen_fd: posix.fd_t,
    doc_root: std.fs.Dir,
    conns: []Conn,
    used: []bool,
};

fn touchActivity(conn: *Conn) void {
    _ = conn.last_activity_ms.store(std.time.milliTimestamp(), .monotonic);
}

fn idleSweeper(st: *State) void {
    const interval_ns = std.time.ns_per_s;
    while (true) {
        std.Thread.sleep(interval_ns);
        if (st.opts.idle_timeout_seconds == 0) continue;

        const now_ms = std.time.milliTimestamp();
        const timeout_ms: i64 = @intCast(st.opts.idle_timeout_seconds * std.time.ms_per_s);

        st.mutex.lock();
        var i: usize = 0;
        while (i < st.conns.len) : (i += 1) {
            if (!st.used[i]) continue;
            const conn = &st.conns[i];
            const last = conn.last_activity_ms.load(.monotonic);
            if (now_ms -| last > timeout_ms) {
                _ = posix.shutdown(conn.fd, .both) catch {};
            }
        }
        st.mutex.unlock();
    }
}

pub fn run(alloc: std.mem.Allocator, port: u16, root_path: []const u8, opts: ServerOptions) !void {
    const listen_fd = try setupListen(port);
    defer posix.close(listen_fd);

    var ring = try IoUring.init(512, 0);
    errdefer ring.deinit();

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

    var doc_root = try std.fs.cwd().openDir(root_path, .{});
    errdefer doc_root.close();

    var st = State{
        .alloc = alloc,
        .mutex = .{},
        .opts = opts,
        .ring = ring,
        .listen_fd = listen_fd,
        .doc_root = doc_root,
        .conns = conns,
        .used = used,
    };
    defer st.ring.deinit();
    defer st.doc_root.close();

    const idle_thread: ?std.Thread = if (opts.idle_timeout_seconds > 0)
        try std.Thread.spawn(.{}, idleSweeper, .{&st})
    else
        null;
    defer if (idle_thread) |t| t.join();

    var addr: posix.sockaddr.storage = undefined;
    var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    _ = try st.ring.accept(ud(.accept, 0), listen_fd, @ptrCast(&addr), &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
    _ = try st.ring.submit();

    var cqes: [64]linux.io_uring_cqe = undefined;

    while (true) {
        const n = try st.ring.copy_cqes(&cqes, 1);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            try dispatch(&st, cqes[i]);
        }
        _ = try st.ring.submit();
    }
}

fn setupListen(port: u16) !posix.fd_t {
    const sockfd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, posix.IPPROTO.TCP);
    errdefer posix.close(sockfd);

    const yes: i32 = 1;
    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&yes));

    const addr = try std.net.Address.parseIp4("0.0.0.0", port);
    try posix.bind(sockfd, &addr.any, addr.getOsSockLen());
    try posix.listen(sockfd, 128);
    return sockfd;
}

fn ensureRecvBuf(st: *State, conn: *Conn) !void {
    if (conn.buf.len != 0) return;
    conn.buf = try st.alloc.alloc(u8, st.opts.recv_buffer_size);
    conn.buf_owned = true;
}

fn acquire(st: *State) ?u32 {
    for (st.used, 0..) |u, idx| {
        if (!u) {
            st.used[idx] = true;
            return @intCast(idx);
        }
    }
    return null;
}

fn releaseConn(st: *State, idx: u32) void {
    st.mutex.lock();
    defer st.mutex.unlock();
    if (!st.used[idx]) return;

    const conn = &st.conns[idx];
    if (conn.write_buf) |w| {
        if (conn.write_buf_owned) st.alloc.free(w);
    }
    if (conn.stream) |*sm| {
        sm.file.close();
        st.alloc.free(sm.chunk_buf);
    }
    if (conn.fd >= 0) posix.close(conn.fd);

    if (st.opts.pool_mode == .dynamic and conn.buf_owned) {
        st.alloc.free(conn.buf);
        conn.buf = &.{};
        conn.buf_owned = false;
    }

    conn.* = Conn{
        .last_activity_ms = std.atomic.Value(i64).init(0),
    };
    st.used[idx] = false;
}

fn dispatch(st: *State, cqe: linux.io_uring_cqe) !void {
    const p = parse_ud(cqe.user_data);
    switch (p.op) {
        .accept => try onAccept(st, cqe),
        .recv => try onRecv(st, p.idx, cqe),
        .send => try onSend(st, p.idx, cqe),
    }
}

fn onAccept(st: *State, cqe: linux.io_uring_cqe) !void {
    var addr: posix.sockaddr.storage = undefined;
    var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);

    if (cqe.res < 0) {
        _ = try st.ring.accept(ud(.accept, 0), st.listen_fd, @ptrCast(&addr), &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        return;
    }
    const new_fd: posix.fd_t = cqe.res;

    const slot = acquire(st) orelse {
        posix.close(new_fd);
        _ = try st.ring.accept(ud(.accept, 0), st.listen_fd, @ptrCast(&addr), &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        return;
    };

    const conn = &st.conns[slot];
    ensureRecvBuf(st, conn) catch {
        posix.close(new_fd);
        st.mutex.lock();
        st.used[slot] = false;
        st.mutex.unlock();
        _ = try st.ring.accept(ud(.accept, 0), st.listen_fd, @ptrCast(&addr), &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        return;
    };

    conn.fd = new_fd;
    conn.read_len = 0;
    conn.write_buf = null;
    conn.write_buf_owned = false;
    conn.stream = null;
    touchActivity(conn);

    peer_log.printPeer(new_fd);
    _ = try st.ring.recv(ud(.recv, slot), new_fd, .{ .buffer = conn.buf[0..] }, 0);

    _ = try st.ring.accept(ud(.accept, 0), st.listen_fd, @ptrCast(&addr), &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
}

fn onRecv(st: *State, idx: u32, cqe: linux.io_uring_cqe) !void {
    const conn = &st.conns[idx];
    if (cqe.res <= 0) {
        releaseConn(st, idx);
        return;
    }
    touchActivity(conn);
    const nread: usize = @intCast(cqe.res);
    conn.read_len += nread;

    if (conn.read_len > conn.buf.len) {
        releaseConn(st, idx);
        return;
    }

    const data = conn.buf[0..conn.read_len];
    if (!http.hasFullHttpHead(data)) {
        if (conn.read_len == conn.buf.len) {
            releaseConn(st, idx);
            return;
        }
        _ = try st.ring.recv(ud(.recv, idx), conn.fd, .{ .buffer = conn.buf[conn.read_len..] }, 0);
        return;
    }

    const path = http.parseGetPath(data) orelse {
        const resp = try http.errorResponse(st.alloc, 400, "Bad Request");
        conn.write_buf = resp;
        conn.write_buf_owned = true;
        _ = try st.ring.send(ud(.send, idx), conn.fd, resp, 0);
        return;
    };

    const prep = http.prepareGet(st.alloc, st.doc_root, path, data) catch {
        releaseConn(st, idx);
        return;
    };
    switch (prep) {
        .simple => |buf| {
            conn.write_buf = buf;
            conn.write_buf_owned = true;
            conn.stream = null;
            _ = try st.ring.send(ud(.send, idx), conn.fd, buf, 0);
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
            _ = try st.ring.send(ud(.send, idx), conn.fd, s.first_buf, 0);
        },
    }
}

fn onSend(st: *State, idx: u32, cqe: linux.io_uring_cqe) !void {
    _ = cqe.res;
    const conn = &st.conns[idx];
    touchActivity(conn);

    if (conn.write_buf) |w| {
        if (conn.write_buf_owned) st.alloc.free(w);
        conn.write_buf = null;
        conn.write_buf_owned = false;
    }
    if (conn.stream) |*sm| {
        if (sm.next >= sm.end) {
            sm.file.close();
            st.alloc.free(sm.chunk_buf);
            conn.stream = null;
            const sock = conn.fd;
            conn.fd = -1;
            posix.close(sock);
            release(st, idx);
            return;
        }
        const to_read = @min(sm.chunk_buf.len, sm.end - sm.next);
        const n = try sm.file.preadAll(sm.chunk_buf[0..to_read], sm.next);
        if (n == 0) {
            sm.file.close();
            st.alloc.free(sm.chunk_buf);
            conn.stream = null;
            const sock = conn.fd;
            conn.fd = -1;
            posix.close(sock);
            release(st, idx);
            return;
        }
        sm.next += n;
        conn.write_buf = sm.chunk_buf[0..n];
        conn.write_buf_owned = false;
        _ = try st.ring.send(ud(.send, idx), conn.fd, conn.write_buf.?, 0);
        return;
    }
    const sock = conn.fd;
    conn.fd = -1;
    posix.close(sock);
    release(st, idx);
}

fn release(st: *State, idx: u32) void {
    releaseConn(st, idx);
}
