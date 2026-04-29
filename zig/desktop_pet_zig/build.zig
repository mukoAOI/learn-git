const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "tets",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            },
        }),
    });

    exe.root_module.link_libc = true;
    const os_tag = target.result.os.tag;
    switch (os_tag) {
        .windows => {
            exe.subsystem = .windows;
            exe.root_module.addIncludePath(b.path("extern/glfw/include"));
            exe.root_module.addLibraryPath(b.path("extern/glfw/lib"));
            exe.root_module.addIncludePath(b.path("extern/freetype/include/freetype2"));
            exe.root_module.addIncludePath(b.path("src/c"));
            exe.root_module.addLibraryPath(b.path("extern/freetype/lib"));
            exe.root_module.linkSystemLibrary("glfw3dll", .{});
            exe.root_module.linkSystemLibrary("freetype", .{});
            exe.root_module.linkSystemLibrary("opengl32", .{});
            exe.root_module.linkSystemLibrary("gdi32", .{});
            exe.root_module.linkSystemLibrary("user32", .{});
            exe.root_module.linkSystemLibrary("shell32", .{});
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/c/freetype_text.c"),
                .flags = &.{},
            });
        },
        .macos => {
            exe.root_module.linkSystemLibrary("glfw", .{});
            exe.root_module.linkFramework("OpenGL", .{});
            exe.root_module.linkFramework("Cocoa", .{});
            exe.root_module.linkFramework("IOKit", .{});
            exe.root_module.linkFramework("CoreVideo", .{});
        },
        else => {
            exe.root_module.linkSystemLibrary("glfw", .{});
            exe.root_module.linkSystemLibrary("GL", .{});
            exe.root_module.linkSystemLibrary("m", .{});
            exe.root_module.linkSystemLibrary("dl", .{});
            exe.root_module.linkSystemLibrary("pthread", .{});
        },
    }

    b.installArtifact(exe);
    const install_config = b.addInstallBinFile(b.path("config/pet.conf"), "config/pet.conf");
    b.getInstallStep().dependOn(&install_config.step);
    const install_asset_dir = b.addInstallDirectory(.{
        .source_dir = b.path("asset"),
        .install_dir = .bin,
        .install_subdir = "asset",
    });
    b.getInstallStep().dependOn(&install_asset_dir.step);
    if (os_tag == .windows) {
        const install_glfw_dll = b.addInstallBinFile(b.path("extern/glfw/bin/glfw3.dll"), "glfw3.dll");
        b.getInstallStep().dependOn(&install_glfw_dll.step);
        const install_freetype_dll = b.addInstallBinFile(b.path("extern/freetype/bin/freetype.dll"), "freetype.dll");
        b.getInstallStep().dependOn(&install_freetype_dll.step);
    }

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
