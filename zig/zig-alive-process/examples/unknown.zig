//! Unknown-total progress, similar to Python alive-progress unknown mode.
//!
//! Run with:
//!   zig build example-unknown

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, null, .{
        .title = "scan",
        .length = 48,
        .refresh_ms = 220,
    });
    defer bar.destroy();

    var files_seen: u32 = 0;
    while (files_seen < 600) : (files_seen += 1) {
        alive.platform.sleepNs(18 * std.time.ns_per_ms);
        bar.tick(1);

        if (files_seen == 20) try bar.setText("deep directory");
        if (files_seen == 45) try bar.setText("almost idle");
    }

    try bar.finish();
}
