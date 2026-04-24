const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const default_optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (Debug, ReleaseFast, ReleaseSafe, ReleaseSmall)") orelse default_optimize;
    const install_dir = b.option([]const u8, "install-dir", "Install subdirectory under prefix (contains exe and data)") orelse "pokeget-zig";

    const exe = b.addExecutable(.{
        .name = "pokeget-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Release: keep symbols stripped and enable LTO where linker is stable.
    // On Windows, full/thin LTO may fail with `_tls_index` in lld-link.
    // Prefer target query when provided, then fall back to resolved target.
    const target_os = target.query.os_tag orelse target.result.os.tag;
    const is_windows_target = target_os == .windows;
    const is_windows_host = @import("builtin").os.tag == .windows;
    switch (optimize) {
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => {
            exe.root_module.strip = true;
            if (!is_windows_target and !is_windows_host) exe.lto = .full;
        },
        .Debug => {},
    }

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = install_dir } },
    });
    b.getInstallStep().dependOn(&install_exe.step);

    const install_data = b.addInstallDirectory(.{
        .source_dir = b.path("data"),
        .install_dir = .{ .custom = install_dir },
        .install_subdir = "data",
    });
    b.getInstallStep().dependOn(&install_data.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run pokeget-zig");
    run_step.dependOn(&run_cmd.step);
}
