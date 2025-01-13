const std = @import("std");
const SIMD = @import("SIMD.zig");
const expect = std.testing.expect;

const Self = @This();

byte_size: usize,
bit_size: usize,
bits_free: usize,

vector_count: usize,
vector_offsets: []usize,

data_slice: []u8,

fn get_vector_count(byte_size: usize) usize {
    return @divExact(byte_size, SIMD.VECTOR_SIZE);
}

fn get_vector_size(byte_size: usize) usize {
    return get_vector_count(byte_size) * @sizeOf(usize);
}

pub fn get_size(byte_size: usize) usize {
    return byte_size + get_vector_size(byte_size);
}

pub fn init(memory: []u8, byte_size: usize) Self {
    const bit_size = byte_size * 8;
    const bits_free = byte_size * 8;
    const data_slice = memory[0..byte_size];
    const vector_count = get_vector_count(byte_size);
    const vector_size = get_vector_size(byte_size);
    var vector_offsets: []usize = @as([*]usize, @ptrCast(@alignCast(memory[byte_size .. byte_size + vector_size])))[0..vector_count];

    for (0..vector_count) |i| {
        vector_offsets[i] = i * SIMD.VECTOR_SIZE;
    }

    @memset(data_slice, 255);

    return Self{
        .byte_size = byte_size,
        .bit_size = bit_size,
        .bits_free = bits_free,
        .vector_count = vector_count,
        .vector_offsets = vector_offsets,
        .data_slice = data_slice,
    };
}

// pub fn set_bits(self: Self, bit_offset: usize, bit_count: usize, is_free: bool) noreturn {
//     // TODO: implement
// }

pub fn find(self: Self, bits_needed: usize) ?usize {
    var remaining: usize = bits_needed;

    for (0..self.vector_count) |vector_index| {
        const slice = self.data_slice[self.vector_offsets[vector_index] .. self.vector_offsets[vector_index] + SIMD.VECTOR_SIZE];
        const vector = SIMD.from(slice);
        const popcount = SIMD.popcount(vector);

        // we keep jumping in the current layer
        // with step size equal to VECTOR_SIZE
        for (0..SIMD.VECTOR_SIZE) |byte_index| {
            const free_bits_in_byte = popcount[byte_index];
            const required_bits_in_byte = @min(8, remaining);

            // we don't have enough space so we reset remaining
            if (free_bits_in_byte < required_bits_in_byte) {
                remaining = bits_needed;
                continue;
            }

            // we might have enough space so we go bit by bit
            else {
                const byte = slice[byte_index];

                // TODO: inline
                for (0..8) |bit_index| {
                    // TODO: create a look-up table for masks
                    // if bit is zero we reset remaining
                    if (((byte >> @as(u3, @truncate(bit_index))) & 1) == 0) {
                        remaining = bits_needed;
                    }

                    // otherwise we decrease remaining
                    else {
                        remaining -= 1;

                        // check if we've reached the end
                        if (remaining == 0) {
                            return (vector_index * SIMD.VECTOR_BIT_SIZE) + (byte_index * 8) + bit_index + 1 - bits_needed;
                        }
                    }
                }
            }
        }
    }

    return null;
}

test "get_vector_count" {
    try expect(get_vector_count(4096) == 256);
}

test "get_vector_size" {
    try expect(get_vector_size(4096) == 2048);
}

test "get_size" {
    try expect(get_size(4096) == 6144);
}

test "init + find" {
    const allocator = std.testing.allocator;
    const raw_size = 4096;
    const memory_size = get_size(raw_size);
    const memory = try allocator.alloc(u8, memory_size);

    defer allocator.free(memory);

    const bitmap = init(memory, raw_size);

    bitmap.data_slice[0] = 0;

    const bit_pos = bitmap.find(365);

    std.debug.print("{any}\n", .{bit_pos});

    // try expect(bit_pos == 0);
}
