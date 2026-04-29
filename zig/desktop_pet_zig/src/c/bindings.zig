const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("GLFW/glfw3.h");
    if (builtin.os.tag == .windows) {
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
        @cInclude("windows.h");
        @cInclude("GLFW/glfw3native.h");
    }
    if (builtin.os.tag == .macos) {
        @cInclude("OpenGL/gl.h");
    } else {
        @cInclude("GL/gl.h");
    }
});
