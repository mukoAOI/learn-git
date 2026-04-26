//! Higher-level API examples: closer to tqdm-style ergonomics.
//!
//! Run with:
//!   zig build example-easy

const std = @import("std");
const alive = @import("alive_progress");

const Job = struct {
    name: []const u8,
    delay_ms: u64,
};

pub fn main(init: std.process.Init) !void {
    const jobs = [_]Job{
        .{ .name = "download", .delay_ms = 220 },
        .{ .name = "parse", .delay_ms = 180 },
        .{ .name = "transform", .delay_ms = 260 },
        .{ .name = "write", .delay_ms = 160 },
    };

    try alive.forEach(init.gpa, init.io, jobs[0..], .{
        .title = "forEach",
        .length = 28,
        .style = alive.ProgressStyle.arrow(),
        .refresh_ms = 180,
    }, {}, runJob);

    try alive.range(init.gpa, init.io, 30, .{
        .title = "range",
        .length = 28,
        .refresh_ms = 180,
    }, {}, runStep);
}

fn runJob(_: void, job: Job, _: usize, bar: *alive.AliveBar) !void {
    try bar.setText(job.name);
    alive.platform.sleepNs(job.delay_ms * std.time.ns_per_ms);
}

fn runStep(_: void, index: usize, bar: *alive.AliveBar) !void {
    if (index % 10 == 0) {
        var text_buf: [64]u8 = undefined;
        const text = try std.fmt.bufPrint(&text_buf, "step {d}", .{index});
        try bar.setText(text);
    }
    alive.platform.sleepNs(35 * std.time.ns_per_ms);
}
