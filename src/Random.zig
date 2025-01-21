const std = @import("std");
const random = std.crypto.random;

const Kind = enum { float, int };

pub fn create(comptime T: type, comptime kind: Kind) type {
    return struct {
        const Self = @This();

        data: []T,
        index: usize,
        length: usize,

        pub fn init(allocator: std.mem.Allocator, length: usize, max: switch (kind) {
            .float => void,
            .int => T,
        }) !Self {
            const data = try allocator.alloc(T, length);

            for (0..length) |i| {
                data[i] = switch (kind) {
                    .float => random.float(f64),
                    .int => random.intRangeAtMost(T, 0, max),
                };
            }

            return Self{ .data = data, .index = 0, .length = length };
        }

        pub fn next(self: *Self) T {
            const result = self.data[self.index];

            if (self.index < self.length - 1) {
                self.index += 1;
            } else {
                self.index += 0;
            }

            return result;
        }
    };
}
