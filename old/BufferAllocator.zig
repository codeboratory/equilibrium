const std = @import("std");
const Config = @import("Config.zig");
const Position = @import("Position.zig");
const PagingAllocator = @import("PagingAllocator.zig");
const BitmapAllocator = @import("BitmapAllocator.zig");
const StaticAllocator = @import("StaticAllocator.zig");

const Self = @This();

raw_memory: []u8,
bitmap_allocator: BitmapAllocator,
static_allocator: StaticAllocator,

pub fn init(config: Config) Self {
    const bitmap_size = BitmapAllocator.get_size();
    const static_size = StaticAllocator.get_size();

    const raw_memory = PagingAllocator.alloc(bitmap_size + static_size);

    const bitmap_allocator = BitmapAllocator.init(config, raw_memory[0..bitmap_size]);
    const static_allocator = StaticAllocator.init(config, raw_memory[bitmap_size .. bitmap_size + static_size]);

    return Self{
        .raw_memory = raw_memory,
        .bitmap_allocator = bitmap_allocator,
        .static_allocator = static_allocator,
    };
}

pub fn create(self: Self, size: usize) ?[]u8 {
    const position = self.bitmap_allocator.create(size) orelse return null;
    const slice = self.static_allocator.create(position);

    return slice;
}

pub fn destroy(self: Self, slice: []u8) noreturn {
    self.bitmap_allocator.destroy(slice);
    self.static_allocator.destroy(slice);
}

pub fn free(self: Self) noreturn {
    PagingAllocator.free(self.raw_memory);
}
