const std = @import("std");
const builtin = @import("builtin");
const zigimg = @import("zigimg");

const bindings = @import("c/bindings.zig");
const draw = @import("c/draw.zig");
const ft_text = @import("c/freetype_text.zig");
const geom = @import("logic/geom.zig");
const scale_logic = @import("logic/scale.zig");
const menu_layout = @import("logic/menu_layout.zig");
const config = @import("config/pet_config.zig");
const windows_os = @import("os/windows.zig");

const c = bindings.c;

fn loadChats(allocator: std.mem.Allocator, io: std.Io) []const []const u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "asset/chat.json", allocator, .limited(256 * 1024)) catch return &.{};
    var parsed = std.json.parseFromSlice([]const []const u8, allocator, data, .{}) catch {
        allocator.free(data);
        return &.{};
    };
    defer parsed.deinit();
    defer allocator.free(data);

    var out = allocator.alloc([]const u8, parsed.value.len) catch return &.{};
    for (parsed.value, 0..) |line, i| {
        out[i] = allocator.dupe(u8, line) catch line;
    }
    return out;
}

fn clampWindowToScreen(win_w: c_int, win_h: c_int, x: *c_int, y: *c_int) void {
    const monitor = c.glfwGetPrimaryMonitor() orelse return;
    const mode = c.glfwGetVideoMode(monitor) orelse return;
    const max_x: c_int = mode.*.width - win_w;
    const max_y: c_int = mode.*.height - win_h;
    if (x.* < 0) x.* = 0;
    if (y.* < 0) y.* = 0;
    if (x.* > max_x) x.* = max_x;
    if (y.* > max_y) y.* = max_y;
}

fn initTextRenderer(cfg: config.RenderConfig, font_path_out: *[260:0]u8) bool {
    if (cfg.font_file.len > 0 and cfg.font_file.len < 240) {
        const prefix = "asset/fonts/";
        @memcpy(font_path_out[0..prefix.len], prefix);
        @memcpy(font_path_out[prefix.len .. prefix.len + cfg.font_file.len], cfg.font_file);
        font_path_out[prefix.len + cfg.font_file.len] = 0;
        if (ft_text.init(font_path_out[0 .. prefix.len + cfg.font_file.len :0], cfg.font_size)) {
            return true;
        }
    }
    if (builtin.os.tag == .windows) {
        return ft_text.init("C:/Windows/Fonts/segoeui.ttf", cfg.font_size) or
            ft_text.init("C:/Windows/Fonts/arial.ttf", cfg.font_size) or
            ft_text.init("C:/Windows/Fonts/msyh.ttc", cfg.font_size);
    }
    if (builtin.os.tag == .macos) {
        return ft_text.init("/System/Library/Fonts/Supplemental/Arial.ttf", cfg.font_size);
    }
    return ft_text.init("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", cfg.font_size);
}

fn clampMenuWindowToScreen(menu_w: c_int, menu_h: c_int, x: *c_int, y: *c_int) void {
    clampWindowToScreen(menu_w, menu_h, x, y);
}

fn fitLabel(label: []const u8, max_width_px: f32, font_px: f32, buf: []u8) []const u8 {
    const char_w = font_px * 0.62;
    const ellipsis = "...";
    if (@as(f32, @floatFromInt(label.len)) * char_w <= max_width_px) return label;

    const ellipsis_w = @as(f32, @floatFromInt(ellipsis.len)) * char_w;
    var keep: usize = 0;
    while (keep < label.len and (@as(f32, @floatFromInt(keep + 1)) * char_w + ellipsis_w) <= max_width_px) : (keep += 1) {}
    if (keep > buf.len - ellipsis.len) keep = buf.len - ellipsis.len;
    @memcpy(buf[0..keep], label[0..keep]);
    @memcpy(buf[keep .. keep + ellipsis.len], ellipsis);
    return buf[0 .. keep + ellipsis.len];
}

fn estimateDisplayUnits(text: []const u8) f32 {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var units: f32 = 0;
    while (it.nextCodepoint()) |cp| {
        if (cp <= 0x7F) {
            // ASCII chars are usually narrower than CJK.
            if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or (cp >= '0' and cp <= '9')) {
                units += 0.55;
            } else if (cp == ' ') {
                units += 0.35;
            } else {
                units += 0.5;
            }
        } else if (
            (cp >= 0x4E00 and cp <= 0x9FFF) or // CJK Unified Ideographs
            (cp >= 0x3400 and cp <= 0x4DBF) or // CJK Extension A
            (cp >= 0xF900 and cp <= 0xFAFF) or // CJK Compatibility Ideographs
            (cp >= 0x3000 and cp <= 0x303F) or // CJK symbols/punctuation
            (cp >= 0xFF00 and cp <= 0xFFEF) // Fullwidth forms
        ) {
            units += 1.0;
        } else {
            units += 0.9;
        }
    }
    return units;
}

fn codepointDisplayUnits(cp: u21) f32 {
    if (cp <= 0x7F) {
        if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or (cp >= '0' and cp <= '9')) return 0.55;
        if (cp == ' ') return 0.35;
        return 0.5;
    }
    if (
        (cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0x3000 and cp <= 0x303F) or
        (cp >= 0xFF00 and cp <= 0xFFEF)
    ) return 1.0;
    return 0.9;
}

fn wrapTextLines(
    text: []const u8,
    max_units: f32,
    starts: *[16]usize,
    ends: *[16]usize,
) usize {
    var line_count: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var line_start: usize = 0;
    var line_units: f32 = 0;

    while (true) {
        const cp_start = it.i;
        const cp = it.nextCodepoint() orelse break;
        const cp_end = it.i;

        if (cp == '\n') {
            if (line_count < starts.len) {
                starts[line_count] = line_start;
                ends[line_count] = cp_start;
                line_count += 1;
            }
            line_start = cp_end;
            line_units = 0;
            continue;
        }

        const units = codepointDisplayUnits(cp);
        if (line_units + units > max_units and cp_start > line_start) {
            if (line_count < starts.len) {
                starts[line_count] = line_start;
                ends[line_count] = cp_start;
                line_count += 1;
            }
            line_start = cp_start;
            line_units = 0;
        }
        line_units += units;
    }

    if (line_start <= text.len and line_count < starts.len) {
        starts[line_count] = line_start;
        ends[line_count] = text.len;
        line_count += 1;
    }
    return if (line_count == 0) 1 else line_count;
}

fn drawMenuSliderComponent(
    text_ready: bool,
    item_x: f32,
    item_w: f32,
    slider_y: f32,
    menu_slider_h: f32,
    target_scale: f32,
    item_text_top_pad: f32,
    slider_hovered: bool,
) void {
    draw.drawSolidRect(item_x, slider_y, item_w, menu_slider_h, if (slider_hovered) 0.22 else 0.16, if (slider_hovered) 0.22 else 0.16, if (slider_hovered) 0.3 else 0.2, 0.96);
    if (text_ready) ft_text.drawText(item_x + 8, slider_y + item_text_top_pad, "SCALE", 1.0, 0.93, 0.93, 0.95, 1.0);
    const track_x = item_x + 8;
    const track_y = slider_y + menu_slider_h - 14;
    const track_w = item_w - 16;
    draw.drawSolidRect(track_x, track_y, track_w, 8, 0.2, 0.2, 0.25, 1.0);
    const t = (target_scale - 0.1) / (1.2 - 0.1);
    draw.drawSolidRect(track_x, track_y, track_w * t, 8, 0.44, 0.6, 0.95, 1.0);
    draw.drawSolidRect(track_x + track_w * t - 4, track_y - 3, 8, 14, 0.93, 0.93, 0.98, 1.0);
}

fn drawMenuButtonComponent(
    text_ready: bool,
    item_x: f32,
    item_y: f32,
    item_w: f32,
    menu_item_h: f32,
    label: []const u8,
    color_r: f32,
    color_g: f32,
    color_b: f32,
    hovered: bool,
    item_text_pad_x: f32,
    item_text_top_pad: f32,
) void {
    draw.drawSolidRect(item_x, item_y, item_w, menu_item_h, if (hovered) color_r + 0.07 else color_r, if (hovered) color_g + 0.06 else color_g, if (hovered) color_b + 0.06 else color_b, 0.98);
    if (text_ready) ft_text.drawText(item_x + item_text_pad_x, item_y + item_text_top_pad, label, 1.0, 0.95, 0.93, 0.93, 1.0);
}

fn applyScale(current_scale: *f32, new_scale: f32, image_w: usize, image_h: usize, sprite_w: *c_int, sprite_h: *c_int, window: ?*c.GLFWwindow) void {
    current_scale.* = scale_logic.clampScale(new_scale);
    const size = scale_logic.calcSpriteSize(image_w, image_h, current_scale.*);
    if (size.w != sprite_w.* or size.h != sprite_h.*) {
        sprite_w.* = @intCast(size.w);
        sprite_h.* = @intCast(size.h);
        c.glfwSetWindowSize(window, sprite_w.*, sprite_h.*);
    }
}

pub fn run(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const cfg = config.load(allocator, init.io);
    const chats = loadChats(allocator, init.io);

    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    var image = try zigimg.Image.fromFilePath(allocator, init.io, "asset/doro.png", read_buffer[0..]);
    defer image.deinit(allocator);
    try image.convert(allocator, .rgba32);
    const pixels = image.rawBytes();

    if (c.glfwInit() == c.GLFW_FALSE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_DECORATED, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_TRANSPARENT_FRAMEBUFFER, c.GLFW_TRUE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_FOCUSED, c.GLFW_TRUE);

    var current_scale = scale_logic.clampScale(cfg.scale);
    var target_scale = current_scale;
    const initial_size = scale_logic.calcSpriteSize(image.width, image.height, current_scale);
    var sprite_w: c_int = @intCast(initial_size.w);
    var sprite_h: c_int = @intCast(initial_size.h);

    const window = c.glfwCreateWindow(sprite_w, sprite_h, "doro", null, null) orelse return error.GlfwCreateWindowFailed;
    defer c.glfwDestroyWindow(window);
    c.glfwSetWindowPos(window, @intCast(cfg.window_x), @intCast(cfg.window_y));
    windows_os.applyWindowIcon(window);

    c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_DECORATED, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_FOCUSED, c.GLFW_TRUE);
    const ml = menu_layout.compute(cfg.font_size, cfg.menu_padding, cfg.menu_gap, cfg.menu_min_width, cfg.menu_max_width);
    const menu_window = c.glfwCreateWindow(ml.menu_w, ml.menu_h, "doro-menu", null, window) orelse return error.GlfwCreateMenuWindowFailed;
    defer c.glfwDestroyWindow(menu_window);
    c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_DECORATED, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_TRANSPARENT_FRAMEBUFFER, c.GLFW_TRUE);
    const bubble_window = c.glfwCreateWindow(320, 88, "doro-chat", null, window) orelse return error.GlfwCreateBubbleWindowFailed;
    defer c.glfwDestroyWindow(bubble_window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    var tex: c_uint = 0;
    c.glGenTextures(1, &tex);
    defer c.glDeleteTextures(1, &tex);

    c.glBindTexture(c.GL_TEXTURE_2D, tex);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, @intCast(image.width), @intCast(image.height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);

    c.glEnable(c.GL_TEXTURE_2D);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    var font_path_buf: [260:0]u8 = [_:0]u8{0} ** 260;
    const text_ready = initTextRenderer(cfg, &font_path_buf);
    defer if (text_ready) ft_text.deinit();

    var drag_active = false;
    var drag_mouse_screen_x: f64 = 0;
    var drag_mouse_screen_y: f64 = 0;
    var drag_window_x: c_int = 0;
    var drag_window_y: c_int = 0;
    var pet_press_active = false;
    var pet_press_start_x: f64 = 0;
    var pet_press_start_y: f64 = 0;
    const drag_threshold_px: f64 = 6.0;
    var right_prev = false;
    var left_prev = false;
    var menu_left_prev = false;

    var menu_visible = false;
    var menu_x: c_int = 20;
    var menu_y: c_int = 20;
    const menu_wf: f32 = ml.menu_wf;
    const menu_slider_h: f32 = ml.menu_slider_h;
    const menu_item_h: f32 = ml.menu_item_h;
    const menu_gap: f32 = ml.menu_gap;
    const menu_pad: f32 = ml.menu_pad;
    const menu_hf: f32 = ml.menu_hf;
    var slider_dragging = false;
    const close_btn_size: f32 = menu_layout.menu_close_btn_size_px;
    var menu_drag_active = false;
    var menu_drag_mouse_screen_x: f64 = 0;
    var menu_drag_mouse_screen_y: f64 = 0;
    var menu_drag_window_x: c_int = 0;
    var menu_drag_window_y: c_int = 0;
    var bubble_visible = false;
    var bubble_start_t: f64 = 0;
    var bubble_idx: usize = 0;
    var bubble_w: c_int = 320;
    var bubble_h: c_int = 88;
    var bubble_text_pad: f32 = 10;
    var bubble_line_h: f32 = 22;
    var bubble_line_count: usize = 1;
    var bubble_line_starts: [16]usize = [_]usize{0} ** 16;
    var bubble_line_ends: [16]usize = [_]usize{0} ** 16;
    const bubble_show_s: f64 = 2.4;
    const bubble_fade_s: f64 = 0.8;
    const seed: u64 = @as(u64, @intFromFloat(c.glfwGetTime() * 1000000.0)) ^ @as(u64, @intCast(@intFromPtr(window)));
    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        var fb_w: c_int = 0;
        var fb_h: c_int = 0;
        c.glfwGetFramebufferSize(window, &fb_w, &fb_h);

        const left_pressed = c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_LEFT) == c.GLFW_PRESS;
        var cursor_x: f64 = 0;
        var cursor_y: f64 = 0;
        c.glfwGetCursorPos(window, &cursor_x, &cursor_y);
        const cursor_xf: f32 = @floatCast(cursor_x);
        const cursor_yf: f32 = @floatCast(cursor_y);
        const right_pressed = c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_RIGHT) == c.GLFW_PRESS;

        if (right_pressed and !right_prev) {
            menu_visible = true;
            var wx: c_int = 0;
            var wy: c_int = 0;
            c.glfwGetWindowPos(window, &wx, &wy);
            menu_x = wx + @as(c_int, @intFromFloat(cursor_xf));
            menu_y = wy + @as(c_int, @intFromFloat(cursor_yf));
            clampMenuWindowToScreen(ml.menu_w, ml.menu_h, &menu_x, &menu_y);
            c.glfwSetWindowPos(menu_window, menu_x, menu_y);
            c.glfwShowWindow(menu_window);
        }
        right_prev = right_pressed;

        if (!menu_visible and left_pressed and !left_prev) {
            pet_press_active = true;
            pet_press_start_x = cursor_x;
            pet_press_start_y = cursor_y;
        }

        if (!menu_visible and left_pressed and pet_press_active and !drag_active) {
            const dx0 = cursor_x - pet_press_start_x;
            const dy0 = cursor_y - pet_press_start_y;
            if (dx0 * dx0 + dy0 * dy0 >= drag_threshold_px * drag_threshold_px) {
                var wx: c_int = 0;
                var wy: c_int = 0;
                c.glfwGetWindowPos(window, &wx, &wy);
                drag_active = true;
                drag_window_x = wx;
                drag_window_y = wy;
                drag_mouse_screen_x = @as(f64, @floatFromInt(wx)) + cursor_x;
                drag_mouse_screen_y = @as(f64, @floatFromInt(wy)) + cursor_y;
                pet_press_active = false;
            }
        }

        if (!menu_visible and !left_pressed and left_prev) {
            if (pet_press_active and chats.len > 0) {
                bubble_idx = random.uintLessThan(usize, chats.len);
                bubble_start_t = c.glfwGetTime();
                bubble_visible = true;

                const text = chats[bubble_idx];
                const font_px: f32 = @floatFromInt(cfg.font_size);
                bubble_text_pad = @max(10.0, font_px * 0.45);
                bubble_line_h = @max(18.0, font_px * 1.18);

                const max_content_w = @min(560.0, @max(220.0, font_px * 14.0));
                const max_units = max_content_w / font_px;
                bubble_line_count = wrapTextLines(text, max_units, &bubble_line_starts, &bubble_line_ends);

                var max_line_units: f32 = 0;
                var li: usize = 0;
                while (li < bubble_line_count) : (li += 1) {
                    const line = text[bubble_line_starts[li]..bubble_line_ends[li]];
                    const units = estimateDisplayUnits(line);
                    if (units > max_line_units) max_line_units = units;
                }

                const text_w_est: c_int = @intFromFloat(max_line_units * font_px + bubble_text_pad * 2);
                const bubble_min_w: c_int = @intFromFloat(font_px * 8.0);
                const bubble_max_w: c_int = 640;
                bubble_w = @max(bubble_min_w, @min(bubble_max_w, text_w_est));
                bubble_h = @intFromFloat(
                    bubble_text_pad * 2 +
                        @as(f32, @floatFromInt(bubble_line_count)) * bubble_line_h +
                        @as(f32, @floatFromInt(if (bubble_line_count > 0) bubble_line_count - 1 else 0)) * (font_px * 0.18),
                );
                if (bubble_h < 56) bubble_h = 56;
                c.glfwSetWindowSize(bubble_window, bubble_w, bubble_h);

                var wx: c_int = 0;
                var wy: c_int = 0;
                c.glfwGetWindowPos(window, &wx, &wy);
                var px: c_int = wx + @divTrunc(sprite_w - bubble_w, 2);
                var py: c_int = wy - bubble_h - 12;
                clampWindowToScreen(bubble_w, bubble_h, &px, &py);
                c.glfwSetWindowPos(bubble_window, px, py);
                c.glfwShowWindow(bubble_window);
            }
            pet_press_active = false;
            drag_active = false;
        }

        var block_drag = false;
        if (menu_visible) {
            var menu_cursor_x: f64 = 0;
            var menu_cursor_y: f64 = 0;
            c.glfwGetCursorPos(menu_window, &menu_cursor_x, &menu_cursor_y);
            const mx: f32 = @floatCast(menu_cursor_x);
            const my: f32 = @floatCast(menu_cursor_y);
            const menu_left_pressed = c.glfwGetMouseButton(menu_window, c.GLFW_MOUSE_BUTTON_LEFT) == c.GLFW_PRESS;

            const item_x: f32 = menu_pad;
            const item_w = menu_wf - menu_pad * 2;
            const header_y: f32 = menu_pad;
            const slider_y: f32 = header_y + ml.menu_header_h + menu_gap;
            const buttons_y = slider_y + menu_slider_h + menu_gap;
            const close_x = menu_wf - menu_pad - close_btn_size;
            const close_y = header_y + (ml.menu_header_h - close_btn_size) * 0.5;

            if (menu_left_pressed and !menu_left_prev) {
                const in_menu = geom.isInRect(mx, my, 0, 0, menu_wf, menu_hf);
                if (in_menu) {
                    block_drag = true;
                    if (geom.isInRect(mx, my, close_x, close_y, close_btn_size, close_btn_size)) {
                        menu_visible = false;
                        slider_dragging = false;
                        menu_drag_active = false;
                        c.glfwHideWindow(menu_window);
                    } else if (geom.isInRect(mx, my, item_x, header_y, item_w, ml.menu_header_h)) {
                        var mwx: c_int = 0;
                        var mwy: c_int = 0;
                        c.glfwGetWindowPos(menu_window, &mwx, &mwy);
                        menu_drag_active = true;
                        menu_drag_window_x = mwx;
                        menu_drag_window_y = mwy;
                        menu_drag_mouse_screen_x = @as(f64, @floatFromInt(mwx)) + menu_cursor_x;
                        menu_drag_mouse_screen_y = @as(f64, @floatFromInt(mwy)) + menu_cursor_y;
                    } else if (geom.isInRect(mx, my, item_x, slider_y, item_w, menu_slider_h)) {
                        slider_dragging = true;
                    } else {
                        var i: usize = 0;
                        while (i < menu_layout.menu_button_count) : (i += 1) {
                            const item_y = buttons_y + @as(f32, @floatFromInt(i)) * (menu_item_h + menu_gap);
                            if (geom.isInRect(mx, my, item_x, item_y, item_w, menu_item_h)) {
                                switch (i) {
                                    0 => c.glfwSetWindowPos(window, @intCast(cfg.window_x), @intCast(cfg.window_y)),
                                    1 => c.glfwSetWindowShouldClose(window, c.GLFW_TRUE),
                                    else => {},
                                }
                                break;
                            }
                        }
                    }
                }
            }

            if (menu_drag_active) {
                block_drag = true;
                var mwx: c_int = 0;
                var mwy: c_int = 0;
                c.glfwGetWindowPos(menu_window, &mwx, &mwy);
                const mouse_screen_x = @as(f64, @floatFromInt(mwx)) + menu_cursor_x;
                const mouse_screen_y = @as(f64, @floatFromInt(mwy)) + menu_cursor_y;
                const dx = mouse_screen_x - menu_drag_mouse_screen_x;
                const dy = mouse_screen_y - menu_drag_mouse_screen_y;
                menu_x = menu_drag_window_x + @as(c_int, @intFromFloat(dx));
                menu_y = menu_drag_window_y + @as(c_int, @intFromFloat(dy));
                clampMenuWindowToScreen(ml.menu_w, ml.menu_h, &menu_x, &menu_y);
                c.glfwSetWindowPos(menu_window, menu_x, menu_y);
            }

            if (slider_dragging) {
                block_drag = true;
                const track_x = item_x + 8;
                const track_w = item_w - 16;
                const t = std.math.clamp((mx - track_x) / track_w, 0.0, 1.0);
                target_scale = 0.1 + t * (1.2 - 0.1);
            }
            if (!menu_left_pressed) {
                slider_dragging = false;
                menu_drag_active = false;
            }
            menu_left_prev = menu_left_pressed;
        }

        if (!left_pressed and !menu_visible) {
            drag_active = false;
        }

        if (drag_active) {
            var wx: c_int = 0;
            var wy: c_int = 0;
            c.glfwGetWindowPos(window, &wx, &wy);
            const mouse_screen_x = @as(f64, @floatFromInt(wx)) + cursor_x;
            const mouse_screen_y = @as(f64, @floatFromInt(wy)) + cursor_y;
            const dx = mouse_screen_x - drag_mouse_screen_x;
            const dy = mouse_screen_y - drag_mouse_screen_y;
            c.glfwSetWindowPos(window, drag_window_x + @as(c_int, @intFromFloat(dx)), drag_window_y + @as(c_int, @intFromFloat(dy)));
        }

        const delta = target_scale - current_scale;
        if (@abs(delta) > 0.0005) {
            applyScale(&current_scale, current_scale + delta * 0.22, image.width, image.height, &sprite_w, &sprite_h, window);
        } else if (current_scale != target_scale) {
            applyScale(&current_scale, target_scale, image.width, image.height, &sprite_w, &sprite_h, window);
        }

        c.glViewport(0, 0, fb_w, fb_h);
        c.glClearColor(0.0, 0.0, 0.0, 0.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glMatrixMode(c.GL_PROJECTION);
        c.glLoadIdentity();
        c.glOrtho(0, @as(f64, @floatFromInt(fb_w)), @as(f64, @floatFromInt(fb_h)), 0, -1, 1);
        c.glMatrixMode(c.GL_MODELVIEW);
        c.glLoadIdentity();
        c.glColor4f(1, 1, 1, 1);

        const draw_x = cfg.offset_x;
        const draw_y = cfg.offset_y;
        const draw_w: f32 = @floatFromInt(sprite_w);
        const draw_h: f32 = @floatFromInt(sprite_h);
        c.glBindTexture(c.GL_TEXTURE_2D, tex);
        c.glBegin(c.GL_QUADS);
        c.glTexCoord2f(0, 0);
        c.glVertex2f(draw_x, draw_y);
        c.glTexCoord2f(1, 0);
        c.glVertex2f(draw_x + draw_w, draw_y);
        c.glTexCoord2f(1, 1);
        c.glVertex2f(draw_x + draw_w, draw_y + draw_h);
        c.glTexCoord2f(0, 1);
        c.glVertex2f(draw_x, draw_y + draw_h);
        c.glEnd();

        if (menu_visible) {
            c.glfwMakeContextCurrent(menu_window);
            c.glViewport(0, 0, ml.menu_w, ml.menu_h);
            c.glClearColor(0.08, 0.08, 0.08, 0.95);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
            c.glMatrixMode(c.GL_PROJECTION);
            c.glLoadIdentity();
            c.glOrtho(0, @as(f64, @floatFromInt(ml.menu_w)), @as(f64, @floatFromInt(ml.menu_h)), 0, -1, 1);
            c.glMatrixMode(c.GL_MODELVIEW);
            c.glLoadIdentity();
            c.glDisable(c.GL_TEXTURE_2D);
            draw.drawSolidRect(0, 0, menu_wf, menu_hf, 0.08, 0.08, 0.08, 0.92);

            var menu_cursor_x: f64 = 0;
            var menu_cursor_y: f64 = 0;
            c.glfwGetCursorPos(menu_window, &menu_cursor_x, &menu_cursor_y);
            const mx: f32 = @floatCast(menu_cursor_x);
            const my: f32 = @floatCast(menu_cursor_y);

            const item_x: f32 = menu_pad;
            const item_w = menu_wf - menu_pad * 2;
            const header_y: f32 = menu_pad;
            const slider_y: f32 = header_y + ml.menu_header_h + menu_gap;
            const buttons_y = slider_y + menu_slider_h + menu_gap;
            const close_x = menu_wf - menu_pad - close_btn_size;
            const close_y = header_y + (ml.menu_header_h - close_btn_size) * 0.5;
            const slider_hovered = geom.isInRect(mx, my, item_x, slider_y, item_w, menu_slider_h);
            const close_hovered = geom.isInRect(mx, my, close_x, close_y, close_btn_size, close_btn_size);
            const item_text_pad_x: f32 = 8;
            const item_text_top_pad: f32 = @floatFromInt(cfg.item_text_top_pad);

            if (text_ready) ft_text.drawText(item_x, header_y + 2, "MENU", 1.0, 0.9, 0.9, 0.94, 1.0);
            drawMenuSliderComponent(text_ready, item_x, item_w, slider_y, menu_slider_h, target_scale, item_text_top_pad, slider_hovered);
            draw.drawSolidRect(close_x, close_y, close_btn_size, close_btn_size, if (close_hovered) 0.45 else 0.28, 0.15, 0.18, 0.98);
            if (text_ready) ft_text.drawText(close_x + 4, close_y + 2, "X", 1.0, 0.98, 0.95, 0.95, 1.0);

            var i: usize = 0;
            while (i < menu_layout.menu_button_count) : (i += 1) {
                const item_y = buttons_y + @as(f32, @floatFromInt(i)) * (menu_item_h + menu_gap);
                const hovered = geom.isInRect(mx, my, item_x, item_y, item_w, menu_item_h);
                var label_buf: [64]u8 = undefined;
                const fitted = fitLabel(menu_layout.menu_button_labels[i], item_w - item_text_pad_x * 2, ml.menu_text_px, label_buf[0..]);
                if (i == menu_layout.menu_button_count - 1) {
                    drawMenuButtonComponent(text_ready, item_x, item_y, item_w, menu_item_h, fitted, 0.2, 0.14, 0.16, hovered, item_text_pad_x, item_text_top_pad);
                } else {
                    drawMenuButtonComponent(text_ready, item_x, item_y, item_w, menu_item_h, fitted, 0.16, 0.16, 0.2, hovered, item_text_pad_x, item_text_top_pad);
                }
            }
            c.glEnable(c.GL_TEXTURE_2D);
            c.glfwSwapBuffers(menu_window);
            c.glfwMakeContextCurrent(window);
        }

        if (bubble_visible and chats.len > 0) {
            const elapsed = c.glfwGetTime() - bubble_start_t;
            var alpha: f32 = 1.0;
            if (elapsed > bubble_show_s) {
                const fade_t = @as(f32, @floatCast((elapsed - bubble_show_s) / bubble_fade_s));
                alpha = @max(0.0, 1.0 - fade_t);
            }
            if (alpha <= 0.0) {
                bubble_visible = false;
                c.glfwHideWindow(bubble_window);
            } else {
                c.glfwMakeContextCurrent(bubble_window);
                c.glViewport(0, 0, bubble_w, bubble_h);
                c.glClearColor(0.0, 0.0, 0.0, 0.0);
                c.glClear(c.GL_COLOR_BUFFER_BIT);
                c.glMatrixMode(c.GL_PROJECTION);
                c.glLoadIdentity();
                c.glOrtho(0, @as(f64, @floatFromInt(bubble_w)), @as(f64, @floatFromInt(bubble_h)), 0, -1, 1);
                c.glMatrixMode(c.GL_MODELVIEW);
                c.glLoadIdentity();
                c.glDisable(c.GL_TEXTURE_2D);
                draw.drawSolidRect(0, 0, @floatFromInt(bubble_w), @floatFromInt(bubble_h), 0.1, 0.1, 0.12, 0.82 * alpha);
                if (text_ready) {
                    const text = chats[bubble_idx];
                    var li: usize = 0;
                    while (li < bubble_line_count) : (li += 1) {
                        const line = text[bubble_line_starts[li]..bubble_line_ends[li]];
                        const y = bubble_text_pad * 0.5 + @as(f32, @floatFromInt(li)) * (bubble_line_h + @as(f32, @floatFromInt(cfg.font_size)) * 0.18);
                        ft_text.drawText(bubble_text_pad, y, line, 1.0, 0.95, 0.95, 0.98, alpha);
                    }
                }
                c.glEnable(c.GL_TEXTURE_2D);
                c.glfwSwapBuffers(bubble_window);
                c.glfwMakeContextCurrent(window);
            }
        }

        left_prev = left_pressed;
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}
