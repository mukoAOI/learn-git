//! Small blocking time helpers for the progress renderer.
//!
//! `std.Io` clocks are great when an application is already driving an IO runtime, but a progress
//! bar should also work in simple command-line programs. These helpers mirror Python's
//! `time.perf_counter()` plus `sleep()`.

const std = @import("std");
const builtin = @import("builtin");

var qpc_frequency = std.atomic.Value(i64).init(0);

pub fn nowNs() i128 {
    if (builtin.os.tag == .windows) {
        var counter: i64 = 0;
        const frequency = queryPerformanceFrequency();
        if (frequency == 0 or QueryPerformanceCounter(&counter) == .FALSE) {
            return 0;
        }
        return @divTrunc(@as(i128, counter) * std.time.ns_per_s, frequency);
    }

    // Fallback for targets where this prototype has not been specialized yet. It keeps the API
    // usable, while Windows (the current development target) gets a true monotonic clock.
    return 0;
}

pub fn sleepNs(ns: u64) void {
    if (ns == 0) return;
    if (builtin.os.tag == .windows) {
        const ms = @max(@divTrunc(ns + std.time.ns_per_ms - 1, std.time.ns_per_ms), 1);
        Sleep(@intCast(@min(ms, std.math.maxInt(windows.DWORD))));
        return;
    }
}

fn queryPerformanceFrequency() i64 {
    const cached = qpc_frequency.load(.monotonic);
    if (cached != 0) return cached;

    var frequency: i64 = 0;
    if (QueryPerformanceFrequency(&frequency) == .FALSE or frequency <= 0) return 0;

    _ = qpc_frequency.cmpxchgStrong(0, frequency, .release, .monotonic);
    return qpc_frequency.load(.acquire);
}

pub const WriteError = error{WriteFailed};

pub fn writeStdout(bytes: []const u8) WriteError!void {
    if (bytes.len == 0) return;
    if (builtin.os.tag == .windows) {
        const handle = GetStdHandle(std_output_handle);
        var remaining = bytes;
        while (remaining.len > 0) {
            const chunk_len = @min(remaining.len, std.math.maxInt(windows.DWORD));
            var written: windows.DWORD = 0;
            if (WriteFile(
                handle,
                remaining.ptr,
                @intCast(chunk_len),
                &written,
                null,
            ) == .FALSE) return error.WriteFailed;
            if (written == 0) return error.WriteFailed;
            remaining = remaining[written..];
        }
        return;
    }

    std.debug.print("{s}", .{bytes});
}

const windows = std.os.windows;
const std_output_handle: windows.DWORD = @bitCast(@as(i32, -11));

extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) windows.BOOL;
extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) windows.BOOL;
extern "kernel32" fn Sleep(dwMilliseconds: windows.DWORD) callconv(.winapi) void;
extern "kernel32" fn GetStdHandle(nStdHandle: windows.DWORD) callconv(.winapi) windows.HANDLE;
extern "kernel32" fn WriteFile(
    hFile: windows.HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: windows.DWORD,
    lpNumberOfBytesWritten: *windows.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) windows.BOOL;
