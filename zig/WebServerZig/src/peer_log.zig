const std = @import("std");
const posix = std.posix;
const logger = @import("logger.zig");

/// 在已连接的套接字上打印对端 IP 与端口（accept 成功后调用）。
pub fn printPeer(socket: posix.socket_t) void {
    var storage: posix.sockaddr.storage = undefined;
    var len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    posix.getpeername(socket, @ptrCast(&storage), &len) catch return;
    const addr = std.net.Address.initPosix(@ptrCast(&storage));
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{f}", .{addr}) catch return;
    logger.peerConnected(s);
}
