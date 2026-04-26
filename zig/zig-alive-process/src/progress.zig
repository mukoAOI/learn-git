//! Core alive-style progress bar (Zig port subset of Python alive-progress).

const std = @import("std");
const calibration = @import("calibration.zig");
const platform = @import("platform.zig");
const style_mod = @import("style.zig");
const timing = @import("timing.zig");
const terminal = @import("terminal.zig");
const render = @import("render.zig");

pub const max_title_len = 160;
pub const max_text_len = 256;
pub const max_frame_len = 512;

pub const Config = struct {
    length: u32 = 40,
    max_cols: u32 = 120,
    style: style_mod.ProgressStyle = style_mod.ProgressStyle.classic(),
    calibrate: f64 = 1_000_000.0,
    /// Minimum milliseconds between animation frames. Set to 0 for fully dynamic FPS.
    refresh_ms: u64 = 120,
    force_tty: ?bool = null,
    disable: bool = false,
    title: []const u8 = "",
    receipt: bool = true,
    manual: bool = false,
};

fn fixedWriter(buf: []u8) std.Io.Writer {
    return .{
        .vtable = &.{
            .drain = std.Io.Writer.fixedDrain,
            .flush = std.Io.Writer.noopFlush,
            .rebase = std.Io.Writer.failingRebase,
        },
        .buffer = buf,
        .end = 0,
    };
}

fn writeProgressBar(
    w: *std.Io.Writer,
    length: u32,
    total: ?u64,
    manual: bool,
    fraction: f64,
    phase: u32,
    spec: style_mod.BarSpec,
) !void {
    const state: render.BarState = if (total == null and !manual)
        .{ .unknown = phase }
    else
        .{ .known = std.math.clamp(fraction, 0, 1) };

    try render.writeBar(w, length, state, spec);
}

pub const AliveBar = struct {
    allocator: std.mem.Allocator,
    cfg: Config,
    total: ?u64,
    manual: bool,

    /// Simple lock (avoids `Io.Mutex` + `testing.io` futex issues in unit tests).
    spin: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread,

    running: std.atomic.Value(bool),
    done: std.atomic.Value(bool),

    has_start_ts: bool,
    start_ns: i128,
    count: i64,
    processed: i64,
    percent: f64,
    tick_frames: std.atomic.Value(u32),

    rate_smooth: timing.exponentialSmoothing(f64, 0.3),
    eta_smooth: timing.exponentialSmoothing(f64, 0.5),

    title_buf: [max_title_len]u8,
    title_len: usize,
    text_buf: [max_text_len]u8,
    text_len: usize,

    interactive: bool,
    previous_frame: [max_frame_len]u8,
    previous_frame_len: usize,

    fn logicTotal(self: *AliveBar) f64 {
        if (self.total) |t| return @floatFromInt(t);
        return 1.0;
    }

    fn primeStart(self: *AliveBar) void {
        if (self.has_start_ts) return;
        self.start_ns = platform.nowNs();
        self.has_start_ts = true;
    }

    fn elapsedSeconds(self: *AliveBar) f64 {
        if (!self.has_start_ts) return 0;
        const elapsed_ns = @max(platform.nowNs() - self.start_ns, 0);
        return @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    }

    fn writeOut(self: *AliveBar, bytes: []const u8) !void {
        _ = self;
        try platform.writeStdout(bytes);
    }

    fn writeBufferedFrame(self: *AliveBar, frame: []const u8) !void {
        const frame_len = @min(frame.len, self.previous_frame.len);
        const visible_frame = frame[0..frame_len];
        if (std.mem.eql(u8, self.previous_frame[0..self.previous_frame_len], visible_frame)) return;

        var out: [max_frame_len * 2 + 1]u8 = undefined;
        var len: usize = 0;

        out[len] = '\r';
        len += 1;

        @memcpy(out[len..][0..frame_len], visible_frame);
        len += frame_len;

        // If the new frame is shorter, overwrite the tail with spaces instead of clearing the
        // whole line. This avoids the visible blanking phase caused by "\x1b[K".
        if (self.previous_frame_len > frame_len) {
            const pad_len = @min(self.previous_frame_len - frame_len, out.len - len);
            @memset(out[len..][0..pad_len], ' ');
            len += pad_len;
        }

        try self.writeOut(out[0..len]);

        @memcpy(self.previous_frame[0..frame_len], visible_frame);
        self.previous_frame_len = frame_len;
    }

    fn acquire(self: *AliveBar) void {
        while (self.spin.cmpxchgStrong(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn release(self: *AliveBar) void {
        self.spin.store(false, .release);
    }

    fn setTitleUnlocked(self: *AliveBar, title: []const u8) !void {
        if (title.len > self.title_buf.len) return error.TitleTooLong;
        @memcpy(self.title_buf[0..title.len], title);
        self.title_len = title.len;
    }

    fn setTextUnlocked(self: *AliveBar, text: []const u8) !void {
        if (text.len > self.text_buf.len) return error.TextTooLong;
        @memcpy(self.text_buf[0..text.len], text);
        self.text_len = text.len;
    }

    pub fn init(allocator: std.mem.Allocator, io: std.Io, total_opt: ?u64, cfg: Config) !AliveBar {
        var effective_cfg = cfg;
        effective_cfg.length = @max(1, cfg.length);

        const interactive = !effective_cfg.disable and
            (effective_cfg.force_tty orelse terminal.isStdoutTty(io));

        var self: AliveBar = undefined;
        self.allocator = allocator;
        self.cfg = effective_cfg;
        self.total = total_opt;
        self.manual = cfg.manual;
        self.spin = std.atomic.Value(bool).init(false);
        self.thread = null;
        self.running = std.atomic.Value(bool).init(false);
        self.done = std.atomic.Value(bool).init(false);
        self.has_start_ts = false;
        self.start_ns = 0;
        self.count = 0;
        self.processed = 0;
        self.percent = 0;
        self.tick_frames = std.atomic.Value(u32).init(0);
        self.rate_smooth = .{};
        self.eta_smooth = .{};
        self.title_buf = undefined;
        self.title_len = 0;
        try self.setTitleUnlocked(cfg.title);
        self.text_buf = undefined;
        self.text_len = 0;
        self.interactive = interactive;
        self.previous_frame = undefined;
        self.previous_frame_len = 0;

        return self;
    }

    /// Heap-allocating convenience constructor.
    ///
    /// Use this when you want Python-like "start immediately" behavior. Stack users should call
    /// `init()`, assign to a stable variable, then call `start()`.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, total_opt: ?u64, cfg: Config) !*AliveBar {
        const bar = try allocator.create(AliveBar);
        errdefer allocator.destroy(bar);

        bar.* = try AliveBar.init(allocator, io, total_opt, cfg);
        errdefer bar.deinit();

        try bar.start();
        return bar;
    }

    pub fn destroy(self: *AliveBar) void {
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }

    /// Starts the refresh thread after the `AliveBar` address is stable.
    ///
    /// Do not move the value after calling this. If that is inconvenient, use `create()`.
    pub fn start(self: *AliveBar) !void {
        if (self.done.load(.monotonic) or self.running.load(.monotonic)) return;
        self.primeStart();

        self.running.store(true, .monotonic);
        if (self.interactive) {
            try self.writeOut("\x1b[?25l");
            self.thread = try std.Thread.spawn(.{}, refreshWorker, .{self});
        }
    }

    pub fn deinit(self: *AliveBar) void {
        self.finish() catch {};
    }

    /// Stops refresh thread and prints the final receipt (if configured).
    pub fn finish(self: *AliveBar) !void {
        if (self.done.swap(true, .monotonic)) return;

        self.running.store(false, .monotonic);
        if (self.thread) |th| {
            th.join();
            self.thread = null;
        }

        if (self.interactive) {
            try self.writeOut("\x1b[?25h");
        }

        if (!self.cfg.disable and self.cfg.receipt) {
            try self.writeReceipt();
        } else if (self.interactive) {
            try self.writeBufferedFrame("");
        }
    }

    /// Advance counter by `delta` (auto / unknown modes). Clamped at zero.
    pub fn tick(self: *AliveBar, delta: i64) void {
        if (self.manual or delta == 0) return;
        self.acquire();
        defer self.release();
        self.count +|= delta;
        if (self.count < 0) self.count = 0;
        self.processed +|= delta;
        if (self.processed < 0) self.processed = 0;
    }

    /// Advance count without contributing to throughput/ETA, equivalent to Python `skipped=True`.
    pub fn skip(self: *AliveBar, delta: i64) void {
        if (self.manual or delta == 0) return;
        self.acquire();
        defer self.release();
        self.count +|= delta;
        if (self.count < 0) self.count = 0;
    }

    /// Manual mode: set absolute progress in [0, 1].
    pub fn setFraction(self: *AliveBar, frac: f64) void {
        if (!self.manual) return;
        const f = std.math.clamp(frac, 0, 1);
        self.acquire();
        defer self.release();
        self.percent = f;
        if (self.total) |tot| {
            self.count = @intFromFloat(@ceil(f * @as(f64, @floatFromInt(tot))));
        }
        self.processed = self.count;
    }

    pub fn current(self: *AliveBar) f64 {
        self.acquire();
        defer self.release();
        return if (self.manual) self.percent else @floatFromInt(self.count);
    }

    pub fn elapsed(self: *AliveBar) f64 {
        return self.elapsedSeconds();
    }

    pub fn setTitle(self: *AliveBar, title: []const u8) !void {
        self.acquire();
        defer self.release();
        try self.setTitleUnlocked(title);
    }

    pub fn setText(self: *AliveBar, text: []const u8) !void {
        self.acquire();
        defer self.release();
        try self.setTextUnlocked(text);
    }

    fn refreshWorker(ctx: *AliveBar) void {
        while (ctx.running.load(.monotonic)) {
            ctx.primeStart();
            const sleep_ns = ctx.renderFrame() catch {
                platform.sleepNs(16 * std.time.ns_per_ms);
                continue;
            };
            platform.sleepNs(@max(sleep_ns, ctx.cfg.refresh_ms * std.time.ns_per_ms));
            _ = ctx.tick_frames.fetchAdd(1, .monotonic);
        }
    }

    /// One interactive frame; returns how long to sleep before the next frame.
    fn renderFrame(self: *AliveBar) !u64 {
        var line_buf: [max_frame_len]u8 = undefined;
        var line_w = fixedWriter(line_buf[0..]);

        const elapsed_s = self.elapsedSeconds();

        self.acquire();
        defer self.release();
        const count = self.count;
        const tot = self.total;
        const pct = self.percent;
        const manual = self.manual;
        const title = self.title_buf[0..self.title_len];
        const text = self.text_buf[0..self.text_len];
        const proc = self.processed;
        const frame = self.tick_frames.load(.monotonic);

        const rate_raw = if (elapsed_s > 0) @as(f64, @floatFromInt(proc)) / elapsed_s else 0;
        const rate = self.rate_smooth.next(rate_raw);

        const lt = self.logicTotal();
        const pos = if (tot != null and !manual)
            @as(f64, @floatFromInt(count))
        else
            pct * lt;

        var eta_buf: [32]u8 = undefined;
        const eta_str: []const u8 = blk: {
            if (tot == null and !manual) break :blk "?";
            const eraw = timing.simpleEta(lt, pos, rate);
            if (eraw < 0 or !std.math.isFinite(eraw)) break :blk "?";
            break :blk timing.formatEta(&eta_buf, self.eta_smooth.next(eraw));
        };

        var elap_buf: [32]u8 = undefined;
        const elapsed_str = timing.formatElapsedRun(&elap_buf, elapsed_s);

        var rate_buf: [48]u8 = undefined;
        const rate_str = try std.fmt.bufPrint(&rate_buf, "{d:.1}/s", .{rate});

        const mismatch = if (tot) |t| count != @as(i64, @intCast(t)) else false;
        const warn_prefix: []const u8 = if (mismatch) self.cfg.style.warning_prefix else "";

        if (title.len > 0) try line_w.print("{s} ", .{title});
        try line_w.writeAll(self.cfg.style.border_left);

        const bar_len = self.cfg.length;
        const frac: f64 = if (tot) |t| blk: {
            if (t == 0) break :blk 0;
            break :blk @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(t));
        } else if (manual) pct else 0;

        try writeProgressBar(&line_w, bar_len, tot, manual, frac, frame, self.cfg.style.bar);

        if (tot) |t| {
            if (count > @as(i64, @intCast(t))) try line_w.writeAll("⚠");
        }

        try line_w.print("{s} ", .{self.cfg.style.border_right});
        try line_w.writeAll(style_mod.spinnerFrame(
            self.cfg.style,
            @intCast(frame),
        ));
        try line_w.writeByte(' ');

        var mon_buf: [160]u8 = undefined;
        const mon = if (tot) |t| blk: {
            const p = if (t == 0) 0 else @as(f64, @floatFromInt(count)) * 100.0 / @as(f64, @floatFromInt(t));
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d}/{d} [{d:.0}%]", .{ warn_prefix, count, t, p });
        } else if (manual) blk: {
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d:.0}%", .{ warn_prefix, pct * 100.0 });
        } else blk: {
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d}", .{ warn_prefix, count });
        };

        try line_w.print(" {s} in {s} ({s}, eta: {s})", .{ mon, elapsed_str, rate_str, eta_str });

        if (text.len > 0) {
            try line_w.print("  {s}", .{text});
        }

        const slice = line_buf[0..line_w.end];
        if (self.interactive) {
            try self.writeBufferedFrame(slice);
        }

        return calibration.sleepNsForNextFrame(self.cfg.calibrate, rate);
    }

    fn writeReceipt(self: *AliveBar) !void {
        self.primeStart();
        var line_buf: [max_frame_len]u8 = undefined;
        var line_w = fixedWriter(line_buf[0..]);

        const elapsed_s = self.elapsedSeconds();

        self.acquire();
        defer self.release();
        const count = self.count;
        const tot = self.total;
        const pct = self.percent;
        const manual = self.manual;
        const title = self.title_buf[0..self.title_len];
        const proc = self.processed;
        const frame = self.tick_frames.load(.monotonic);

        const rate_raw = if (elapsed_s > 0) @as(f64, @floatFromInt(proc)) / elapsed_s else 0;

        var elap_buf: [32]u8 = undefined;
        const elapsed_str = timing.formatElapsedEnd(&elap_buf, elapsed_s);

        var rate_buf: [48]u8 = undefined;
        const rate_str = try std.fmt.bufPrint(&rate_buf, "{d:.2}/s", .{rate_raw});

        const mismatch = if (tot) |t| count != @as(i64, @intCast(t)) else false;
        const warn_prefix: []const u8 = if (mismatch) self.cfg.style.warning_prefix else "";

        if (title.len > 0) try line_w.print("{s} ", .{title});
        try line_w.writeAll(self.cfg.style.border_left);

        const bar_len = self.cfg.length;
        const frac: f64 = if (tot) |t| blk: {
            if (t == 0) break :blk 0;
            break :blk @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(t));
        } else if (manual) pct else 0;

        try writeProgressBar(&line_w, bar_len, tot, manual, frac, frame, self.cfg.style.bar);

        if (tot) |t| {
            if (count > @as(i64, @intCast(t))) try line_w.writeAll("⚠");
        }

        try line_w.print("{s} ", .{self.cfg.style.border_right});

        var mon_buf: [160]u8 = undefined;
        const mon = if (tot) |t| blk: {
            const p = if (t == 0) 0 else @as(f64, @floatFromInt(count)) * 100.0 / @as(f64, @floatFromInt(t));
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d}/{d} [{d:.0}%]", .{ warn_prefix, count, t, p });
        } else if (manual) blk: {
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d:.0}%", .{ warn_prefix, pct * 100.0 });
        } else blk: {
            break :blk try std.fmt.bufPrint(&mon_buf, "{s}{d}", .{ warn_prefix, count });
        };

        try line_w.print(" {s} in {s} ({s})", .{ mon, elapsed_str, rate_str });

        const slice = line_buf[0..line_w.end];
        if (self.interactive) {
            try self.writeBufferedFrame(slice);
        } else {
            try self.writeOut(slice);
        }
        try self.writeOut("\n");
    }
};
