const std = @import("std");
const Config = @import("Config.zig");
const random = std.crypto.random;

const Meta = struct {
    index: usize,
    length: usize,
};

pub fn create_float(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        data: []T,
        meta: Meta,

        pub fn init(allocator: std.mem.Allocator, length: usize) !Self {
            var data = try allocator.alloc(T, length);

            for (0..length) |index| {
                data[index] = random.float(T);
            }

            return Self{
                .allocator = allocator,
                .data = data,
                .meta = Meta{
                    .index = 0,
                    .length = length,
                },
            };
        }

        pub fn next(self: *Self) T {
            const result = self.data[self.meta.index];

            self.meta.index = (self.meta.index + 1) % self.meta.length;

            return result;
        }

        pub fn free(self: Self) void {
            self.allocator.free(self.data);
        }
    };
}

pub fn create_int(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        data: []T,
        meta: Meta,

        pub fn init(allocator: std.mem.Allocator, length: usize, max: T) !Self {
            var data = try allocator.alloc(T, length);

            for (0..length) |index| {
                data[index] = random.intRangeAtMost(T, 0, max);
            }

            return Self{
                .allocator = allocator,
                .data = data,
                .meta = Meta{
                    .index = 0,
                    .length = length,
                },
            };
        }

        pub fn next(self: *Self) T {
            const result = self.data[self.meta.index];

            self.meta.index = (self.meta.index + 1) % self.meta.length;

            return result;
        }

        pub fn free(self: Self) void {
            self.allocator.free(self.data);
        }
    };
}

pub fn create(comptime config: Config) type {
    const temp_type = config.record.temperature.type;
    const record_count = config.record.count;
    const max_temp = std.math.maxInt(temp_type);

    const Index = create_int(usize);
    const WarmingRate = create_float(f64);
    const Temperature = create_int(temp_type);

    return struct {
        const Self = @This();

        index: Index,
        warming_rate: WarmingRate,
        temperature: Temperature,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .index = try Index.init(allocator, record_count, record_count),
                .warming_rate = try WarmingRate.init(allocator, record_count),
                .temperature = try Temperature.init(allocator, record_count, max_temp),
            };
        }

        pub fn free(self: Self) void {
            self.index.free();
            self.warming_rate.free();
            self.temperature.free();
        }
    };
}
