//! One opaque API call with unknown duration.
//!
//! `untilDone()` keeps an unknown-total progress bar alive with heartbeat ticks while the
//! blocking API runs.
//!
//! Run with:
//!   zig build example-until_done

const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    try alive.untilDone(init.gpa, init.io, .{
        .title = "api",
        .length = 30,
        .refresh_ms = 220,
    }, 250, {}, callSlowApi);
}

fn callSlowApi(_: void, bar: *alive.AliveBar) !void {
    try bar.setText("connecting");
    alive.platform.sleepNs(800 * std.time.ns_per_ms);

    try bar.setText("waiting for remote service");
    alive.platform.sleepNs(1400 * std.time.ns_per_ms);

    try bar.setText("finalizing response");
    alive.platform.sleepNs(900 * std.time.ns_per_ms);
}
