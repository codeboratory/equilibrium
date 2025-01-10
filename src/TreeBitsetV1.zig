const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const Self = @This();

allocator: Allocator,

data_size: usize,

bitmap_data: []u8,
bitmap_data_size: usize,
bitmap_levels: [][]u8,
bitmap_levels_size: usize,

pub fn init(allocator: Allocator, size: usize, levels: usize) !Self {
    const offsets = try allocator.alloc(usize, levels);
    const lengths = try allocator.alloc(usize, levels);

    defer allocator.free(offsets);
    defer allocator.free(lengths);

    const bitmap_data_size = bk: {
        var total: usize = 0;

        for (0..levels) |i| {
            const length = size / std.math.pow(usize, 8, i + 1);

            offsets[i] = total;
            lengths[i] = length - 1;
            total += length;
        }

        break :bk total;
    };

    const bitmap_data = try allocator.alloc(u8, bitmap_data_size);
    const bitmap_levels = try allocator.alloc([]u8, levels);

    @memset(bitmap_data, 0);

    for (0..levels) |i| {
        const offset = offsets[i];
        const length = lengths[i];

        bitmap_levels[i] = bitmap_data[offset .. offset + length];
    }

    return Self{ .allocator = allocator, .data_size = size, .bitmap_data = bitmap_data, .bitmap_levels = bitmap_levels, .bitmap_data_size = bitmap_data_size, .bitmap_levels_size = levels };
}

pub fn free(self: Self) void {
    self.allocator.free(self.bitmap_data);
    self.allocator.free(self.bitmap_levels);
}

fn get_level_index(self: Self, size: usize) usize {
    return @min(self.bitmap_levels_size - 1, @as(usize, @intFromFloat(@divFloor(@log2(@as(f64, @floatFromInt(size))), 3))));
}

pub fn find(self: Self, size: usize) ?usize {
    var level_index = self.get_level_index(size);
    var level = self.bitmap_levels[level_index];
    var index = @as(usize, 0);
    var bits = (size + (std.math.pow(usize, 8, level_index + 1) - 1)) / std.math.pow(usize, 8, level_index + 1);

    while (index < level.len - 2) {
        const value = @as(u16, (@as(u16, level[index]) << 8) | level[index + 1]);
        const count = @as(usize, 16 - @popCount(value));

        std.debug.print("{any}\n", .{level});
        std.debug.print("{} {} {} {}\n", .{ level_index, index, bits, count });

        if (count >= bits) {
            if (level_index == 0) {
                return index;
            } else {
                bits *= 8;
                index *= 8;
                level_index -= 1;
                level = self.bitmap_levels[level_index][(index * 8) .. (index * 8) + 16];
            }
        } else {
            index += 1;
        }
    }

    return null;
}

test "Everything" {
    const size = 584;
    const levels = 3;

    const allocator = std.testing.allocator;
    const bitset = try Self.init(allocator, 4096, levels);
    defer bitset.free();

    try expect(bitset.bitmap_data.len == size);
    try expect(bitset.bitmap_data_size == size);
    try expect(bitset.bitmap_levels.len == levels);

    try expect(bitset.get_level_index(6) == 0);
    try expect(bitset.get_level_index(7) == 0);
    try expect(bitset.get_level_index(8) == 1);
    try expect(bitset.get_level_index(56) == 1);
    try expect(bitset.get_level_index(256) == 2);
    try expect(bitset.get_level_index(1024) == 2);

    // TODO: should jump to 0th level, not 1st
    std.debug.print("{any}\n", .{bitset.find(55)});
}
