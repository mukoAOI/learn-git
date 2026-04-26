//! Progress bar style definitions and presets.

const std = @import("std");

pub const dots_spinner = [_][]const u8{
    "⠋",
    "⠙",
    "⠹",
    "⠸",
    "⠼",
    "⠴",
    "⠦",
    "⠧",
    "⠇",
    "⠏",
};

pub const arrow_spinner = [_][]const u8{
    ">    ", "=>   ", "==>  ", "===> ", "====>",
};

pub const line_spinner = [_][]const u8{ "- ", "\\", "| ", "/ " };
pub const quiet_spinner = [_][]const u8{""};

pub const BarParts = struct {
    fill: []const u8 = "=",
    tip: []const u8 = ">",
    empty: []const u8 = " ",
    unknown_fill: []const u8 = "=",
    unknown_empty: []const u8 = " ",

    pub fn init(fill: []const u8, tip: []const u8, empty: []const u8) BarParts {
        return .{
            .fill = fill,
            .tip = tip,
            .empty = empty,
            .unknown_fill = fill,
            .unknown_empty = empty,
        };
    }

    pub fn withUnknown(
        fill: []const u8,
        tip: []const u8,
        empty: []const u8,
        unknown_fill: []const u8,
        unknown_empty: []const u8,
    ) BarParts {
        return .{
            .fill = fill,
            .tip = tip,
            .empty = empty,
            .unknown_fill = unknown_fill,
            .unknown_empty = unknown_empty,
        };
    }
};

pub const BarSpec = union(enum) {
    blocks,
    arrow,

    /// Fully custom fixed-width bar pieces.
    ///
    /// `fill` is used behind progress, `tip` is the moving head, and `empty` fills the rest.
    /// For unknown-total mode, `unknown_fill` and `unknown_empty` are used by the sliding window.
    custom: BarParts,

    pub fn fromParts(fill: []const u8, tip: []const u8, empty: []const u8) BarSpec {
        return .{ .custom = BarParts.init(fill, tip, empty) };
    }

    pub fn fromPartsWithUnknown(
        fill: []const u8,
        tip: []const u8,
        empty: []const u8,
        unknown_fill: []const u8,
        unknown_empty: []const u8,
    ) BarSpec {
        return .{ .custom = BarParts.withUnknown(
            fill,
            tip,
            empty,
            unknown_fill,
            unknown_empty,
        ) };
    }
};

pub const ProgressStyle = struct {
    bar: BarSpec = .blocks,
    border_left: []const u8 = "|",
    border_right: []const u8 = "|",
    spinner_frames: []const []const u8 = dots_spinner[0..],
    warning_prefix: []const u8 = "(!) ",

    pub fn classic() ProgressStyle {
        return .{
            .bar = .blocks,
            .border_left = "|",
            .border_right = "|",
            .spinner_frames = dots_spinner[0..],
            .warning_prefix = "(!) ",
        };
    }

    pub fn square() ProgressStyle {
        return .{
            .bar = .blocks,
            .border_left = "[",
            .border_right = "]",
            .spinner_frames = line_spinner[0..],
            .warning_prefix = "! ",
        };
    }

    pub fn arrow() ProgressStyle {
        return .{
            .bar = .arrow,
            .border_left = "[",
            .border_right = "]",
            .spinner_frames = arrow_spinner[0..],
            .warning_prefix = "! ",
        };
    }

    pub fn naked() ProgressStyle {
        return .{
            .bar = .blocks,
            .border_left = "",
            .border_right = "",
            .spinner_frames = quiet_spinner[0..],
            .warning_prefix = "",
        };
    }

    pub fn custom(
        bar: BarSpec,
        border_left: []const u8,
        border_right: []const u8,
        spinner_frames: []const []const u8,
        warning_prefix: []const u8,
    ) ProgressStyle {
        return .{
            .bar = bar,
            .border_left = border_left,
            .border_right = border_right,
            .spinner_frames = if (spinner_frames.len == 0) quiet_spinner[0..] else spinner_frames,
            .warning_prefix = warning_prefix,
        };
    }
};

pub fn spinnerFrame(progress_style: ProgressStyle, frame_index: usize) []const u8 {
    const frames = if (progress_style.spinner_frames.len == 0) quiet_spinner[0..] else progress_style.spinner_frames;
    return frames[frame_index % frames.len];
}

test "preset style groups bar and borders" {
    const progress_style = ProgressStyle.arrow();
    switch (progress_style.bar) {
        .arrow => {},
        else => return error.UnexpectedBarSpec,
    }
    try std.testing.expectEqualStrings("[", progress_style.border_left);
    try std.testing.expectEqualStrings("]", progress_style.border_right);
    try std.testing.expect(progress_style.spinner_frames.len > 0);
    try std.testing.expectEqualStrings("! ", progress_style.warning_prefix);
}
