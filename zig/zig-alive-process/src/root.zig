//! Zig port of [alive-progress](https://github.com/rsalmei/alive-progress) — core terminal progress bar.
//!
//! This is not a line-by-line translation of the Python package. It reproduces the main ideas:
//! dynamic refresh FPS from throughput, exponential smoothing for rate/ETA, smooth Unicode bar,
//! spinner, under/over progress warning prefix, and final receipt.
//!
//! Not ported: print/logging hooks, Jupyter, grapheme compiler, themes catalog, `alive_it`, pause API.

const std = @import("std");

pub const progress = @import("progress.zig");
pub const api = @import("api.zig");
pub const calibration = @import("calibration.zig");
pub const platform = @import("platform.zig");
pub const render = @import("render.zig");
pub const style = @import("style.zig");
pub const timing = @import("timing.zig");
pub const terminal = @import("terminal.zig");

pub const AliveBar = progress.AliveBar;
pub const Config = progress.Config;
pub const max_title_len = progress.max_title_len;
pub const max_text_len = progress.max_text_len;
pub const max_frame_len = progress.max_frame_len;
pub const ProgressStyle = style.ProgressStyle;
pub const BarSpec = style.BarSpec;
pub const BarParts = style.BarParts;
pub const withBar = api.withBar;
pub const range = api.range;
pub const forEach = api.forEach;
pub const untilDone = api.untilDone;

pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

test "alive bar counter and skipped progress" {
    const gpa = std.testing.allocator;
    var bar = try AliveBar.init(gpa, std.testing.io, 10, .{
        .force_tty = false,
        .receipt = false,
    });
    defer bar.deinit();

    bar.tick(2);
    bar.skip(3);

    try std.testing.expectEqual(@as(f64, 5), bar.current());
    try bar.finish();
}

test "alive bar reports text capacity errors" {
    const gpa = std.testing.allocator;
    var bar = try AliveBar.init(gpa, std.testing.io, 1, .{
        .force_tty = false,
        .receipt = false,
    });
    defer bar.deinit();

    var text: [max_text_len + 1]u8 = undefined;
    @memset(&text, 'x');

    try std.testing.expectError(error.TextTooLong, bar.setText(text[0..]));
}

test "range helper works without output" {
    try range(std.testing.allocator, std.testing.io, 3, .{
        .disable = true,
        .receipt = false,
    }, {}, testRangeBody);
}

fn testRangeBody(_: void, _: usize, _: *AliveBar) !void {}

test "untilDone helper works without output" {
    try untilDone(std.testing.allocator, std.testing.io, .{
        .disable = true,
        .receipt = false,
    }, 1, {}, testUntilDoneBody);
}

fn testUntilDoneBody(_: void, bar: *AliveBar) !void {
    try bar.setText("ok");
}
