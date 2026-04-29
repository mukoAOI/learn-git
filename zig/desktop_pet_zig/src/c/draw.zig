const bindings = @import("bindings.zig");
const c = bindings.c;

pub fn drawSolidRect(x: f32, y: f32, w: f32, h: f32, r: f32, g: f32, b: f32, a: f32) void {
    c.glColor4f(r, g, b, a);
    c.glBegin(c.GL_QUADS);
    c.glVertex2f(x, y);
    c.glVertex2f(x + w, y);
    c.glVertex2f(x + w, y + h);
    c.glVertex2f(x, y + h);
    c.glEnd();
}
