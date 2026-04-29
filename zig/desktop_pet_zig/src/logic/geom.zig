pub fn isInRect(px: f32, py: f32, x: f32, y: f32, w: f32, h: f32) bool {
    return px >= x and px <= x + w and py >= y and py <= y + h;
}
