//! Manual percentage mode for operations that report a fraction directly.
//!
//! Run with:
//!   zig build example-manual

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
        .title = "pipeline",
        .length = 32,
        .manual = true,
        .refresh_ms = 180,
    });
    defer bar.destroy();

    const steps = [_]struct {
        text: []const u8,
        fraction: f64,
        delay_ms: u64,
    }{
        .{ .text = "read input", .fraction = 0.10, .delay_ms = 250 },
        .{ .text = "parse", .fraction = 0.35, .delay_ms = 350 },
        .{ .text = "transform", .fraction = 0.75, .delay_ms = 500 },
        .{ .text = "write output", .fraction = 1.00, .delay_ms = 250 },
    };

    for (steps) |step| {
        try bar.setText(step.text);
        alive.platform.sleepNs(step.delay_ms * std.time.ns_per_ms);
        bar.setFraction(step.fraction);
    }

    try bar.finish();
}
