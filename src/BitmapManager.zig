const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const Self = @This();

allocator: Allocator,
size: usize,
layers: u8,
data: []u8,
sizes: []usize,
offsets: []usize,

fn slice_size(size: usize, index: usize) usize {
    return if (index == 0) 0 else size / std.math.pow(usize, 8, index);
}

fn data_size(size: usize, layers: u8) usize {
    var total: usize = 0;

    for (1..layers + 1) |i| {
        total += slice_size(size, i);
    }

    return total;
}

fn slice_index(layers: usize, size: usize) usize {
    return @min(layers - 1, @as(usize, @intFromFloat(@divFloor(@log2(@as(f64, @floatFromInt(size))), 3))));
}

pub fn init(allocator: Allocator, size: usize, layers: u8) !Self {
    const data = try allocator.alloc(u8, data_size(size, layers));
    const offsets = try allocator.alloc(usize, layers);
    const sizes = try allocator.alloc(usize, layers);

    @memset(data, 0);
    @memset(sizes, 0);

    for (0..layers) |i| {
        sizes[i] = slice_size(size, i + 1);
        offsets[i] = slice_size(size, i);
    }

    return Self{ .allocator = allocator, .size = size, .layers = layers, .data = data, .sizes = sizes, .offsets = offsets };
}

fn has_space(byte: u8, n: usize) bool {
    var expanded: u8 = byte;
    var i: u4 = 1;

    while (i < n) : (i += 1) {
        expanded |= byte << i;
    }
    
    const valid_positions = @as(u8, 0xFF) >> @intCast(n - 1);

    return (expanded & valid_positions) != valid_positions;
}

fn find_in_layer(self: Self, index: usize, size: usize) void {
    const layer_offset = self.offsets[index];
    const layer_size = self.sizes[index];
    const layer = self.data[layer_offset .. layer_offset + layer_size];
    const required_bits = layer_size / size;
    // const is_last = index == self.layers-1;

    for (0..layer_size - required_bits) |i| {
        const slice = layer[i .. i + required_bits];

        for(0..required_bits) |j| {
            if (has_space(slice[j]))
        }
    }
}

pub fn find(self: Self, size: usize) void {
    self.find_in_layer(slice_index(self.layers, size), size);
}

pub fn free(self: Self) void {
    self.allocator.free(self.data);
    self.allocator.free(self.sizes);
    self.allocator.free(self.offsets);
}

test "TEST" {
    const allocator = std.testing.allocator;
    const bitmap = try Self.init(allocator, 4096, 3);
    defer bitmap.free();

    bitmap.find(4);
    bitmap.find(16);
}
