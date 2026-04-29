const std = @import("std");
const mimalloc = @import("mimalloc");
const builtin = @import("builtin");

const Case = struct {
    name: []const u8,
    allocator: std.mem.Allocator,
};

const alloc_count = 20000;
const rounds = 100;
const max_size = 2048;
const min_threads = 4;
const max_threads = 8;

pub fn main() !void {
    const concurrent_threads = detectThreadCount();
    std.debug.print(
        "allocator bench: alloc_count={d}, rounds={d}, max_size={d}, single=1, concurrent={d}\n",
        .{ alloc_count, rounds, max_size, concurrent_threads },
    );

    const cases = [_]Case{
        .{ .name = "mimalloc", .allocator = mimalloc.allocator },
        .{ .name = "zig_smp_allocator", .allocator = std.heap.smp_allocator },
        .{ .name = "zig_c_allocator", .allocator = std.heap.c_allocator },
    };

    for (cases) |case_item| {
        const single_ns = try runCaseConcurrent(case_item.allocator, 1);
        const single_avg_ns = single_ns / rounds;
        const concurrent_ns = try runCaseConcurrent(case_item.allocator, concurrent_threads);
        const concurrent_avg_ns = concurrent_ns / (rounds * concurrent_threads);
        std.debug.print(
            "{s:>18}: single_avg={d} ns, concurrent_avg={d} ns\n",
            .{ case_item.name, single_avg_ns, concurrent_avg_ns },
        );
    }
}

fn detectThreadCount() usize {
    const cpu_count = std.Thread.getCpuCount() catch 6;
    return @min(max_threads, @max(min_threads, cpu_count));
}

fn runCaseConcurrent(allocator: std.mem.Allocator, thread_count: usize) !u64 {
    const infra_alloc = std.heap.page_allocator;
    var results = try infra_alloc.alloc(u64, thread_count);
    defer infra_alloc.free(results);
    @memset(results, 0);

    var workers = try infra_alloc.alloc(std.Thread, thread_count);
    defer infra_alloc.free(workers);

    var contexts = try infra_alloc.alloc(WorkerCtx, thread_count);
    defer infra_alloc.free(contexts);

    for (0..thread_count) |i| {
        contexts[i] = .{
            .allocator = allocator,
            .seed = 0x4d495f4d414c4c4f + i * 0x9e3779b97f4a7c15,
            .result_ns = &results[i],
        };
        workers[i] = try std.Thread.spawn(.{}, workerMain, .{&contexts[i]});
    }
    for (workers) |worker| worker.join();

    var total_ns: u64 = 0;
    for (results) |ns| total_ns += ns;
    return total_ns;
}

const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    result_ns: *u64,
};

fn workerMain(ctx: *WorkerCtx) void {
    ctx.result_ns.* = runCase(ctx.allocator, ctx.seed) catch 0;
}

fn runCase(allocator: std.mem.Allocator, seed: u64) !u64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var ptrs = try allocator.alloc([]u8, alloc_count);
    defer allocator.free(ptrs);

    var sizes = try allocator.alloc(usize, alloc_count);
    defer allocator.free(sizes);

    var free_order = try allocator.alloc(usize, alloc_count);
    defer allocator.free(free_order);
    for (0..alloc_count) |i| free_order[i] = i;

    var timer = try BenchTimer.start();
    var r: usize = 0;
    while (r < rounds) : (r += 1) {
        // Fisher-Yates shuffle to randomize free order every round.
        var shuffle_i: usize = alloc_count - 1;
        while (shuffle_i > 0) : (shuffle_i -= 1) {
            const j = random.uintLessThan(usize, shuffle_i + 1);
            std.mem.swap(usize, &free_order[shuffle_i], &free_order[j]);
        }

        for (0..alloc_count) |i| {
            const sz = random.uintLessThan(usize, max_size) + 1;
            sizes[i] = sz;
            ptrs[i] = try allocator.alloc(u8, sz);
            ptrs[i][0] = @intCast(sz & 0xff);
        }

        for (0..alloc_count) |i| {
            const idx = free_order[i];
            std.debug.assert(ptrs[idx].len == sizes[idx]);
            allocator.free(ptrs[idx]);
        }
    }

    return timer.read();
}

const BenchTimer = struct {
    start_ns: u64,

    fn start() !BenchTimer {
        return .{ .start_ns = try monotonicNowNs() };
    }

    fn read(self: BenchTimer) u64 {
        const now = monotonicNowNs() catch return 0;
        // monotonic 失败时不能 return 0 再参与减法，否则 0 - start_ns 会无符号下溢。
        return now -| self.start_ns;
    }
};

fn monotonicNowNs() !u64 {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        var qpc: windows.LARGE_INTEGER = undefined;
        var qpf: windows.LARGE_INTEGER = undefined;
        if (!windows.ntdll.RtlQueryPerformanceCounter(&qpc).toBool()) return error.ClockUnavailable;
        if (!windows.ntdll.RtlQueryPerformanceFrequency(&qpf).toBool()) return error.ClockUnavailable;
        const ticks: u64 = @bitCast(qpc);
        const freq: u64 = @bitCast(qpf);
        return ticks * std.time.ns_per_s / freq;
    }
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts))) {
        .SUCCESS => {},
        else => return error.ClockUnavailable,
    }
    const sec: u64 = @intCast(ts.sec);
    const nsec: u64 = @intCast(ts.nsec);
    return sec * std.time.ns_per_s + nsec;
}
