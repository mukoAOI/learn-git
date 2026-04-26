//! Progress bar rendered as `=====>`.
//!
//! Run with:
//!   zig build example-arrow

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
        .title = "arrow",
        .length = 36,
        .style = alive.ProgressStyle.custom(
            .arrow,
            "[",
            "]",
            alive.style.dots_spinner[0..],
            "😍",
        ),
        .refresh_ms = 80,
    });
    defer bar.destroy();

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        alive.platform.sleepNs(20 * std.time.ns_per_ms);
        bar.tick(1);

        if (i == 40) try bar.setText("custom spinner");
        if (i == 70) try bar.setText("using => style");
    }

    try bar.setText("complete");
    try bar.finish();
}
