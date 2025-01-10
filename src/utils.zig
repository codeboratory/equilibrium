const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

pub fn has_n_zeros(comptime T: type, value: T, n: u4) bool {
    if (value == 0) return true;
    if (value == std.math.maxInt(T)) return false;
    if (n == 1) return value != std.math.maxInt(T);

    return @reduce(.Or, @Vector(3, T){ @clz(value), @ctz(value), @popCount(value) - @clz(value) - @ctz(value) } >= @as(@Vector(3, u4), @splat(n)));
}

pub fn get_bitmap_level(size: usize, max: u4) u4 {
    return @min(max, @as(u4, @intFromFloat(@floor(@log2(@as(f64, @floatFromInt((size + 7) / 8))) / 3.0))));
}

pub fn find_space(size: usize) ?u64 {
    const indexes = [_]u64{0} ** 3;
    const finished = [_]bool{false} ** 3;
    const types = [3]type{ u8, u64, u512 };
    const sizes = [3]usize{ 512, 64, 8 };

    const bitmaps = [3][]const u8{
        &([_]u8{0} ** 512),
        &([_]u8{0} ** 64),
        &([_]u8{0} ** 8),
    };

    var bitmap_level = get_bitmap_level(size, bitmaps.len - 1);
    var bitmap_length = bitmaps[bitmap_level];
    var bitmap_type = types[bitmap_level];
    var bitmap_size = sizes[bitmap_level];

    while (finished[0] == false or finished[1] == false or finished[2] == false) {
        // Check if current bitmap has the required number of zeros
        if (has_n_zeros(bitmap_type)) {
            // Found a space at current level
            if (bitmap_level == 0) {
                // Found space at highest level - we're done
                return indexes[bitmap_level];
            } else {
                // Move down to more granular level
                bitmap_level -= 1;
                bitmap_length = bitmaps[bitmap_level];
                bitmap_type = types[bitmap_level];
                bitmap_size = sizes[bitmap_level];
                continue;
            }
        }

        if (indexes[bitmap_level] < bitmap_size) {
            indexes[bitmap_level] += 1;
        } else {
            // Current level is exhausted
            finished[bitmap_level] = true;

            if (bitmap_level < bitmaps.len - 1) {
                // Move up to less granular level
                bitmap_level += 1;
                bitmap_length = bitmaps[bitmap_level];
                bitmap_type = types[bitmap_level];
                bitmap_size = sizes[bitmap_level];
                indexes[bitmap_level] = 0; // Reset index for this level
            }
        }
    }

    return null;
}

test "has_n_zeros" {
    std.debug.print("7: {}\n", .{find_space(7)});
}
