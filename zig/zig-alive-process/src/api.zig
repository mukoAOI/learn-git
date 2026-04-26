//! Convenience APIs: nicer lifecycle handling, inspired by tqdm/alive_it ergonomics.

const std = @import("std");
const progress = @import("progress.zig");
const platform = @import("platform.zig");

pub const Config = progress.Config;
pub const AliveBar = progress.AliveBar;

/// Create a progress bar, pass it to `body`, and always finish/destroy it.
///
/// `body` must be callable as:
///   `try body(context, bar);`
pub fn withBar(
    allocator: std.mem.Allocator,
    io: std.Io,
    total: ?u64,
    cfg: Config,
    context: anytype,
    comptime body: anytype,
) !void {
    const bar = try AliveBar.create(allocator, io, total, cfg);
    defer bar.destroy();

    try body(context, bar);
    try bar.finish();
}

/// Progress over `0..total`, similar to `tqdm(range(total))`.
///
/// `body` must be callable as:
///   `try body(context, index, bar);`
pub fn range(
    allocator: std.mem.Allocator,
    io: std.Io,
    total: usize,
    cfg: Config,
    context: anytype,
    comptime body: anytype,
) !void {
    const bar = try AliveBar.create(allocator, io, @intCast(total), cfg);
    defer bar.destroy();

    for (0..total) |index| {
        try body(context, index, bar);
        bar.tick(1);
    }

    try bar.finish();
}

/// Progress over a slice/array, similar to wrapping an iterable with tqdm.
///
/// `body` must be callable as:
///   `try body(context, item, index, bar);`
pub fn forEach(
    allocator: std.mem.Allocator,
    io: std.Io,
    items: anytype,
    cfg: Config,
    context: anytype,
    comptime body: anytype,
) !void {
    const bar = try AliveBar.create(allocator, io, @intCast(items.len), cfg);
    defer bar.destroy();

    for (items, 0..) |item, index| {
        try body(context, item, index, bar);
        bar.tick(1);
    }

    try bar.finish();
}

/// Run one blocking/opaque operation while the bar advances with a heartbeat.
///
/// This is for APIs that do not expose progress callbacks and whose duration is unknown. The
/// operation can still update text/title through the `bar` passed to `body`.
///
/// `body` must be callable as:
///   `try body(context, bar);`
pub fn untilDone(
    allocator: std.mem.Allocator,
    io: std.Io,
    cfg: Config,
    heartbeat_ms: u64,
    context: anytype,
    comptime body: anytype,
) !void {
    const bar = try AliveBar.create(allocator, io, null, cfg);
    defer bar.destroy();

    var heartbeat = Heartbeat{
        .bar = bar,
        .running = std.atomic.Value(bool).init(true),
        .heartbeat_ms = @max(heartbeat_ms, 1),
    };
    const thread = try std.Thread.spawn(.{}, heartbeatMain, .{&heartbeat});
    defer {
        heartbeat.running.store(false, .release);
        thread.join();
    }

    try body(context, bar);
    try bar.finish();
}

const Heartbeat = struct {
    bar: *AliveBar,
    running: std.atomic.Value(bool),
    heartbeat_ms: u64,
};

fn heartbeatMain(ctx: *Heartbeat) void {
    while (ctx.running.load(.acquire)) {
        platform.sleepNs(ctx.heartbeat_ms * std.time.ns_per_ms);
        if (!ctx.running.load(.acquire)) break;
        ctx.bar.tick(1);
    }
}
