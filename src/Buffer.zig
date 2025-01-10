const std = @import("std");
const Pager = @import("Pager.zig");

const posix = std.posix;
const mmap = posix.mmap;
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;

const Self = @This();

const VECTOR_SIZE = std.simd.suggestVectorLength(u8) orelse @panic("SIMD not supported");
const VECTOR_BIT_SIZE = VECTOR_SIZE * 8;

meta_size: u64,
meta_data: []u8,

total_size: u64,
total_data: []u8,

// TODO: abstract into Buffer
buffer_size: u64,
buffer_data: []u8,

// TODO: abstract into Bitmap
bitmap_count: u64,
bitmap_size: u64,
// NOTE: maybe change to u4 for less fragmentation
bitmap_data: []u8,

bitmap_offsets: []u64,
bitmap_sizes: []u64,
bitmap_multipliers: []u64,

bitmap_pointers: [][]u8,

pub fn init(buffer_size: u64) Self {
    const meta_size: u64 = 4096;
    const meta_data = Pager.alloc(meta_size);
    const bitmap_count: usize = @as(usize, @intFromFloat(@floor(@log(@as(f64, @floatFromInt(buffer_size))) / @log(8.0)))) - 1;
    const offset: usize = bitmap_count * 8;

    var bitmap_offsets: []u64 = @as([*]u64, @ptrCast(@alignCast(meta_data[offset * 0 .. offset * 1])))[0..bitmap_count];
    var bitmap_sizes: []u64 = @as([*]u64, @ptrCast(@alignCast(meta_data[offset * 1 .. offset * 2])))[0..bitmap_count];
    var bitmap_multipliers: []u64 = @as([*]u64, @ptrCast(@alignCast(meta_data[offset * 2 .. offset * 3])))[0..bitmap_count];
    var bitmap_pointers: [][]u8 = @as([*][]u8, @ptrCast(@alignCast(meta_data[offset * 3 .. offset * 4 * 2])))[0..bitmap_count];

    var bitmap_size: u64 = 0;

    for (0..bitmap_count) |i| {
        const multiplier = math.pow(u64, 8, i + 1);
        const size: u64 = buffer_size / multiplier;

        bitmap_offsets[i] = bitmap_size;
        bitmap_sizes[i] = size;
        bitmap_multipliers[i] = multiplier;
        bitmap_size += size;
    }

    const total_size = bitmap_size + buffer_size;
    const total_data = Pager.alloc(total_size);
    const bitmap_data = total_data[0..bitmap_size];
    const buffer_data = total_data[bitmap_size .. bitmap_size + buffer_size];

    @memset(bitmap_data, 255);

    for (0..bitmap_count) |i| {
        bitmap_pointers[i] = bitmap_data[bitmap_offsets[i] .. bitmap_offsets[i] + bitmap_sizes[i]];
    }

    return Self{
        .meta_size = meta_size,
        .meta_data = meta_data,
        .total_size = total_size,
        .total_data = total_data,
        .buffer_size = buffer_size,
        .buffer_data = buffer_data,
        .bitmap_count = bitmap_count,
        .bitmap_size = bitmap_size,
        .bitmap_data = bitmap_data,
        .bitmap_offsets = bitmap_offsets,
        .bitmap_sizes = bitmap_sizes,
        .bitmap_multipliers = bitmap_multipliers,
        .bitmap_pointers = bitmap_pointers,
    };
}

pub fn get_bitmap_index(self: Self, size: usize) usize {
    return @max(1, @min(self.bitmap_count, (63 - @clz(size)) / 3)) - 1;
}

pub fn free(self: Self) void {
    Pager.free(self.meta_data);
    Pager.free(self.total_data);
}

pub fn slice_to_vec(slice: []u8) @Vector(VECTOR_SIZE, u8) {
    return @bitCast(slice[0..VECTOR_SIZE].*);
}

pub fn vec_popcount(vector: @Vector(VECTOR_SIZE, u8)) @Vector(VECTOR_SIZE, u8) {
    return @popCount(vector);
}

pub fn vec_add(vector: @Vector(VECTOR_SIZE, u8)) u8 {
    return @reduce(.Add, vector);
}

pub fn create(self: Self, size: usize) ?usize {
    const bitmap_index = self.get_bitmap_index(size);
    const bitmap_multiplier = self.bitmap_multipliers[bitmap_index];
    const bits_required = (size + bitmap_multiplier - 1) / bitmap_multiplier;
    const bitmap_pointer = self.bitmap_pointers[bitmap_index];
    const bitmap_size = self.bitmap_sizes[bitmap_index];
    const pos_end = bitmap_size * 8;

    var pos_byte: usize = 0;
    var pos_bit: usize = 0;
    var remaining: usize = bits_required;
    var vector = undefined;

    outer: while (pos_bit < pos_end) {
        pos_byte = pos_bit >> 3;

        const is_first_bit = pos_bit % 8 == 0;
        const has_space_for_vector = bitmap_size - pos_byte >= VECTOR_SIZE;
        const should_use_vector = has_space_for_vector and is_first_bit;

        // we're at the beginning of a byte
        // and we have at least VECTOR_SIZE bytes
        // so we can analyze the whole vector
        if (should_use_vector) {
            const slice = bitmap_pointer[pos_byte .. pos_byte + VECTOR_SIZE];
            const slice_vector = slice_to_vec(slice);
            const bit_start = vec_add(@clz(slice_vector));
            const is_gap = bit_start > 0;
            const is_counting = remaining != bits_required;

            // there's a gap of zero bit(s)
            // and we're already counting
            if (is_gap and is_counting) {
                // jump over the gap and reset counter
                remaining = bits_required;
            }

            // jump over all zero bits
            pos_bit += bit_start;
            pos_byte = pos_bit >> 3;

            // NOTE: maybe we could use a popcount somehow
            const bit_end = vec_add(@ctz(slice_vector));
            const remaining_bits = VECTOR_BIT_SIZE - bit_start - bit_end;

            // there might be enough free space
            if (remaining_bits >= bits_required) {
                var i: usize = 0;
                while (i < remaining_bits) {
                    // the bit is zero so we skip it,
                    // reset counter and jump to outer loop
                    if (((bitmap_pointer[pos_byte] >> @as(u3, @truncate(pos_bit))) & 1) == 0) {
                        pos_bit += 1;
                        remaining = bits_required;
                        continue :outer;
                    }

                    // we increment by one and keep iterating
                    else {
                        i += 1;
                        pos_bit += 1;
                        remaining -= 1;

                        if (remaining == 0) {
                            return (pos_bit - bits_required) * bitmap_multiplier;
                        }
                    }
                }
            }

            // there isn't enough free space
            else {
                // jump over to the next vector and reset counter
                pos_bit += remaining_bits + bit_end;
                remaining = bits_required;
                continue;
            }
        }

        // search bit by bit in a byte
        else {
            // FIXME: this should be the start
            // the end is 8 - start
            const remaining_bits = pos_bit % 8;

            var i: usize = 0;
            while (i < remaining_bits) {
                // the bit is zero so we skip it,
                // reset counter and jump to outer loop
                if (((bitmap_pointer[pos_byte] >> @as(u3, @truncate(pos_bit))) & 1) == 0) {
                    pos_bit += 1;
                    remaining = bits_required;
                    continue :outer;
                }

                // we increment by one and keep iterating
                else {
                    i += 1;
                    pos_bit += 1;
                    remaining -= 1;

                    if (remaining == 0) {
                        return (pos_bit - bits_required) * bitmap_multiplier;
                    }
                }
            }
        }
    }

    return null;
}

// pub fn destroy(slice: *const []u8) void {
//     // remove from buffer
//     // set bits to 1 and bubble up
// }

test "Buffer.init" {
    const buffer = init(4096);
    defer buffer.free();

    buffer.bitmap_data[0] = 0;
    const o1 = buffer.create(13);
    buffer.bitmap_data[1] = 0;
    const o2 = buffer.create(17);

    print("o1: {any}\n", .{o1});
    print("o2: {any}\n", .{o2});
}
