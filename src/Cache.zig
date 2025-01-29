const std = @import("std");
const Config = @import("Config.zig");
const Testing = @import("Testing.zig");
const hash_map_create = @import("HashMap.zig").create;

pub fn create(comptime config: Config) type {
    const HashMap = hash_map_create(config);

    return struct {
        const Self = @This();

        hash_map: HashMap,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .hash_map = try HashMap.init(allocator),
            };
        }

        pub fn free(self: Self) void {
            self.hash_map.free();
        }
    };
}
