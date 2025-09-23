const std = @import("std");

const Person = struct {
    name: []const u8,
    age: u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const person = Person{ .name = "Alice", .age = 30 };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try std.json.stringify(person, .{}, buffer.writer());

    std.debug.print("Serialized JSON: {s}\n", .{buffer.items});
}
