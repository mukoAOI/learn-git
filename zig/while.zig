const expect = @import("std").testing.expect;
const std = @import("std");

pub fn main() !void {
    var i: i32 = 0;
    while (i < 10000) : (i = i * i + 1) {
        std.debug.print("the value of i is {}\n", .{i});
    }

    const asd = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var j: usize = 0;
    while (j < asd.len) : (j += 1) {
        std.debug.print("{}\t", .{asd[j]});
    }
}
