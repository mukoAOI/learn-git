//! Build bar line (UTF-8), inspired by alive-progress smooth bar.

const std = @import("std");
const style = @import("style.zig");

const partials = [_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" };

pub const BarState = union(enum) {
    known: f64,
    unknown: u32,
};

fn partsFor(spec: style.BarSpec) style.BarParts {
    return switch (spec) {
        .blocks => .{
            .fill = "█",
            .tip = "",
            .empty = " ",
            .unknown_fill = "█",
            .unknown_empty = "░",
        },
        .arrow => .{
            .fill = "=",
            .tip = ">",
            .empty = " ",
            .unknown_fill = "=",
            .unknown_empty = " ",
        },
        .custom => |custom| custom,
    };
}

pub fn writeBar(w: *std.Io.Writer, length: u32, state: BarState, spec: style.BarSpec) !void {
    const parts = partsFor(spec);
    switch (state) {
        .known => |fraction| try writeKnownBarParts(w, length, fraction, parts),
        .unknown => |phase| try writeUnknownBarParts(
            w,
            length,
            phase,
            parts.unknown_fill,
            parts.unknown_empty,
        ),
    }
}

fn writeKnownBarParts(w: *std.Io.Writer, length: u32, fraction: f64, parts: style.BarParts) !void {
    if (parts.tip.len == 0) {
        return writeBlockLikeBar(w, length, fraction, parts);
    }

    const f = std.math.clamp(fraction, 0, 1);
    const filled: u32 = @intFromFloat(@round(f * @as(f64, @floatFromInt(length))));

    var i: u32 = 0;
    while (i < length) : (i += 1) {
        if (i + 1 < filled) {
            try w.writeAll(parts.fill);
        } else if (i + 1 == filled and filled < length) {
            try w.writeAll(parts.tip);
        } else if (filled >= length) {
            try w.writeAll(parts.fill);
        } else {
            try w.writeAll(parts.empty);
        }
    }
}

fn writeBlockLikeBar(w: *std.Io.Writer, length: u32, fraction: f64, parts: style.BarParts) !void {
    const f = std.math.clamp(fraction, 0, 1);
    const virt: f64 = @floatFromInt(length);
    const pos = f * virt;
    const full: u32 = @intFromFloat(@floor(pos));
    const frac = pos - @floor(pos);
    const partial_idx: usize = if (frac > 0) @intFromFloat(@min(frac * 8.0, 7.0)) else 0;

    var i: u32 = 0;
    while (i < full) : (i += 1) {
        try w.writeAll(parts.fill);
    }
    if (full < length and frac > 0) {
        try w.writeAll(partials[partial_idx]);
        i += 1;
    }
    while (i < length) : (i += 1) {
        try w.writeAll(parts.empty);
    }
}

fn writeUnknownBarParts(
    w: *std.Io.Writer,
    length: u32,
    phase: u32,
    fill: []const u8,
    empty: []const u8,
) !void {
    const seg: u32 = @max(3, length / 4);
    var i: u32 = 0;
    while (i < length) : (i += 1) {
        const p = (i +% phase) % length;
        const in_win = p < seg;
        try w.writeAll(if (in_win) fill else empty);
    }
}

fn fixedWriter(buf: []u8) std.Io.Writer {
    return .{
        .vtable = &.{
            .drain = std.Io.Writer.fixedDrain,
            .flush = std.Io.Writer.noopFlush,
            .rebase = std.Io.Writer.failingRebase,
        },
        .buffer = buf,
        .end = 0,
    };
}

test "known bar keeps requested width" {
    var buf: [128]u8 = undefined;
    var w = fixedWriter(&buf);
    try writeBar(&w, 10, .{ .known = 0.5 }, .blocks);

    try std.testing.expect(std.mem.count(u8, buf[0..w.end], "█") >= 5);
}

test "unknown bar handles non-zero width" {
    var buf: [128]u8 = undefined;
    var w = fixedWriter(&buf);
    try writeBar(&w, 8, .{ .unknown = 3 }, .blocks);

    try std.testing.expect(w.end > 0);
}

test "arrow bar uses arrow head" {
    var buf: [128]u8 = undefined;
    var w = fixedWriter(&buf);
    try writeBar(&w, 10, .{ .known = 0.5 }, .arrow);

    try std.testing.expect(std.mem.indexOf(u8, buf[0..w.end], ">") != null);
}

test "custom bar style renders custom pieces" {
    var buf: [128]u8 = undefined;
    var w = fixedWriter(&buf);
    try writeBar(&w, 8, .{ .known = 0.5 }, style.BarSpec.fromParts("#", "@", "."));

    try std.testing.expect(std.mem.indexOf(u8, buf[0..w.end], "@") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..w.end], ".") != null);
}
