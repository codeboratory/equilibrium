const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;

const BitmapAllocator = @This();

allocator: Allocator,
data: []u8,
data_size: usize,
data_ptr: usize,
bitmap: []u8,
bitmap_ptr: usize,
bitmap_size: usize,

pub fn init(allocator: Allocator, size: usize) !BitmapAllocator {
    const bitmap_size = @divExact(size, 8);
    const data = try allocator.alloc(u8, size);
    const bitmap = try allocator.alloc(u8, bitmap_size);

    @memset(data, 0);
    @memset(bitmap, 0);

    return BitmapAllocator{ .allocator = allocator, .data = data, .data_size = size, .data_ptr = @intFromPtr(data[0..].ptr), .bitmap = bitmap, .bitmap_ptr = @intFromPtr(bitmap[0..].ptr), .bitmap_size = bitmap_size };
}

pub fn free(self: BitmapAllocator) void {
    self.allocator.free(self.data);
    self.allocator.free(self.bitmap);
}

pub fn create(self: BitmapAllocator, value: []u8) ?*const []u8 {
    const value_length = @as(u64, @intFromFloat(std.math.ceil(@as(f64, @floatFromInt(value.len)) / 8))) * 8;
    const bitmap_offset = value_length / 8;

    if (value_length > self.bitmap_size) {
        return null;
    }

    for (0..self.bitmap_size) |i| {
        if (i + bitmap_offset > self.bitmap_size - 1) {
            return null;
        }

        const bitmap_slice = self.bitmap[i .. i + bitmap_offset];

        if (std.mem.allEqual(u8, bitmap_slice, 0)) {
            @memset(bitmap_slice, 1);
            @memcpy(self.data[(i * 8) .. (i * 8) + value.len], value);

            return &self.data[(i * 8) .. (i * 8) + value_length];
        }
    }

    return null;
}

fn get_index(array_ptr: usize, value: *u8) usize {
    return (@intFromPtr(value) - array_ptr) / @sizeOf(u8);
}

pub fn destroy(self: BitmapAllocator, value: *const []u8) void {
    const data_offset = get_index(self.data_ptr, &value.*[0]);
    const data_length = value.len;
    const bitmap_offset = @divExact(data_offset, 8);
    const bitmap_length = @divExact(data_length, 8);

    @memset(self.data[data_offset .. data_offset + data_length], 0);
    @memset(self.bitmap[bitmap_offset .. bitmap_offset + bitmap_length], 0);
}

test "BitmapAllocator.init" {
    const length = 128;
    const bitmap_allocator = try BitmapAllocator.init(test_allocator, length);
    defer bitmap_allocator.free();

    try expect(bitmap_allocator.data.len == length);
    try expect(bitmap_allocator.bitmap.len == length / 8);
}

test "BitmapAllocator.create | Enough space" {
    const bitmap_allocator = try BitmapAllocator.init(test_allocator, 128);
    defer bitmap_allocator.free();

    var string = "Hello, World!".*;
    const bytes: []u8 = &string;
    const maybe_data_ptr = bitmap_allocator.create(bytes);

    if (maybe_data_ptr) |_| {
        try expect(std.mem.eql(u8, bitmap_allocator.data[0..bytes.len], bytes));
        try expect(bitmap_allocator.bitmap[0] == 1);
        try expect(bitmap_allocator.bitmap[1] == 1);
    } else {
        try expect(false);
    }
}

test "BitmapAllocator.create | Not enough space" {
    const bitmap_allocator = try BitmapAllocator.init(test_allocator, 8);
    defer bitmap_allocator.free();

    var string = "Hello, World!".*;
    const bytes: []u8 = &string;
    const maybe_data_ptr = bitmap_allocator.create(bytes);

    try expect(maybe_data_ptr == null);
}

test "BitmapAllocator.destroy" {
    const bitmap_allocator = try BitmapAllocator.init(test_allocator, 128);
    defer bitmap_allocator.free();

    var string = "Hello, World!".*;
    const bytes: []u8 = &string;
    const maybe_data_ptr = bitmap_allocator.create(bytes);

    if (maybe_data_ptr) |data_ptr| {
        bitmap_allocator.destroy(data_ptr);

        try expect(std.mem.allEqual(u8, bitmap_allocator.data[0..data_ptr.len], 0));
        try expect(bitmap_allocator.bitmap[0] == 0);
        try expect(bitmap_allocator.bitmap[1] == 0);
    } else {
        try expect(false);
    }
}
