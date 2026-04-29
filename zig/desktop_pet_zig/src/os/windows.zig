const builtin = @import("builtin");
const bindings = @import("../c/bindings.zig");
const c = bindings.c;

pub fn applyWindowIcon(window: ?*c.GLFWwindow) void {
    if (builtin.os.tag != .windows) return;

    const hwnd = c.glfwGetWin32Window(window);
    const icon_big = c.LoadImageA(
        null,
        "asset/doro.ico",
        c.IMAGE_ICON,
        64,
        64,
        c.LR_LOADFROMFILE,
    );
    const icon_small = c.LoadImageA(
        null,
        "asset/doro.ico",
        c.IMAGE_ICON,
        32,
        32,
        c.LR_LOADFROMFILE,
    );
    if (icon_big != null) {
        const icon_big_param: c.LPARAM = @bitCast(@intFromPtr(icon_big));
        _ = c.SendMessageA(hwnd, c.WM_SETICON, c.ICON_BIG, icon_big_param);
    }
    if (icon_small != null) {
        const icon_small_param: c.LPARAM = @bitCast(@intFromPtr(icon_small));
        _ = c.SendMessageA(hwnd, c.WM_SETICON, c.ICON_SMALL, icon_small_param);
    }
}
