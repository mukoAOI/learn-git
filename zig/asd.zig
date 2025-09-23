const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 正确初始化 ArrayList
    var list = std.ArrayList(usize).init(allocator);
    defer list.deinit(); // 确保释放内存

    // 预分配容量（可选，但可以提高性能）
    try list.ensureTotalCapacity(8);

    // 添加元素（使用正确的 append 语法）
    for (0..8) |i| {
        try list.append(i);
    }

    // 安全地追加已存在的元素
    // 注意：这里直接使用值而不是引用，避免悬垂指针
    try list.append(list.items[5]);
}
