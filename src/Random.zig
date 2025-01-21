const std = @import("std");
const random = std.crypto.random;

pub fn create(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        index: usize,
        length: usize,

        pub fn init(comptime length: usize, comptime max: if (@typeInfo(T) == .Float) void else T) Self {
            var data = [_]T{undefined} ** length;

            for (&data) |*item| {
                item.* = switch (@typeInfo(T)) {
                    .Float => random.float(T),
                    .Int => random.intRangeAtMost(T, 0, max),
                    else => @compileError("Type must be float or integer"),
                };
            }

            return Self{
                .data = &data,
                .index = 0,
                .length = length,
            };
        }

        pub fn next(self: *Self) T {
            const result = self.data[self.index];
            self.index = (self.index + 1) % self.length;
            return result;
        }
    };
}
