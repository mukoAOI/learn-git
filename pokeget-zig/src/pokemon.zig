const std = @import("std");
const cli = @import("cli.zig");
const list_mod = @import("list.zig");

const DEFAULT_SHINY_RATE: u32 = 8192;

pub const Region = enum {
    Kanto,
    Johto,
    Hoenn,
    Sinnoh,
    Unova,
    Kalos,
    Alola,
    Galar,
};

pub const SelectionTag = enum {
    random,
    region,
    dex_id,
    name,
};

pub const Selection = union(SelectionTag) {
    random: void,
    region: Region,
    dex_id: usize,
    name: []const u8,

    pub fn parse(arg: []const u8) Selection {
        if (std.fmt.parseUnsigned(usize, arg, 10)) |dex_id| {
            if (dex_id == 0) return .{ .random = {} };
            return .{ .dex_id = dex_id - 1 };
        } else |_| {}

        if (std.ascii.eqlIgnoreCase(arg, "random")) return .{ .random = {} };
        if (std.ascii.eqlIgnoreCase(arg, "kanto")) return .{ .region = .Kanto };
        if (std.ascii.eqlIgnoreCase(arg, "johto")) return .{ .region = .Johto };
        if (std.ascii.eqlIgnoreCase(arg, "hoenn")) return .{ .region = .Hoenn };
        if (std.ascii.eqlIgnoreCase(arg, "sinnoh")) return .{ .region = .Sinnoh };
        if (std.ascii.eqlIgnoreCase(arg, "unova")) return .{ .region = .Unova };
        if (std.ascii.eqlIgnoreCase(arg, "kalos")) return .{ .region = .Kalos };
        if (std.ascii.eqlIgnoreCase(arg, "alola")) return .{ .region = .Alola };
        if (std.ascii.eqlIgnoreCase(arg, "galar")) return .{ .region = .Galar };
        return .{ .name = arg };
    }
};

pub const Attributes = struct {
    form: []const u8,
    female: bool,
    shiny: bool,
    owns_form: bool,

    pub fn fromArgs(allocator: std.mem.Allocator, args: *const cli.Args, prng: std.Random) !Attributes {
        var form = args.form;
        if (args.mega) form = "mega";
        if (args.mega_x) form = "mega-x";
        if (args.mega_y) form = "mega-y";
        if (args.alolan) form = "alola";
        if (args.gmax) form = "gmax";
        if (args.hisui) form = "hisui";
        if (args.galar) form = "galar";

        var owns_form = false;
        if (args.noble and form.len != 0) {
            form = try std.mem.concat(allocator, u8, &[_][]const u8{ form, "-noble" });
            owns_form = true;
        } else if (args.noble and form.len == 0) {
            form = "noble";
        }

        return .{
            .form = form,
            .female = args.female,
            .shiny = args.shiny or isShinyByRate(prng),
            .owns_form = owns_form,
        };
    }

    fn isShinyByRate(prng: std.Random) bool {
        return prng.uintLessThan(u32, DEFAULT_SHINY_RATE) == 0;
    }

    pub fn path(self: *const Attributes, allocator: std.mem.Allocator, name: []const u8, random: bool, region: bool) ![]const u8 {
        const is_random = random or region;
        var filename_builder = std.array_list.Managed(u8).init(allocator);
        defer filename_builder.deinit();

        try filename_builder.appendSlice(name);
        if (self.form.len != 0 and !is_random) {
            try filename_builder.append('-');
            try filename_builder.appendSlice(self.form);
        }

        const filename = filename_builder.items;
        var clean = std.array_list.Managed(u8).init(allocator);
        defer clean.deinit();

        for (filename) |c| {
            const ch = switch (c) {
                ' ', '_' => '-',
                '.', '\'', ':' => continue,
                else => std.ascii.toLower(c),
            };
            try clean.append(ch);
        }

        const folder = if (self.shiny) "shiny" else "regular";
        const female_folder = if (self.female and !is_random) "female/" else "";

        return std.fmt.allocPrint(allocator, "data/pokesprite/pokemon-gen8/{s}/{s}{s}.png", .{
            folder,
            female_folder,
            std.mem.trim(u8, clean.items, " "),
        });
    }
};

pub const Pokemon = struct {
    name: []const u8,
    sprite_path: []const u8,

    pub fn resolve(
        allocator: std.mem.Allocator,
        arg: []const u8,
        list: *const list_mod.List,
        attributes: *const Attributes,
        prng: std.Random,
    ) !Pokemon {
        const selection = Selection.parse(arg);
        const is_random = selection == .random;
        const is_region = selection == .region;

        const filename = switch (selection) {
            .random => list.random(prng),
            .region => |r| list.getByRegion(r, prng),
            .dex_id => |id| list.getById(id) orelse return error.InvalidDexId,
            .name => |n| n,
        };

        return .{
            .name = list.formatName(filename),
            .sprite_path = try attributes.path(allocator, filename, is_random, is_region),
        };
    }
};
