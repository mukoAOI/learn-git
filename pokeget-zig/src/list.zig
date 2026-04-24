const std = @import("std");
const pokemon = @import("pokemon.zig");

const Entry = struct {
    proper_name: []const u8,
    filename: []const u8,
};

pub const List = struct {
    allocator: std.mem.Allocator,
    entries: std.array_list.Managed(Entry),
    name_index: std.StringHashMapUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) !List {
        var list = List{
            .allocator = allocator,
            .entries = std.array_list.Managed(Entry).init(allocator),
            .name_index = .{},
        };
        try list.load();
        return list;
    }

    pub fn deinit(self: *List) void {
        self.name_index.deinit(self.allocator);
        self.entries.deinit();
    }

    fn load(self: *List) !void {
        const file = @embedFile("../data/names.csv");
        var lines = std.mem.tokenizeScalar(u8, file, '\n');

        while (lines.next()) |line_raw| {
            const line = std.mem.trimEnd(u8, line_raw, "\r");
            if (line.len == 0) continue;
            const comma = std.mem.indexOfScalar(u8, line, ',') orelse continue;
            const proper = line[0..comma];
            const filename = line[comma + 1 ..];
            try self.entries.append(.{
                .proper_name = proper,
                .filename = filename,
            });
            try self.name_index.put(self.allocator, filename, proper);
        }
    }

    pub fn formatName(self: *const List, filename: []const u8) []const u8 {
        return self.name_index.get(filename) orelse filename;
    }

    pub fn getById(self: *const List, id: usize) ?[]const u8 {
        if (id >= self.entries.items.len) return null;
        return self.entries.items[id].filename;
    }

    pub fn random(self: *const List, prng: std.Random) []const u8 {
        const idx = prng.uintLessThan(usize, self.entries.items.len);
        return self.entries.items[idx].filename;
    }

    pub fn getByRegion(self: *const List, region: pokemon.Region, prng: std.Random) []const u8 {
        const Bounds = struct { start: usize, end: usize };
        const bounds: Bounds = switch (region) {
            .Kanto => .{ .start = @as(usize, 0), .end = @as(usize, 151) },
            .Johto => .{ .start = @as(usize, 152), .end = @as(usize, 251) },
            .Hoenn => .{ .start = @as(usize, 252), .end = @as(usize, 386) },
            .Sinnoh => .{ .start = @as(usize, 387), .end = @as(usize, 493) },
            .Unova => .{ .start = @as(usize, 494), .end = @as(usize, 649) },
            .Kalos => .{ .start = @as(usize, 650), .end = @as(usize, 721) },
            .Alola => .{ .start = @as(usize, 722), .end = @as(usize, 809) },
            .Galar => .{ .start = @as(usize, 810), .end = @as(usize, 905) },
        };
        const len = bounds.end - bounds.start + 1;
        const idx = bounds.start + prng.uintLessThan(usize, len);
        return self.entries.items[idx].filename;
    }
};
