//! Resuming work with skipped items.
//!
//! `skip()` advances the monitor without contributing to throughput/ETA, matching
//! Python's `bar(..., skipped=True)`.
//!
//! Run with:
//!   zig build example-skipped

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, 120, .{
        .title = "resume",
        .length = 34,
        .refresh_ms = 180,
    });
    defer bar.destroy();

    try bar.setText("loading checkpoint");
    alive.platform.sleepNs(250 * std.time.ns_per_ms);
    bar.skip(70);

    try bar.setText("processing remaining items");
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        alive.platform.sleepNs(18 * std.time.ns_per_ms);
        bar.tick(1);
    }

    try bar.setText("resumed successfully");
    try bar.finish();
}
