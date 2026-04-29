pub fn clampScale(value: f32) f32 {
    if (value < 0.1) return 0.1;
    if (value > 1.2) return 1.2;
    return value;
}

pub fn calcSpriteSize(image_w: usize, image_h: usize, scale: f32) struct { w: i32, h: i32 } {
    var w: i32 = @intFromFloat(@as(f32, @floatFromInt(image_w)) * scale);
    var h: i32 = @intFromFloat(@as(f32, @floatFromInt(image_h)) * scale);
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    return .{ .w = w, .h = h };
}
