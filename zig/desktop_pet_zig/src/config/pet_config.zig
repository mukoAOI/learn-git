const std = @import("std");

pub const RenderConfig = struct {
    scale: f32 = 0.35,
    window_x: i32 = 1200,
    window_y: i32 = 620,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    font_file: []const u8 = "",
    font_size: i32 = 20,
    menu_padding: i32 = 12,
    menu_gap: i32 = 10,
    menu_min_width: i32 = 220,
    menu_max_width: i32 = 420,
    item_text_top_pad: i32 = 7,
};

pub fn load(allocator: std.mem.Allocator, io: std.Io) RenderConfig {
    var cfg = RenderConfig{};
    const data = std.Io.Dir.cwd().readFileAlloc(io, "config/pet.conf", allocator, .limited(64 * 1024)) catch return cfg;
    defer allocator.free(data);

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "scale")) {
            cfg.scale = std.fmt.parseFloat(f32, value) catch cfg.scale;
        } else if (std.mem.eql(u8, key, "window_x")) {
            cfg.window_x = std.fmt.parseInt(i32, value, 10) catch cfg.window_x;
        } else if (std.mem.eql(u8, key, "window_y")) {
            cfg.window_y = std.fmt.parseInt(i32, value, 10) catch cfg.window_y;
        } else if (std.mem.eql(u8, key, "offset_x")) {
            cfg.offset_x = std.fmt.parseFloat(f32, value) catch cfg.offset_x;
        } else if (std.mem.eql(u8, key, "offset_y")) {
            cfg.offset_y = std.fmt.parseFloat(f32, value) catch cfg.offset_y;
        } else if (std.mem.eql(u8, key, "font_file")) {
            cfg.font_file = allocator.dupe(u8, value) catch cfg.font_file;
        } else if (std.mem.eql(u8, key, "font_size")) {
            cfg.font_size = std.fmt.parseInt(i32, value, 10) catch cfg.font_size;
        } else if (std.mem.eql(u8, key, "menu_padding")) {
            cfg.menu_padding = std.fmt.parseInt(i32, value, 10) catch cfg.menu_padding;
        } else if (std.mem.eql(u8, key, "menu_gap")) {
            cfg.menu_gap = std.fmt.parseInt(i32, value, 10) catch cfg.menu_gap;
        } else if (std.mem.eql(u8, key, "menu_min_width")) {
            cfg.menu_min_width = std.fmt.parseInt(i32, value, 10) catch cfg.menu_min_width;
        } else if (std.mem.eql(u8, key, "menu_max_width")) {
            cfg.menu_max_width = std.fmt.parseInt(i32, value, 10) catch cfg.menu_max_width;
        } else if (std.mem.eql(u8, key, "item_text_top_pad")) {
            cfg.item_text_top_pad = std.fmt.parseInt(i32, value, 10) catch cfg.item_text_top_pad;
        }
    }
    if (cfg.font_size < 12) cfg.font_size = 12;
    if (cfg.font_size > 64) cfg.font_size = 64;
    if (cfg.menu_padding < 6) cfg.menu_padding = 6;
    if (cfg.menu_gap < 4) cfg.menu_gap = 4;
    if (cfg.menu_min_width < 160) cfg.menu_min_width = 160;
    if (cfg.menu_max_width < cfg.menu_min_width) cfg.menu_max_width = cfg.menu_min_width;
    if (cfg.item_text_top_pad < 0) cfg.item_text_top_pad = 0;
    if (cfg.item_text_top_pad > 40) cfg.item_text_top_pad = 40;
    return cfg;
}
