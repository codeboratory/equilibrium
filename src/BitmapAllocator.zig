const std = @import("std");
const PagerAllocator = @import("PagerAllocator.zig");
const Constants = @import("Constants.zig");
const Vector = @import("Vector.zig");
const Position = @import("Position.zig");
const Config = @import("Config.zig");

const posix = std.posix;
const mmap = posix.mmap;
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;

const Self = @This();

memory: []u8,

bitmap_count: u64,
bitmap_size: u64,
bitmap_data: []u8,

bitmap_offsets: []u64,
bitmap_sizes: []u64,
bitmap_multipliers: []u64,

bitmap_pointers: [][]u8,

pub fn get_size(size: usize) usize {}

inline fn get_index(self: Self, size: usize) usize {
    return @max(1, @min(self.bitmap_count, (63 - @clz(size)) / 3)) - 1;
}

pub fn init(memory: []u8, config: Config) Self {
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

    const bitmap_data = total_data[0..bitmap_size];
    const buffer_data = total_data[bitmap_size .. bitmap_size + buffer_size];

    @memset(bitmap_data, 255);

    for (0..bitmap_count) |i| {
        bitmap_pointers[i] = bitmap_data[bitmap_offsets[i] .. bitmap_offsets[i] + bitmap_sizes[i]];
    }

    return Self{
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

pub fn set_bits() noreturn {}

pub fn create(self: Self, size: usize) ?Position {
    const bitmap_index = self.get_index(size);
    const bitmap_multiplier = self.bitmap_multipliers[bitmap_index];
    const bits_required = (size + bitmap_multiplier - 1) / bitmap_multiplier;
    const bitmap_pointer = self.bitmap_pointers[bitmap_index];
    const bitmap_size = self.bitmap_sizes[bitmap_index];
    const vec_count = bitmap_size / Constants.VECTOR_SIZE;

    var remaining: usize = bits_required;

    for (0..vec_count) |vec_index| {
        const byte_pos = vec_index * Constants.VECTOR_SIZE;
        const bitmap_slice = bitmap_pointer[byte_pos .. byte_pos + Constants.VECTOR_SIZE];
        const vec_slice = Vector.from(bitmap_slice);
        const vec_pop = Vector.popcount(vec_slice);
        const vec_sum = Vector.add(vec_pop);
        const not_enough_space = remaining > Constants.VECTOR_BIT_SIZE - vec_sum;
        const not_vector_full = vec_sum > 0;

        // if we don't have enough space and at the same time
        // the vector is not full then we reset remaining
        // and continue to the next vector
        if (not_enough_space and not_vector_full) {
            remaining = bits_required;
            continue;
        }

        // we keep jumping in the current layer
        // with step size equal to VECTOR_SIZE
        for (0..Constants.VECTOR_SIZE) |byte_index| {
            const free_bits_in_byte = vec_pop[byte_index];
            const required_bits_in_byte = @min(8, remaining);
            const remaining_full_byte = remaining == 8;
            const has_full_byte = free_bits_in_byte == 8;
            const remaining_more = remaining > 8;

            // we don't have enough space so we reset remaining
            if (free_bits_in_byte < required_bits_in_byte) {
                remaining = bits_required;
            }

            // we need exactly one full byte and we have one full byte
            else if (remaining_full_byte and has_full_byte) {
                return ((vec_index * Constants.VECTOR_SIZE) + (byte_index * 8)) - bits_required;
            }

            // we need more than one full byte and we have one full byte
            else if (remaining_more and has_full_byte) {
                remaining -= 8;
            }

            // we have to check individual bits
            else {
                const byte = bitmap_slice[byte_index];

                for (0..8) |i| {
                    // if bit is zero we reset remaining
                    if (((byte >> @as(u3, @truncate(i))) & 1) == 0) {
                        remaining = bits_required;
                    }

                    // otherwise we decrease remaining
                    else {
                        remaining -= 1;

                        // and check if we've reached the end
                        if (remaining == 0) {
                            return (vec_index * Constants.VECTOR_SIZE) + (byte_index * 8) + i - bits_required;
                        }
                    }
                }
            }
        }
    }

    return null;
}

pub fn destroy(self: Self, position: Position) noreturn {
    self.set_bits(position);    
}
