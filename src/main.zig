const std = @import("std");
const Buffer = @import("Buffer.zig");

pub fn main() !void {
    const buffer = Buffer.init(4096);
    defer buffer.free();

    const o1 = buffer.create(13);
    // const o2 = buffer.create(17);

    std.debug.print("o1: {any}\n", .{o1});
    // std.debug.print("o2: {any}\n", .{o2});
}
