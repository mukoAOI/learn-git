const app = @import("src/main.zig");
const std = @import("std");

pub fn main(init: std.process.Init) void {
    app.main(init) catch |err| {
        switch (err) {
            // User-input errors are already printed by app.main; avoid stack trace noise.
            error.InvalidArguments => std.process.exit(2),
            // Missing assets are already reported with a friendly message in app.main.
            error.MissingSpriteAssets => std.process.exit(1),
            else => {
                std.debug.print("error: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            },
        }
    };
}
