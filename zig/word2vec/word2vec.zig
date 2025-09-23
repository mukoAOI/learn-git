const std = @import("std");
const math = std.math;
const mem = std.mem;
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const Word2Vec = struct {
    const Self = @This();

    allocator: Allocator,
    vocab_size: usize,
    embedding_dim: usize,
    window_size: usize,
    learning_rate: f32,
    neg_samples: usize,

    // Vocabulary
    word_to_index: std.StringHashMap(usize),
    index_to_word: std.ArrayList([]const u8),
    word_freq: std.ArrayList(u32),

    // Model parameters
    input_embeddings: std.ArrayList(f32), // vocab_size × embedding_dim
    output_embeddings: std.ArrayList(f32), // vocab_size × embedding_dim

    // Training state
    rng: std.Random,

    pub fn init(
        allocator: Allocator,
        vocab_size: usize,
        embedding_dim: usize,
        window_size: usize,
        learning_rate: f32,
        neg_samples: usize,
    ) !Self {
        const seed: u128 = @bitCast(std.time.nanoTimestamp());
        var prng = std.rand.DefaultPrng.init(seed);
        const rng = prng.random();

        return Self{
            .allocator = allocator,
            .vocab_size = vocab_size,
            .embedding_dim = embedding_dim,
            .window_size = window_size,
            .learning_rate = learning_rate,
            .neg_samples = neg_samples,
            .word_to_index = std.StringHashMap(usize).init(allocator),
            .index_to_word = std.ArrayList([]const u8).init(allocator),
            .word_freq = std.ArrayList(u32).init(allocator),
            .input_embeddings = std.ArrayList(f32).init(allocator),
            .output_embeddings = std.ArrayList(f32).init(allocator),
            .rng = rng,
        };
    }

    pub fn deinit(self: *Self) void {
        self.word_to_index.deinit();

        for (self.index_to_word.items) |word| {
            self.allocator.free(word);
        }
        self.index_to_word.deinit();
        self.word_freq.deinit();
        self.input_embeddings.deinit();
        self.output_embeddings.deinit();
    }

    // Build vocabulary from text
    pub fn buildVocabulary(self: *Self, text: []const u8) !void {
        var word_counts = std.StringHashMap(u32).init(self.allocator);
        defer word_counts.deinit();

        var iterator = std.mem.tokenizeAny(u8, text, " \t\n\r");
        while (iterator.next()) |word| {
            const trimmed_word = std.mem.trim(u8, word, ".,!?;:\"()");
            if (trimmed_word.len == 0) continue;

            const entry = try word_counts.getOrPut(trimmed_word);
            if (entry.found_existing) {
                entry.value_ptr.* += 1;
            } else {
                entry.value_ptr.* = 1;
                // Store a copy of the word
                const word_copy = try self.allocator.dupe(u8, trimmed_word);
                entry.key_ptr.* = word_copy;
            }
        }

        // Sort by frequency and take top vocab_size words
        var entries = std.ArrayList(struct { word: []const u8, count: u32 }).init(self.allocator);
        defer entries.deinit();

        var it = word_counts.iterator();
        while (it.next()) |entry| {
            try entries.append(.{ .word = entry.key_ptr.*, .count = entry.value_ptr.* });
        }

        // Sort by frequency descending
        std.sort.block(struct { word: []const u8, count: u32 }, entries.items, {}, struct {
            fn lessThan(_: void, a: struct { word: []const u8, count: u32 }, b: struct { word: []const u8, count: u32 }) bool {
                return a.count > b.count;
            }
        }.lessThan);

        const actual_vocab_size = @min(self.vocab_size, entries.items.len);

        // Initialize vocabulary structures
        try self.index_to_word.ensureTotalCapacity(actual_vocab_size);
        try self.word_freq.ensureTotalCapacity(actual_vocab_size);

        for (entries.items[0..actual_vocab_size], 0..) |entry, i| {
            const word_copy = try self.allocator.dupe(u8, entry.word);
            try self.word_to_index.put(word_copy, i);
            self.index_to_word.appendAssumeCapacity(word_copy);
            self.word_freq.appendAssumeCapacity(entry.count);
        }

        self.vocab_size = actual_vocab_size;

        // Initialize embeddings with random values
        const total_embeddings = self.vocab_size * self.embedding_dim;
        try self.input_embeddings.ensureTotalCapacity(total_embeddings);
        try self.output_embeddings.ensureTotalCapacity(total_embeddings);

        // Initialize with random values
        for (0..total_embeddings) |_| {
            const rand_val = self.rng.float(f32) * 2.0 - 1.0;
            self.input_embeddings.appendAssumeCapacity(rand_val * 0.1);
            self.output_embeddings.appendAssumeCapacity(rand_val * 0.1);
        }
    }

    // Get word frequency for negative sampling
    fn getWordFrequency(self: *Self, word_idx: usize) f32 {
        var total_words: u32 = 0;
        for (self.word_freq.items) |freq| {
            total_words += freq;
        }

        const freq = @as(f32, @floatFromInt(self.word_freq.items[word_idx])) / @as(f32, @floatFromInt(total_words));
        return std.math.pow(f32, freq, 0.75);
    }

    // Negative sampling distribution
    fn getNegativeSample(self: *Self) usize {
        const rand_val = self.rng.float(f32);
        var cumulative: f32 = 0.0;

        for (0..self.vocab_size) |i| {
            cumulative += self.getWordFrequency(i);
            if (rand_val <= cumulative) {
                return i;
            }
        }

        return self.vocab_size - 1;
    }

    // Sigmoid function
    fn sigmoid(x: f32) f32 {
        return 1.0 / (1.0 + std.math.exp(-x));
    }

    // Train on a single context window
    pub fn trainOnWindow(self: *Self, center_idx: usize, context_indices: []const usize) !void {
        const center_embedding_start = center_idx * self.embedding_dim;
        const center_embedding = self.input_embeddings.items[center_embedding_start .. center_embedding_start + self.embedding_dim];

        var input_grad = try self.allocator.alloc(f32, self.embedding_dim);
        defer self.allocator.free(input_grad);
        @memset(input_grad, 0.0);

        // Positive samples
        for (context_indices) |context_idx| {
            const output_embedding_start = context_idx * self.embedding_dim;
            const output_embedding = self.output_embeddings.items[output_embedding_start .. output_embedding_start + self.embedding_dim];

            // Dot product
            var dot: f32 = 0.0;
            for (center_embedding, output_embedding) |c, o| {
                dot += c * o;
            }

            const score = Self.sigmoid(dot);
            const error1 = score - 1.0; // Positive sample target is 1

            // Calculate gradients
            for (0..self.embedding_dim) |j| {
                const grad = error1 * output_embedding[j];
                input_grad[j] += grad;

                // Update output embedding
                self.output_embeddings.items[output_embedding_start + j] -= self.learning_rate * error1 * center_embedding[j];
            }
        }

        // Negative samples
        for (0..self.neg_samples) |_| {
            const neg_idx = self.getNegativeSample();
            if (neg_idx == center_idx) continue;

            const neg_embedding_start = neg_idx * self.embedding_dim;
            const neg_embedding = self.output_embeddings.items[neg_embedding_start .. neg_embedding_start + self.embedding_dim];

            // Dot product
            var dot: f32 = 0.0;
            for (center_embedding, neg_embedding) |c, n| {
                dot += c * n;
            }

            const score = Self.sigmoid(dot);
            const error1 = score - 0.0; // Negative sample target is 0

            // Calculate gradients
            for (0..self.embedding_dim) |j| {
                const grad = error1 * neg_embedding[j];
                input_grad[j] += grad;

                // Update negative embedding
                self.output_embeddings.items[neg_embedding_start + j] -= self.learning_rate * error1 * center_embedding[j];
            }
        }

        // Update input embedding
        for (0..self.embedding_dim) |j| {
            self.input_embeddings.items[center_embedding_start + j] -= self.learning_rate * input_grad[j];
        }
    }

    // Main training function
    pub fn train(self: *Self, text: []const u8, epochs: usize) !void {
        var words = std.ArrayList(usize).init(self.allocator);
        defer words.deinit();

        // Convert text to word indices
        var iterator = std.mem.tokenizeAny(u8, text, " \t\n\r");
        while (iterator.next()) |word| {
            const trimmed_word = std.mem.trim(u8, word, ".,!?;:\"()");
            if (trimmed_word.len == 0) continue;

            if (self.word_to_index.get(trimmed_word)) |idx| {
                try words.append(idx);
            }
        }

        std.debug.print("Training on {} words...\n", .{words.items.len});

        for (0..epochs) |epoch| {
            //var total_loss: f32 = 0.0;
            var sample_count: usize = 0;

            for (words.items, 0..) |center_word, i| {
                // Determine context window
                const start = if (i < self.window_size) 0 else i - self.window_size;
                const end = @min(i + self.window_size + 1, words.items.len);

                var context_indices = std.ArrayList(usize).init(self.allocator);
                defer context_indices.deinit();

                // Collect context words (excluding center word)
                for (start..end) |j| {
                    if (j != i) {
                        try context_indices.append(words.items[j]);
                    }
                }

                if (context_indices.items.len > 0) {
                    try self.trainOnWindow(center_word, context_indices.items);
                    sample_count += 1;
                }
            }

            std.debug.print("Epoch {}/{} completed\n", .{ epoch + 1, epochs });
        }
    }

    // Get embedding for a word
    pub fn getEmbedding(self: *Self, word: []const u8) ?[]const f32 {
        if (self.word_to_index.get(word)) |idx| {
            const start = idx * self.embedding_dim;
            return self.input_embeddings.items[start .. start + self.embedding_dim];
        }
        return null;
    }

    // Find most similar words
    pub fn mostSimilar(self: *Self, word: []const u8, top_k: usize) !?[]struct { word: []const u8, similarity: f32 } {
        const query_embedding = self.getEmbedding(word) orelse return null;

        var similarities = std.ArrayList(struct { word: []const u8, similarity: f32 }).init(self.allocator);
        defer similarities.deinit();

        for (self.index_to_word.items, 0..) |other_word, idx| {
            if (std.mem.eql(u8, word, other_word)) continue;

            const other_embedding_start = idx * self.embedding_dim;
            const other_embedding = self.input_embeddings.items[other_embedding_start .. other_embedding_start + self.embedding_dim];

            // Cosine similarity
            var dot: f32 = 0.0;
            var norm_query: f32 = 0.0;
            var norm_other: f32 = 0.0;

            for (query_embedding, other_embedding) |q, o| {
                dot += q * o;
                norm_query += q * q;
                norm_other += o * o;
            }

            const similarity = if (norm_query > 0 and norm_other > 0)
                dot / (std.math.sqrt(norm_query) * std.math.sqrt(norm_other))
            else
                0.0;

            try similarities.append(.{ .word = other_word, .similarity = similarity });
        }

        // Sort by similarity
        std.sort.block(struct { word: []const u8, similarity: f32 }, similarities.items, {}, struct {
            fn lessThan(_: void, a: struct { word: []const u8, similarity: f32 }, b: struct { word: []const u8, similarity: f32 }) bool {
                return a.similarity > b.similarity;
            }
        }.lessThan);

        const k = @min(top_k, similarities.items.len);
        var result = try self.allocator.alloc(struct { word: []const u8, similarity: f32 }, k);
        for (0..k) |i| {
            result[i] = similarities.items[i];
        }

        return result;
    }

    // Save embeddings to file
    pub fn saveEmbeddings(self: *Self, filename: []const u8) !void {
        var file = try fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();

        try writer.print("{} {}\n", .{ self.vocab_size, self.embedding_dim });

        for (self.index_to_word.items, 0..) |word, i| {
            try writer.print("{s}", .{word});

            const start = i * self.embedding_dim;
            const embedding = self.input_embeddings.items[start .. start + self.embedding_dim];

            for (embedding) |value| {
                try writer.print(" {d:.6}", .{value});
            }
            try writer.print("\n", .{});
        }
    }
};

// Example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sample_text =
        \\the quick brown fox jumps over the lazy dog
        \\machine learning is a subset of artificial intelligence
        \\natural language processing helps computers understand human language
        \\word embeddings represent words as vectors in high dimensional space
        \\deep learning models can learn complex patterns from data
    ;

    var model = try Word2Vec.init(
        allocator,
        1000, // vocab_size
        100, // embedding_dim
        5, // window_size
        0.025, // learning_rate
        5, // neg_samples
    );
    defer model.deinit();

    try model.buildVocabulary(sample_text);
    try model.train(sample_text, 10);

    // Test similarity
    if (try model.mostSimilar("learning", 5)) |similar_words| {
        defer allocator.free(similar_words);

        std.debug.print("Words similar to 'learning':\n", .{});
        for (similar_words) |item| {
            std.debug.print("  {s}: {d:.3}\n", .{ item.word, item.similarity });
        }
    }

    try model.saveEmbeddings("word_vectors.txt");
}
