//! Basic known-total progress.
//!
//! Run with:
//!   zig build example-basic

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, 80, .{
        .title = "download",
        .length = 30,
        .refresh_ms = 180,
    });
    defer bar.destroy();

    var i: u32 = 0;
    while (i < 80) : (i += 1) {
        alive.platform.sleepNs(20 * std.time.ns_per_ms);
        bar.tick(1);

        if (i == 25) try bar.setText("switching mirror");
        if (i == 50) try bar.setText("verifying chunks");
    }

    try bar.setText("done");
    try bar.finish();
}
