const std = @import("std");
const Allocator = std.mem.Allocator;

fn calc_bitmap_space(length: usize, layers: u8) usize {
    var total: usize = 0;

    for (1..layers + 1) |i| {
        total += length / std.math.pow(usize, 8, i);
    }

    return total;
}

test "TEST" {
    std.debug.print("{}\n", .{calc_bitmap_space(4096, 3)});
}
