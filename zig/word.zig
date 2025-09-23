const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMap;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 打开文件
    const file = try std.fs.cwd().openFile("input.txt", .{});
    defer file.close();

    // 读取文件内容
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    std.debug.print("{}", .{content.len});
    defer allocator.free(content);

    // 统计词频
    var word_counts = try countWords(allocator, content);
    defer {
        var it = word_counts.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        word_counts.deinit();
    }

    // 输出结果
    var it = word_counts.iterator();
    while (it.next()) |entry| {
        std.debug.print("{s}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

fn countWords(allocator: Allocator, text: []const u8) !HashMap(u32) {
    var map = HashMap(u32).init(allocator);
    errdefer map.deinit();

    var words = std.mem.tokenizeAny(u8, text, " \t\n\r.,;:!?\"'()[]{}");

    while (words.next()) |word| {
        if (word.len == 0) continue;

        // 转换为小写
        const lower_word = try std.ascii.allocLowerString(allocator, word);
        defer allocator.free(lower_word);

        // 更新计数
        const gop = try map.getOrPut(lower_word);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, lower_word);
            gop.value_ptr.* = 1;
        } else {
            gop.value_ptr.* += 1;
        }
    }

    return map;
}
