const std = @import("std");
const PagerAllocator = @import("PagerAllocator.zig");
const Position = @import("Position.zig");
const Config = @import("Config.zig");

const posix = std.posix;
const mmap = posix.mmap;
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;

const Self = @This();

pub fn get_size() usize {

}

pub fn init(memory: []u8, config: Config) Self {
    const meta_size: u64 = 4096;
    const meta_data = PagerAllocator.alloc(meta_size);
    const total_size = bitmap_size + buffer_size;
    const total_data = PagerAllocator.alloc(total_size);
    const bitmap_data = total_data[0..bitmap_size];
    const buffer_data = total_data[bitmap_size .. bitmap_size + buffer_size];

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

pub fn free(self: Self, position: Position) void {
    // TODO
}
