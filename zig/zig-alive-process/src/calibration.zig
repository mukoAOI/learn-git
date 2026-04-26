//! Dynamic refresh FPS from throughput, matching alive-progress calibration curve.

const std = @import("std");

const min_fps: f64 = 2.0;
const max_fps: f64 = 60.0;

/// Returns FPS for the current observed rate (items per second).
/// `calibrate` is the rate at which FPS reaches `max_fps` (default 1_000_000 in Python).
pub fn fpsForRate(calibrate: f64, rate: f64) f64 {
    const c = @max(1e-6, calibrate);
    const adjust_log_curve = 100.0 / @min(c, 100.0);
    const factor = (max_fps - min_fps) / @log10((c * adjust_log_curve) + 1.0);

    if (rate <= 0) return 10.0;
    if (rate < c) {
        return @log10((rate * adjust_log_curve) + 1.0) * factor + min_fps;
    }
    return max_fps;
}

pub fn sleepNsForNextFrame(calibrate: f64, rate: f64) u64 {
    const fps = fpsForRate(calibrate, rate);
    const period_s = 1.0 / fps;
    return @intFromFloat(@max(period_s * std.time.ns_per_s, 1.0));
}

test "fps curve bounds" {
    try std.testing.expect(fpsForRate(1_000_000, 0) == 10.0);
    try std.testing.expect(fpsForRate(1_000_000, 1_000_000) >= max_fps - 0.001);
    try std.testing.expect(fpsForRate(1_000_000, 1) > min_fps);
}
