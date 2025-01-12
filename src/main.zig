const std = @import("std");
const BufferAllocator = @import("BufferAllocator.zig");

pub fn main() !void {
    const buffer = BufferAllocator.init(4096);

    const o1 = buffer.create(13);
    // const o2 = buffer.create(17);

    std.debug.print("o1: {any}\n", .{o1});
    // std.debug.print("o2: {any}\n", .{o2});
}
