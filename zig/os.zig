const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    std.debug.print("{}", .{builtin.os.tag});
}
