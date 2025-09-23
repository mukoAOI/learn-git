const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SimpleCache(comptime K: type, comptime V: type) type {
    return struct {
        map: std.AutoHashMap(K, V),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .map = std.AutoHashMap(K, V).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn get(self: *Self, key: K) ?V {
            // 简单的缓存：获取值（这里没有实现LRU淘汰逻辑）
            return self.map.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            // 简单的缓存：插入或更新值
            // 在实际的LRU缓存中，这里还需要更新键的访问时间或顺序
            try self.map.put(key, value);

            // 高级：可以在这里检查 map.capacity() 和 map.count()，
            // 如果元素过多，可以移除最旧的一个条目。
        }
    };
}

test "simple cache" {
    var cache = SimpleCache(i32, []const u8).init(std.testing.allocator);
    defer cache.deinit();

    try cache.put(1, "Cached Value 1");
    try cache.put(42, "The Answer");

    try std.testing.expectEqualStrings("The Answer", cache.get(42).?);
    try std.testing.expect(cache.get(999) == null);
}
