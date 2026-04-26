//! Multiple workers sharing one progress bar.
//!
//! Run with:
//!   zig build example-multitask

const std = @import("std");
const alive = @import("alive_progress");

const worker_count = 4;
const units_per_worker = 50;

const Worker = struct {
    id: usize,
    bar: *alive.AliveBar,
    delay_ms: u64,
};

pub fn main(init: std.process.Init) !void {
    const total = worker_count * units_per_worker;
    const bar = try alive.AliveBar.create(init.gpa, init.io, total, .{
        .title = "workers",
        .length = 36,
        .refresh_ms = 180,
    });
    defer bar.destroy();

    var workers: [worker_count]Worker = undefined;
    var threads: [worker_count]std.Thread = undefined;

    for (&workers, 0..) |*worker_ctx, i| {
        worker_ctx.* = .{
            .id = i + 1,
            .bar = bar,
            .delay_ms = 12 + i * 7,
        };
        threads[i] = try std.Thread.spawn(.{}, workerMain, .{worker_ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    try bar.setText("all workers finished");
    try bar.finish();
}

fn workerMain(ctx: *Worker) void {
    var i: usize = 0;
    while (i < units_per_worker) : (i += 1) {
        alive.platform.sleepNs(ctx.delay_ms * std.time.ns_per_ms);

        if (i % 15 == 0) {
            var text_buf: [64]u8 = undefined;
            const text = std.fmt.bufPrint(
                &text_buf,
                "worker {d}: {d}/{d}",
                .{ ctx.id, i + 1, units_per_worker },
            ) catch "";
            ctx.bar.setText(text) catch {};
        }

        ctx.bar.tick(1);
    }
}
