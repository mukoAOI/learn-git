const std = @import("std");
const Allocator = std.mem.Allocator;
const PriorityQueue = std.PriorityQueue;
const Order = std.math.Order;

// 哈夫曼树节点
const HuffmanNode = struct {
    frequency: u32,
    character: ?u8, // 非叶子节点为 null
    left: ?*HuffmanNode,
    right: ?*HuffmanNode,

    // 用于优先队列比较
    pub fn compare(context: void, a: *HuffmanNode, b: *HuffmanNode) Order {
        _ = context;
        if (a.frequency < b.frequency) {
            return .lt;
        } else if (a.frequency > b.frequency) {
            return .gt;
        } else {
            return .eq;
        }
    }
};

// 哈夫曼编码表
const HuffmanCode = struct {
    character: u8,
    code: []const u8,
    bit_length: usize,
};

// 哈夫曼树
const HuffmanTree = struct {
    root: *HuffmanNode,
    allocator: Allocator,
    codes: std.AutoHashMap(u8, []const u8),
    code_bit_lengths: std.AutoHashMap(u8, usize),

    // 构建哈夫曼树
    pub fn init(allocator: Allocator, frequencies: []const u32) !*HuffmanTree {
        var tree = try allocator.create(HuffmanTree);
        tree.allocator = allocator;
        tree.codes = std.AutoHashMap(u8, []const u8).init(allocator);
        tree.code_bit_lengths = std.AutoHashMap(u8, usize).init(allocator);

        // 创建优先队列（最小堆）
        var queue = PriorityQueue(*HuffmanNode, void, HuffmanNode.compare).init(allocator, {});
        defer queue.deinit();

        // 为每个字符创建节点并加入队列
        for (frequencies, 0..) |freq, i| {
            if (freq > 0) {
                const node = try allocator.create(HuffmanNode);
                node.* = .{
                    .frequency = freq,
                    .character = @as(u8, @intCast(i)),
                    .left = null,
                    .right = null,
                };
                try queue.add(node);
            }
        }

        // 构建哈夫曼树
        while (queue.count() > 1) {
            const left = queue.remove();
            const right = queue.remove();

            const parent = try allocator.create(HuffmanNode);
            parent.* = .{
                .frequency = left.frequency + right.frequency,
                .character = null,
                .left = left,
                .right = right,
            };

            try queue.add(parent);
        }

        tree.root = queue.remove();
        try tree.buildCodes(tree.root, "");

        return tree;
    }

    // 从数据直接构建哈夫曼树
    pub fn fromData(allocator: Allocator, data: []const u8) !*HuffmanTree {
        // 计算字符频率
        var frequencies = try allocator.alloc(u32, 256);
        defer allocator.free(frequencies);

        for (frequencies) |*freq| {
            freq.* = 0;
        }

        for (data) |byte| {
            frequencies[byte] += 1;
        }

        return try init(allocator, frequencies);
    }

    // 递归构建编码表
    fn buildCodes(self: *HuffmanTree, node: *HuffmanNode, code: []const u8) !void {
        if (node.character) |ch| {
            // 叶子节点，保存编码
            const code_copy = try self.allocator.dupe(u8, code);
            try self.codes.put(ch, code_copy);
            try self.code_bit_lengths.put(ch, code.len);
        } else {
            // 非叶子节点，递归处理左右子树
            if (node.left) |left| {
                const left_code = try std.fmt.allocPrint(self.allocator, "{s}0", .{code});
                defer self.allocator.free(left_code);
                try self.buildCodes(left, left_code);
            }

            if (node.right) |right| {
                const right_code = try std.fmt.allocPrint(self.allocator, "{s}1", .{code});
                defer self.allocator.free(right_code);
                try self.buildCodes(right, right_code);
            }
        }
    }

    // 获取字符的哈夫曼编码
    pub fn getCode(self: *HuffmanTree, character: u8) ?[]const u8 {
        return self.codes.get(character);
    }

    // 获取字符的哈夫曼编码位长度
    pub fn getCodeBitLength(self: *HuffmanTree, character: u8) ?usize {
        return self.code_bit_lengths.get(character);
    }

    // 压缩数据
    pub fn compress(self: *HuffmanTree, data: []const u8) ![]const u8 {
        // 计算压缩后的大致大小
        var total_bits: usize = 32; // 用于存储数据长度的32位
        for (data) |byte| {
            if (self.getCodeBitLength(byte)) |len| {
                total_bits += len;
            }
        }
        const total_bytes = (total_bits + 7) / 8; // 向上取整

        // 创建输出缓冲区
        var output = try self.allocator.alloc(u8, total_bytes);
        errdefer self.allocator.free(output);

        // 使用内存流写入数据
        var stream = std.io.fixedBufferStream(output);
        const writer = stream.writer();

        // 写入数据长度
        try writer.writeIntLittle(u32, @as(u32, @intCast(data.len)));

        // 写入压缩数据
        var bit_buffer: u8 = 0;
        var bit_count: u8 = 0;
        var output_index: usize = 4; // 跳过长度字段

        for (data) |byte| {
            if (self.getCode(byte)) |code| {
                for (code) |bit_char| {
                    const bit = (bit_char == '1');
                    bit_buffer = (bit_buffer << 1) | @intFromBool(bit);
                    bit_count += 1;

                    if (bit_count == 8) {
                        output[output_index] = bit_buffer;
                        output_index += 1;
                        bit_buffer = 0;
                        bit_count = 0;
                    }
                }
            }
        }

        // 处理剩余的位
        if (bit_count > 0) {
            bit_buffer <<= @as(u3, 8 - bit_count);
            output[output_index] = bit_buffer;
        }

        return output;
    }

    // 解压数据
    pub fn decompress(self: *HuffmanTree, compressed: []const u8) ![]const u8 {
        // 读取数据长度
        var stream = std.io.fixedBufferStream(compressed);
        const reader = stream.reader();
        const data_length = try reader.readIntLittle(u32);

        // 创建输出缓冲区
        var output = try self.allocator.alloc(u8, data_length);
        errdefer self.allocator.free(output);

        // 解码数据
        var current_node = self.root;
        var output_index: usize = 0;
        var byte_index: usize = 4; // 跳过长度字段

        while (output_index < data_length) {
            if (byte_index >= compressed.len) {
                return error.InvalidHuffmanData;
            }

            const byte = compressed[byte_index];
            var bit_mask: u8 = 0x80; // 从最高位开始

            while (bit_mask > 0 and output_index < data_length) {
                const bit = (byte & bit_mask) != 0;

                if (bit) {
                    current_node = current_node.right orelse return error.InvalidHuffmanData;
                } else {
                    current_node = current_node.left orelse return error.InvalidHuffmanData;
                }

                if (current_node.character) |ch| {
                    output[output_index] = ch;
                    output_index += 1;
                    current_node = self.root;
                }

                bit_mask >>= 1;
            }

            byte_index += 1;
        }

        return output;
    }

    // 释放内存
    pub fn deinit(self: *HuffmanTree) void {
        self.freeNode(self.root);

        var iter = self.codes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.codes.deinit();
        self.code_bit_lengths.deinit();
        self.allocator.destroy(self);
    }

    // 递归释放节点
    fn freeNode(self: *HuffmanTree, node: *HuffmanNode) void {
        if (node.left) |left| {
            self.freeNode(left);
        }
        if (node.right) |right| {
            self.freeNode(right);
        }
        self.allocator.destroy(node);
    }
};

// 测试代码
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const test_data = "this is an example of huffman encoding";

    std.debug.print("原始数据: {s}\n", .{test_data});
    std.debug.print("原始大小: {} 字节\n", .{test_data.len});

    // 从数据构建哈夫曼树
    var tree = try HuffmanTree.fromData(allocator, test_data);
    defer tree.deinit();

    // 输出字符编码
    const test_chars = "abcdefghijklmnopqrstuvwxyz ";
    for (test_chars) |ch| {
        if (tree.getCode(ch)) |code| {
            std.debug.print("字符 '{c}' 的哈夫曼编码: {s}\n", .{ ch, code });
        }
    }

    // 压缩数据
    const compressed = try tree.compress(test_data);
    defer allocator.free(compressed);

    std.debug.print("压缩后大小: {} 字节\n", .{compressed.len});
    std.debug.print("压缩率: {d:.2}%\n", .{@as(f32, @floatFromInt(compressed.len)) / @as(f32, @floatFromInt(test_data.len)) * 100});

    // 解压数据
    const decompressed = try tree.decompress(compressed);
    defer allocator.free(decompressed);

    std.debug.print("解压后数据: {s}\n", .{decompressed});

    // 验证数据是否正确
    if (std.mem.eql(u8, test_data, decompressed)) {
        std.debug.print("压缩和解压成功!\n", .{});
    } else {
        std.debug.print("压缩和解压失败!\n", .{});
    }
}
