const std = @import("std");
const cli = @import("cli.zig");
const list_mod = @import("list.zig");
const pokemon = @import("pokemon.zig");
const sprite = @import("sprite_render.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());

    var args = cli.parseArgs(allocator, argv) catch |err| switch (err) {
        error.HelpDisplayed => return,
        error.MissingFormValue => {
            std.debug.print("missing value for --form\n", .{});
            return error.InvalidArguments;
        },
        error.UnknownOption => {
            std.debug.print("unknown option\n", .{});
            return error.InvalidArguments;
        },
        else => return err,
    };
    defer args.deinit();

    if (args.pokemon.items.len == 0) {
        std.debug.print("you must specify the pokemon you want to display\n", .{});
        return error.InvalidArguments;
    }

    var list = try list_mod.List.init(allocator);
    defer list.deinit();

    const now_ns = std.Io.Timestamp.now(init.io, .awake).toNanoseconds();
    const seed: u64 = @truncate(@as(u96, @bitCast(now_ns)));
    var prng_gen = std.Random.DefaultPrng.init(seed);
    const prng = prng_gen.random();

    const attributes = try pokemon.Attributes.fromArgs(allocator, &args, prng);

    var resolved = std.array_list.Managed(pokemon.Pokemon).init(allocator);
    try resolved.ensureTotalCapacity(args.pokemon.items.len);
    var decoded = std.array_list.Managed(sprite.Image).init(allocator);
    try decoded.ensureTotalCapacity(args.pokemon.items.len);
    defer {
        for (resolved.items) |item| allocator.free(item.sprite_path);
        resolved.deinit();
        for (decoded.items) |img| img.deinit(allocator);
        decoded.deinit();
        if (attributes.owns_form) {
            allocator.free(attributes.form);
        }
    }

    for (args.pokemon.items) |arg| {
        const selection = pokemon.Selection.parse(arg);
        const can_reroll = selection == .random or selection == .region;
        var attempts: usize = 0;
        const max_attempts: usize = 32;

        while (true) {
            const p = pokemon.Pokemon.resolve(allocator, arg, &list, &attributes, prng) catch |err| switch (err) {
                error.InvalidDexId => {
                    std.debug.print("{s} is not a valid pokedex ID\n", .{arg});
                    return error.InvalidArguments;
                },
                else => return err,
            };

            const img = sprite.loadPng(allocator, init.io, p.sprite_path) catch |err| switch (err) {
                error.FileNotFound, error.UnsupportedPngFormat => {
                    allocator.free(p.sprite_path);
                    attempts += 1;
                    if (can_reroll and attempts < max_attempts) continue;
                    std.debug.print("宝可梦不存在\n", .{});
                    return error.MissingSpriteAssets;
                },
                else => {
                    allocator.free(p.sprite_path);
                    return err;
                },
            };

            try resolved.append(p);
            try decoded.append(img);
            break;
        }
    }

    const combined = try sprite.combineSprites(allocator, decoded.items);
    defer combined.deinit(allocator);

    if (!args.hide_name) {
        for (resolved.items, 0..) |p, idx| {
            if (idx != 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{p.name});
        }
        std.debug.print("\n", .{});
    }

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    try sprite.renderAnsiHalfBlocks(&stdout_writer.interface, combined);
    try stdout_writer.interface.flush();
}
