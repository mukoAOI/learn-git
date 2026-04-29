extern fn ft_text_init(font_path: [*:0]const u8, pixel_height: c_int) c_int;
extern fn ft_text_deinit() void;
extern fn ft_draw_text(
    x: f32,
    y: f32,
    text: [*]const u8,
    text_len: c_int,
    scale: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) void;

pub fn init(font_path: [:0]const u8, pixel_height: i32) bool {
    return ft_text_init(font_path.ptr, pixel_height) != 0;
}

pub fn deinit() void {
    ft_text_deinit();
}

pub fn drawText(x: f32, y: f32, text: []const u8, scale: f32, r: f32, g: f32, b: f32, a: f32) void {
    ft_draw_text(x, y, text.ptr, @intCast(text.len), scale, r, g, b, a);
}
