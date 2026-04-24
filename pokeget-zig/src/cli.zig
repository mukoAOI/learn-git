const std = @import("std");

pub const Args = struct {
    pokemon: std.array_list.Managed([]const u8),
    hide_name: bool = false,
    form: []const u8 = "",
    mega: bool = false,
    mega_x: bool = false,
    mega_y: bool = false,
    shiny: bool = false,
    alolan: bool = false,
    gmax: bool = false,
    hisui: bool = false,
    noble: bool = false,
    galar: bool = false,
    female: bool = false,

    pub fn deinit(self: *Args) void {
        self.pokemon.deinit();
    }
};

fn printHelp() void {
    std.debug.print(
        \\Usage:
        \\  pokeget-zig <pokemon...> [options]
        \\
        \\Options:
        \\  --hide-name         Hide pokemon names
        \\  -f, --form <form>   Set custom form suffix
        \\  -m, --mega          Use mega form
        \\  --mega-x            Use mega-x form
        \\  --mega-y            Use mega-y form
        \\  -s, --shiny         Force shiny
        \\  -a, --alolan        Use alola form
        \\  --gmax              Use gmax form
        \\  --hisui             Use hisui form
        \\  -n, --noble         Append -noble
        \\  --galar             Use galar form
        \\  --female            Use female variant
        \\  -h, --help          Show this help
        \\
    , .{});
}

pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !Args {
    var args = Args{
        .pokemon = std.array_list.Managed([]const u8).init(allocator),
    };

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return error.HelpDisplayed;
        } else if (std.mem.eql(u8, arg, "--hide-name")) {
            args.hide_name = true;
        } else if (std.mem.eql(u8, arg, "--form") or std.mem.eql(u8, arg, "-f")) {
            if (i + 1 >= argv.len) return error.MissingFormValue;
            i += 1;
            const value = argv[i];
            args.form = value;
        } else if (std.mem.eql(u8, arg, "--mega") or std.mem.eql(u8, arg, "-m")) {
            args.mega = true;
        } else if (std.mem.eql(u8, arg, "--mega-x")) {
            args.mega_x = true;
        } else if (std.mem.eql(u8, arg, "--mega-y")) {
            args.mega_y = true;
        } else if (std.mem.eql(u8, arg, "--shiny") or std.mem.eql(u8, arg, "-s")) {
            args.shiny = true;
        } else if (std.mem.eql(u8, arg, "--alolan") or std.mem.eql(u8, arg, "-a")) {
            args.alolan = true;
        } else if (std.mem.eql(u8, arg, "--gmax")) {
            args.gmax = true;
        } else if (std.mem.eql(u8, arg, "--hisui")) {
            args.hisui = true;
        } else if (std.mem.eql(u8, arg, "--noble") or std.mem.eql(u8, arg, "-n")) {
            args.noble = true;
        } else if (std.mem.eql(u8, arg, "--galar")) {
            args.galar = true;
        } else if (std.mem.eql(u8, arg, "--female")) {
            args.female = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            try args.pokemon.append(arg);
        }
    }

    return args;
}
