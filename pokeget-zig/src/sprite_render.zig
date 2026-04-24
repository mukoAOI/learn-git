const std = @import("std");

pub const Pixel = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Image = struct {
    width: usize,
    height: usize,
    pixels: []Pixel,

    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

const Ihdr = struct {
    width: usize,
    height: usize,
    bit_depth: u8,
    color_type: u8,
    compression: u8,
    filter: u8,
    interlace: u8,
};

pub fn loadPng(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Image {
    const file = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(file);
    return decodePngBytes(allocator, file);
}

fn decodePngBytes(allocator: std.mem.Allocator, file: []const u8) !Image {
    const sig = "\x89PNG\r\n\x1a\n";
    if (file.len < sig.len or !std.mem.eql(u8, file[0..sig.len], sig)) return error.InvalidPng;

    var ihdr: ?Ihdr = null;
    var palette: ?[]u8 = null;
    defer if (palette) |p| allocator.free(p);
    var trns: ?[]u8 = null;
    defer if (trns) |t| allocator.free(t);

    var idat = std.array_list.Managed(u8).init(allocator);
    defer idat.deinit();

    var i: usize = sig.len;
    while (i + 12 <= file.len) {
        const chunk_len = readU32be(file[i..][0..4]);
        i += 4;
        const typ = file[i..][0..4];
        i += 4;
        if (i + chunk_len + 4 > file.len) return error.InvalidPng;
        const data = file[i .. i + chunk_len];
        i += chunk_len;
        _ = file[i .. i + 4];
        i += 4;

        if (std.mem.eql(u8, typ, "IHDR")) {
            if (data.len != 13) return error.InvalidPng;
            ihdr = .{
                .width = readU32be(data[0..4]),
                .height = readU32be(data[4..8]),
                .bit_depth = data[8],
                .color_type = data[9],
                .compression = data[10],
                .filter = data[11],
                .interlace = data[12],
            };
        } else if (std.mem.eql(u8, typ, "PLTE")) {
            palette = try allocator.dupe(u8, data);
        } else if (std.mem.eql(u8, typ, "tRNS")) {
            trns = try allocator.dupe(u8, data);
        } else if (std.mem.eql(u8, typ, "IDAT")) {
            try idat.appendSlice(data);
        } else if (std.mem.eql(u8, typ, "IEND")) {
            break;
        }
    }

    const header = ihdr orelse return error.InvalidPng;
    if (header.bit_depth != 8 or header.compression != 0 or header.filter != 0 or header.interlace != 0) {
        return error.UnsupportedPngFormat;
    }

    const channels: usize = switch (header.color_type) {
        0 => 1,
        2 => 3,
        3 => 1,
        6 => 4,
        else => return error.UnsupportedPngFormat,
    };
    const stride = header.width * channels;
    const expected = header.height * (stride + 1);

    var compressed_reader: std.Io.Reader = .fixed(idat.items);
    var inflator: std.compress.flate.Decompress = .init(&compressed_reader, .zlib, &.{});
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    _ = try inflator.reader.streamRemaining(&out.writer);
    const raw = try out.toOwnedSlice();
    defer allocator.free(raw);
    if (raw.len < expected) return error.InvalidPng;

    const scanlines = try allocator.alloc(u8, stride * header.height);
    defer allocator.free(scanlines);
    try unfilter(scanlines, raw, header.width, header.height, channels);

    const pixels = try allocator.alloc(Pixel, header.width * header.height);
    var pidx: usize = 0;
    var offset: usize = 0;
    for (0..header.height) |_| {
        for (0..header.width) |_| {
            const px = switch (header.color_type) {
                0 => blk: {
                    const v = scanlines[offset];
                    offset += 1;
                    break :blk Pixel{ .r = v, .g = v, .b = v, .a = 255 };
                },
                2 => blk: {
                    const r = scanlines[offset];
                    const g = scanlines[offset + 1];
                    const b = scanlines[offset + 2];
                    offset += 3;
                    break :blk Pixel{ .r = r, .g = g, .b = b, .a = 255 };
                },
                3 => blk: {
                    const idx = scanlines[offset];
                    offset += 1;
                    const pal = palette orelse return error.InvalidPng;
                    const base = @as(usize, idx) * 3;
                    if (base + 2 >= pal.len) return error.InvalidPng;
                    const alpha = if (trns) |t| if (@as(usize, idx) < t.len) t[idx] else 255 else 255;
                    break :blk Pixel{ .r = pal[base], .g = pal[base + 1], .b = pal[base + 2], .a = alpha };
                },
                6 => blk: {
                    const r = scanlines[offset];
                    const g = scanlines[offset + 1];
                    const b = scanlines[offset + 2];
                    const a = scanlines[offset + 3];
                    offset += 4;
                    break :blk Pixel{ .r = r, .g = g, .b = b, .a = a };
                },
                else => return error.UnsupportedPngFormat,
            };
            pixels[pidx] = px;
            pidx += 1;
        }
    }

    var img = Image{ .width = header.width, .height = header.height, .pixels = pixels };
    try trimTransparent(allocator, &img);
    return img;
}

fn unfilter(dst: []u8, src: []const u8, width: usize, height: usize, channels: usize) !void {
    const stride = width * channels;
    if (src.len < height * (stride + 1) or dst.len < height * stride) return error.InvalidPng;

    var src_row_start: usize = 0;
    var dst_row_start: usize = 0;
    for (0..height) |row| {
        const filter = src[src_row_start];
        const cur = src[src_row_start + 1 .. src_row_start + 1 + stride];
        const out = dst[dst_row_start .. dst_row_start + stride];
        const prev = if (row == 0) null else dst[dst_row_start - stride .. dst_row_start];

        switch (filter) {
            0 => @memcpy(out, cur),
            1 => {
                for (0..stride) |x| {
                    const left: u8 = if (x >= channels) out[x - channels] else 0;
                    out[x] = cur[x] +% left;
                }
            },
            2 => {
                for (0..stride) |x| {
                    const up: u8 = if (prev) |p| p[x] else 0;
                    out[x] = cur[x] +% up;
                }
            },
            3 => {
                for (0..stride) |x| {
                    const left: u8 = if (x >= channels) out[x - channels] else 0;
                    const up: u8 = if (prev) |p| p[x] else 0;
                    const avg: u8 = @intCast((@as(u16, left) + @as(u16, up)) / 2);
                    out[x] = cur[x] +% avg;
                }
            },
            4 => {
                for (0..stride) |x| {
                    const a: u8 = if (x >= channels) out[x - channels] else 0;
                    const b: u8 = if (prev) |p| p[x] else 0;
                    const c: u8 = if (x >= channels and prev != null) prev.?[x - channels] else 0;
                    out[x] = cur[x] +% paeth(a, b, c);
                }
            },
            else => return error.UnsupportedPngFilter,
        }

        src_row_start += stride + 1;
        dst_row_start += stride;
    }
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const ai: i32 = a;
    const bi: i32 = b;
    const ci: i32 = c;
    const p = ai + bi - ci;
    const pa = @abs(p - ai);
    const pb = @abs(p - bi);
    const pc = @abs(p - ci);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

fn trimTransparent(allocator: std.mem.Allocator, img: *Image) !void {
    var min_x: usize = img.width;
    var min_y: usize = img.height;
    var max_x: usize = 0;
    var max_y: usize = 0;
    var any = false;

    for (0..img.height) |y| {
        for (0..img.width) |x| {
            const p = img.pixels[y * img.width + x];
            if (p.a != 0) {
                any = true;
                if (x < min_x) min_x = x;
                if (y < min_y) min_y = y;
                if (x > max_x) max_x = x;
                if (y > max_y) max_y = y;
            }
        }
    }

    if (!any) return;
    if (min_x == 0 and min_y == 0 and max_x + 1 == img.width and max_y + 1 == img.height) return;

    const new_w = max_x - min_x + 1;
    const new_h = max_y - min_y + 1;
    const new_pixels = try allocator.alloc(Pixel, new_w * new_h);
    for (0..new_h) |y| {
        const src_start = (min_y + y) * img.width + min_x;
        const dst_start = y * new_w;
        @memcpy(new_pixels[dst_start .. dst_start + new_w], img.pixels[src_start .. src_start + new_w]);
    }
    allocator.free(img.pixels);
    img.pixels = new_pixels;
    img.width = new_w;
    img.height = new_h;
}

pub fn combineSprites(allocator: std.mem.Allocator, images: []const Image) !Image {
    if (images.len == 0) return error.NoSprites;

    var total_width: usize = 0;
    var max_height: usize = 0;
    for (images, 0..) |img, idx| {
        total_width += img.width;
        if (idx != 0) total_width += 1;
        if (img.height > max_height) max_height = img.height;
    }

    const pixels = try allocator.alloc(Pixel, total_width * max_height);
    for (pixels) |*p| p.* = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

    var x_shift: usize = 0;
    for (images, 0..) |img, idx| {
        const y_off = max_height - img.height;
        for (0..img.height) |y| {
            const src_start = y * img.width;
            const dst_start = (y + y_off) * total_width + x_shift;
            @memcpy(pixels[dst_start .. dst_start + img.width], img.pixels[src_start .. src_start + img.width]);
        }
        x_shift += img.width;
        if (idx + 1 < images.len) x_shift += 1;
    }

    return .{
        .width = total_width,
        .height = max_height,
        .pixels = pixels,
    };
}

pub fn renderAnsiHalfBlocks(writer: *std.Io.Writer, img: Image) !void {
    const Rgb = struct { r: u8, g: u8, b: u8 };
    var fg: ?Rgb = null;
    var bg: ?Rgb = null;

    var y: usize = 0;
    while (y < img.height) : (y += 2) {
        for (0..img.width) |x| {
            const top = img.pixels[y * img.width + x];
            const bottom = if (y + 1 < img.height) img.pixels[(y + 1) * img.width + x] else Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 };

            if (top.a == 0 and bottom.a == 0) {
                if (fg != null or bg != null) {
                    try writer.writeAll("\x1b[0m");
                    fg = null;
                    bg = null;
                }
                try writer.writeAll(" ");
            } else if (top.a != 0 and bottom.a == 0) {
                const next_fg = Rgb{ .r = top.r, .g = top.g, .b = top.b };
                if (fg == null or !std.meta.eql(fg.?, next_fg)) {
                    try writer.print("\x1b[38;2;{};{};{}m", .{ next_fg.r, next_fg.g, next_fg.b });
                    fg = next_fg;
                }
                if (bg != null) {
                    try writer.writeAll("\x1b[49m");
                    bg = null;
                }
                try writer.writeAll("▀");
            } else if (top.a == 0 and bottom.a != 0) {
                const next_fg = Rgb{ .r = bottom.r, .g = bottom.g, .b = bottom.b };
                if (fg == null or !std.meta.eql(fg.?, next_fg)) {
                    try writer.print("\x1b[38;2;{};{};{}m", .{ next_fg.r, next_fg.g, next_fg.b });
                    fg = next_fg;
                }
                if (bg != null) {
                    try writer.writeAll("\x1b[49m");
                    bg = null;
                }
                try writer.writeAll("▄");
            } else {
                const next_fg = Rgb{ .r = top.r, .g = top.g, .b = top.b };
                const next_bg = Rgb{ .r = bottom.r, .g = bottom.g, .b = bottom.b };
                if (fg == null or !std.meta.eql(fg.?, next_fg)) {
                    try writer.print("\x1b[38;2;{};{};{}m", .{ next_fg.r, next_fg.g, next_fg.b });
                    fg = next_fg;
                }
                if (bg == null or !std.meta.eql(bg.?, next_bg)) {
                    try writer.print("\x1b[48;2;{};{};{}m", .{ next_bg.r, next_bg.g, next_bg.b });
                    bg = next_bg;
                }
                try writer.writeAll("▀");
            }
        }
        if (fg != null or bg != null) {
            try writer.writeAll("\x1b[0m");
            fg = null;
            bg = null;
        }
        try writer.writeAll("\n");
    }
}

fn readU32be(bytes: []const u8) usize {
    return (@as(usize, bytes[0]) << 24) | (@as(usize, bytes[1]) << 16) | (@as(usize, bytes[2]) << 8) | bytes[3];
}
