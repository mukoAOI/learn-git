pub const menu_button_labels = [_][]const u8{
    "RESET POS",
    "QUIT",
};

pub const menu_button_count = menu_button_labels.len;
pub const menu_text_scale_px: f32 = 1.0;
pub const menu_header_h_min_px = 22;
pub const menu_close_btn_size_px = 20;

pub const Layout = struct {
    menu_w: i32,
    menu_h: i32,
    menu_wf: f32,
    menu_hf: f32,
    menu_pad: f32,
    menu_gap: f32,
    menu_slider_h: f32,
    menu_item_h: f32,
    menu_header_h: f32,
    menu_text_px: f32,
};

pub fn compute(font_size: i32, padding: i32, gap: i32, min_width: i32, max_width: i32) Layout {
    const fs: f32 = @floatFromInt(font_size);
    const padf: f32 = @floatFromInt(padding);
    const gapf: f32 = @floatFromInt(gap);

    var max_label_chars: usize = 0;
    for (menu_button_labels) |label| {
        if (label.len > max_label_chars) max_label_chars = label.len;
    }

    const estimated_label_w = @as(f32, @floatFromInt(max_label_chars)) * fs * 0.62 + 20;
    const slider_h = fs * 2.2 + 10;
    const item_h = fs * 1.5 + 10;
    const header_h = @max(@as(f32, @floatFromInt(menu_header_h_min_px)), fs + 8);
    const close_btn = @as(f32, @floatFromInt(menu_close_btn_size_px));
    const content_w = @max(estimated_label_w + 16, close_btn + fs * 3 + 20);
    var menu_w: i32 = @intFromFloat(@as(f32, @floatFromInt(padding * 2)) + @max(content_w, @as(f32, @floatFromInt(min_width))));
    if (menu_w > max_width) menu_w = max_width;
    var menu_h: i32 = @intFromFloat(
        @as(f32, @floatFromInt(padding * 2)) +
            header_h + gapf +
            slider_h + gapf +
            @as(f32, @floatFromInt(menu_button_count)) * item_h +
            @as(f32, @floatFromInt(menu_button_count - 1)) * gapf,
    );
    if (menu_w < 160) menu_w = 160;
    if (menu_h < 120) menu_h = 120;

    return .{
        .menu_w = menu_w,
        .menu_h = menu_h,
        .menu_wf = @floatFromInt(menu_w),
        .menu_hf = @floatFromInt(menu_h),
        .menu_pad = padf,
        .menu_gap = gapf,
        .menu_slider_h = slider_h,
        .menu_item_h = item_h,
        .menu_header_h = header_h,
        .menu_text_px = fs,
    };
}
