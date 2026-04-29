const std = @import("std");
const Alignment = std.mem.Alignment;

pub const c = @cImport({
    @cInclude("mimalloc.h");
});

pub fn malloc(bytes: usize) ?*anyopaque {
    return c.mi_malloc(bytes);
}

pub fn calloc(count: usize, bytes: usize) ?*anyopaque {
    return c.mi_calloc(count, bytes);
}

pub fn realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    return c.mi_realloc(ptr, new_size);
}

pub fn free(ptr: ?*anyopaque) void {
    c.mi_free(ptr);
}

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &MimallocAllocator.vtable,
};

const MimallocAllocator = struct {
    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = freeAlloc,
    };

    fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        std.debug.assert(len > 0);
        const ptr = if (Alignment.compare(alignment, .lte, .of(std.c.max_align_t)))
            c.mi_malloc(len)
        else
            c.mi_malloc_aligned(len, alignment.toByteUnits());
        return @ptrCast(ptr);
    }

    fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        std.debug.assert(new_len > 0);
        _ = alignment;
        if (new_len <= memory.len) return true;
        const expanded = c.mi_expand(memory.ptr, new_len) orelse return false;
        return @intFromPtr(expanded) == @intFromPtr(memory.ptr);
    }

    fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        std.debug.assert(new_len > 0);
        const ptr = if (Alignment.compare(alignment, .lte, .of(std.c.max_align_t)))
            c.mi_realloc(memory.ptr, new_len)
        else
            c.mi_realloc_aligned(memory.ptr, new_len, alignment.toByteUnits());
        return @ptrCast(ptr);
    }

    fn freeAlloc(_: *anyopaque, memory: []u8, _: Alignment, _: usize) void {
        c.mi_free(memory.ptr);
    }
};

test "basic allocation and free" {
    const ptr = malloc(64) orelse return error.OutOfMemory;
    defer free(ptr);

    const bytes: [*]u8 = @ptrCast(@alignCast(ptr));
    bytes[0] = 0xAB;
    try std.testing.expect(bytes[0] == 0xAB);
}

test "allocator interface works" {
    var buffer = try allocator.alloc(u8, 64);
    defer allocator.free(buffer);

    buffer[0] = 0xCD;
    buffer = try allocator.realloc(buffer, 128);
    try std.testing.expect(buffer[0] == 0xCD);
}
