//! Human-readable durations and exponential smoothing (rate / ETA).

const std = @import("std");

fn formatSeconds(buf: []u8, prefix: []const u8, seconds: f64, decimals: u8) []const u8 {
    if (decimals == 0) {
        return std.fmt.bufPrint(buf, "{s}{d:.0}s", .{ prefix, seconds }) catch unreachable;
    }
    if (decimals == 1) {
        return std.fmt.bufPrint(buf, "{s}{d:.1}s", .{ prefix, seconds }) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "{s}{d:.2}s", .{ prefix, seconds }) catch unreachable;
}

/// Running bar display: compact seconds.
pub fn formatElapsedRun(buf: []u8, seconds: f64) []const u8 {
    return formatRunLike(buf, seconds, false);
}

/// Final receipt: slightly higher precision.
pub fn formatElapsedEnd(buf: []u8, seconds: f64) []const u8 {
    return formatRunLike(buf, seconds, true);
}

fn formatRunLike(buf: []u8, seconds_in: f64, end_style: bool) []const u8 {
    const s = if (end_style) @round(seconds_in * 10.0) / 10.0 else @round(seconds_in);

    if (s < 60.0) {
        return formatSeconds(buf, "", s, if (end_style) 1 else 0);
    }

    var minutes = @floor(s / 60.0);
    var sec = s - minutes * 60.0;
    if (!end_style) {
        sec = @floor(sec / 10.0) * 10.0;
    } else {
        sec = @round(sec * 10.0) / 10.0;
    }

    if (minutes < 60.0) {
        return std.fmt.bufPrint(buf, "{d:.0}:{d:02.0}", .{ minutes, sec }) catch unreachable;
    }

    const hours = @floor(minutes / 60.0);
    minutes = @mod(minutes, 60.0);
    if (end_style) {
        return std.fmt.bufPrint(buf, "{d:.0}:{d:02.0}:{d:04.1}", .{ hours, minutes, sec }) catch unreachable;
    }
    sec = 0;
    return std.fmt.bufPrint(buf, "{d:.0}:{d:02.0}:{d:02.0}", .{ hours, minutes, sec }) catch unreachable;
}

/// ETA widget with `~` prefix; negative or invalid -> `"?"`.
pub fn formatEta(buf: []u8, seconds: f64) []const u8 {
    if (seconds < 0 or !std.math.isFinite(seconds)) return "?";
    var tmp: [64]u8 = undefined;
    const inner = formatRunLike(&tmp, seconds, false);
    return std.fmt.bufPrint(buf, "~{s}", .{inner}) catch unreachable;
}

/// Raw ETA before smoothing: remaining / rate.
pub fn simpleEta(logic_total: f64, pos: f64, rate: f64) f64 {
    if (rate <= 0) return -1;
    return (logic_total - pos) / rate;
}

pub fn exponentialSmoothing(comptime T: type, alpha: T) type {
    return struct {
        y_hat: T = 0,
        primed: bool = false,

        pub fn next(self: *@This(), y: T) T {
            if (!self.primed) {
                self.y_hat = y;
                self.primed = true;
                return self.y_hat;
            }
            self.y_hat += alpha * (y - self.y_hat);
            return self.y_hat;
        }

        pub fn reset(self: *@This()) void {
            self.* = .{};
        }
    };
}

test "smoothing" {
    var s = exponentialSmoothing(f64, 0.5){};
    _ = s.next(10.0);
    const v = s.next(20.0);
    try std.testing.expectApproxEqAbs(15.0, v, 1e-9);
}
