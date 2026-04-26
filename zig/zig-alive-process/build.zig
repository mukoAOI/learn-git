const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("alive_progress", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .unwind_tables = releaseUnwindTables(optimize),
    });

    addExample(b, mod, target, optimize, "basic", "Known-total progress");
    addExample(b, mod, target, optimize, "unknown", "Unknown-total progress");
    addExample(b, mod, target, optimize, "manual", "Manual percentage progress");
    addExample(b, mod, target, optimize, "skipped", "Resume progress with skipped items");
    addExample(b, mod, target, optimize, "multitask", "Multiple workers sharing one progress bar");
    addExample(b, mod, target, optimize, "arrow", "Progress bar rendered as =====>");
    addExample(b, mod, target, optimize, "easy", "Higher-level tqdm-style helpers");
    addExample(b, mod, target, optimize, "until_done", "Heartbeat progress for one opaque API call");

    const root_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_root_tests = b.addRunArtifact(root_tests);

    const calibration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/calibration.zig"),
            .target = target,
            .optimize = optimize,
            .unwind_tables = releaseUnwindTables(optimize),
        }),
    });
    const run_calibration_tests = b.addRunArtifact(calibration_tests);

    const timing_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/timing.zig"),
            .target = target,
            .optimize = optimize,
            .unwind_tables = releaseUnwindTables(optimize),
        }),
    });
    const run_timing_tests = b.addRunArtifact(timing_tests);

    const render_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/render.zig"),
            .target = target,
            .optimize = optimize,
            .unwind_tables = releaseUnwindTables(optimize),
        }),
    });
    const run_render_tests = b.addRunArtifact(render_tests);

    const style_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/style.zig"),
            .target = target,
            .optimize = optimize,
            .unwind_tables = releaseUnwindTables(optimize),
        }),
    });
    const run_style_tests = b.addRunArtifact(style_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_calibration_tests.step);
    test_step.dependOn(&run_timing_tests.step);
    test_step.dependOn(&run_render_tests.step);
    test_step.dependOn(&run_style_tests.step);
}

fn addExample(
    b: *std.Build,
    alive_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    description: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = "alive-example-" ++ name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .unwind_tables = releaseUnwindTables(optimize),
            .imports = &.{
                .{ .name = "alive_progress", .module = alive_mod },
            },
        }),
    });

    const run = b.addRunArtifact(exe);
    const step = b.step("example-" ++ name, description);
    step.dependOn(&run.step);
}

fn releaseUnwindTables(optimize: std.builtin.OptimizeMode) ?std.builtin.UnwindTables {
    return switch (optimize) {
        .Debug => null,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .none,
    };
}
