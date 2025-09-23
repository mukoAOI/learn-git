const std = @import("std");

/// 构建优化后的 KMP next 数组
fn buildNext(comptime pattern: []const u8) []const isize {
    const n = pattern.len;
    var next = std.heap.page_allocator.alloc(isize, n) catch unreachable; // 分配 next 数组
    next[0] = -1; // 初始值设为 -1

    var i: usize = 0;   // 主指针
    var j: isize = -1;  // 前缀指针（使用 isize 以处理 -1）

    while (i < n - 1) {
        // j == -1 表示需要从头开始匹配
        // pattern[i] == pattern[j] 表示当前字符匹配成功
        if (j == -1 or pattern[i] == pattern[j]) {
            i += 1;
            j += 1;
            // 优化：若当前字符与回溯后字符相同，则直接继承更早的回溯位置
            if (i < n and pattern[i] == pattern[@intCast(j)]) {
                next[i] = next[@intCast(j)];
            } else {
                next[i] = j;
            }
        } else {
            // 不匹配时回溯到 next[j] 的位置
            j = next[@intCast(j)];
        }
    }
    return next;
}

/// KMP 搜索算法，返回第一个匹配的起始索引（未找到则返回 null）
fn kmpSearch(comptime text: []const u8, comptime pattern: []const u8) ?usize {
    const next = buildNext(pattern); // 构建 next 数组
    defer std.heap.page_allocator.free(next); // 确保释放内存

    var i: usize = 0; // 文本索引
    var j: isize = 0; // 模式索引（使用 isize 以兼容 next 数组的负值）

    while (i < text.len and j < pattern.len) {
        // j == -1 表示需要从头匹配模式
        if (j == -1 or text[i] == pattern[@intCast(j)]) {
            i += 1;
            j += 1;
        } else {
            // 利用 next 数组跳过不必要的比较
            j = next[@intCast(j)];
        }
    }

    return if (j == pattern.len) i - @intCast(j) else null;
}

// 测试代码
pub fn main() !void {
    const text = "ABABDABACDABABCABAB";
    const pattern = "ABABCABAB";

    if (kmpSearch(text, pattern)) |index| {
        std.debug.print("模式在索引 {} 处找到\n", .{index});
    } else {
        std.debug.print("未找到匹配模式\n", .{});
    }
}
