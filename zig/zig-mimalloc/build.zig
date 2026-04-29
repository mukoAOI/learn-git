const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_static = b.option(bool, "build_static", "Build static mimalloc library") orelse true;
    const build_shared = b.option(bool, "build_shared", "Build shared mimalloc library") orelse true;

    // ReleaseFast：与上游 release 包一致，默认本机指令集 + SIMD 位图路径
    const mi_native_tune = b.option(
        bool,
        "mi_native_tune",
        "Use -march=native -mtune=native for mimalloc (portable artifacts: pass -Dmi_native_tune=false)",
    ) orelse (optimize == .ReleaseFast);

    const mi_opt_simd = b.option(
        bool,
        "mi_opt_simd",
        "Define MI_OPT_SIMD=1 (SIMD bitmap fast paths when __AVX2__ / arm neon, matches upstream -DMI_OPT_SIMD=ON)",
    ) orelse true;

    const mi_lto = b.option(bool, "mi_lto", "Enable LTO for mimalloc artifacts") orelse true;

    // Windows：与上游 CI 一致，默认走直接 TLS 快路径（进程 TlsAlloc 总数需 < 64）
    const win_direct_tls = b.option(
        bool,
        "mi_win_direct_tls",
        "MI_WIN_DIRECT_TLS: faster Windows TLS fast-path (disable if you hit TLS slot issues)",
    ) orelse (target.result.os.tag == .windows);

    const mimalloc_dep = b.dependency("mimalloc", .{
        .target = target,
        .optimize = optimize,
    });
    if (!build_static and !build_shared) {
        @panic("At least one of -Dbuild_static or -Dbuild_shared must be true");
    }

    var static_lib: ?*std.Build.Step.Compile = null;
    var shared_lib: ?*std.Build.Step.Compile = null;

    if (build_static) {
        static_lib = addMimallocLibrary(b, mimalloc_dep, target, optimize, .static, "mimalloc", .{
            .win_direct_tls = win_direct_tls,
            .mi_native_tune = mi_native_tune,
            .mi_opt_simd = mi_opt_simd,
            .mi_lto = mi_lto,
        });
        b.installArtifact(static_lib.?);
    }
    if (build_shared) {
        shared_lib = addMimallocLibrary(b, mimalloc_dep, target, optimize, .dynamic, "mimalloc_shared", .{
            .win_direct_tls = win_direct_tls,
            .mi_native_tune = mi_native_tune,
            .mi_opt_simd = mi_opt_simd,
            .mi_lto = mi_lto,
        });
        b.installArtifact(shared_lib.?);
    }

    const mimalloc_mod = b.addModule("mimalloc", .{
        .root_source_file = b.path("src/mimalloc.zig"),
        .target = target,
        .optimize = optimize,
    });
    mimalloc_mod.addIncludePath(mimalloc_dep.path("include"));

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/mimalloc.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addIncludePath(mimalloc_dep.path("include"));

    const tests = b.addTest(.{
        .root_module = test_module,
    });
    tests.root_module.linkLibrary(static_lib orelse shared_lib.?);

    const test_step = b.step("test", "Run mimalloc wrapper tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_module.addImport("mimalloc", mimalloc_mod);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_module,
    });
    bench_exe.root_module.linkLibrary(static_lib orelse shared_lib.?);
    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run allocator benchmark");
    bench_step.dependOn(&run_bench.step);
}

const MimallocCompileOpts = struct {
    win_direct_tls: bool,
    mi_native_tune: bool,
    mi_opt_simd: bool,
    mi_lto: bool,
};

fn addMimallocLibrary(
    b: *std.Build,
    mimalloc_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    name: []const u8,
    opts: MimallocCompileOpts,
) *std.Build.Step.Compile {
    const c_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_module.addIncludePath(mimalloc_dep.path("include"));

    const base_define_count: usize = 15;
    const native_extra: usize = if (opts.mi_native_tune) 2 else 0;
    const flags = b.allocator.alloc([]const u8, base_define_count + native_extra) catch @panic("OOM");
    defer b.allocator.free(flags);

    var f: usize = 0;
    flags[f] = "-std=c11";
    f += 1;
    flags[f] = "-D__DATE__=\"redacted\"";
    f += 1;
    flags[f] = "-D__TIME__=\"00:00:00\"";
    f += 1;
    flags[f] = "-DMI_BUILD_RELEASE=1";
    f += 1;
    flags[f] = "-DMI_DEBUG=0";
    f += 1;
    flags[f] = "-DMI_SECURE=0";
    f += 1;
    flags[f] = "-DMI_GUARDED=0";
    f += 1;
    flags[f] = "-DMI_PADDING=0";
    f += 1;
    flags[f] = "-DMI_SHOW_ERRORS=0";
    f += 1;
    flags[f] = "-DMI_TRACK_VALGRIND=0";
    f += 1;
    flags[f] = "-DMI_TRACK_ASAN=0";
    f += 1;
    flags[f] = "-DMI_TRACK_ETW=0";
    f += 1;
    flags[f] = "-DMI_OVERRIDE=0";
    f += 1;
    flags[f] = if (opts.win_direct_tls) "-DMI_WIN_DIRECT_TLS=1" else "-DMI_WIN_DIRECT_TLS=0";
    f += 1;
    flags[f] = if (opts.mi_opt_simd) "-DMI_OPT_SIMD=1" else "-DMI_OPT_SIMD=0";
    f += 1;

    if (opts.mi_native_tune) {
        flags[f] = "-march=native";
        f += 1;
        flags[f] = "-mtune=native";
        f += 1;
    }
    std.debug.assert(f == flags.len);

    c_module.addCSourceFile(.{
        .file = mimalloc_dep.path("src/static.c"),
        .flags = flags,
    });

    const lib = b.addLibrary(.{
        .linkage = linkage,
        .name = name,
        .root_module = c_module,
    });
    if (opts.mi_lto) lib.lto = .full;
    return lib;
}
