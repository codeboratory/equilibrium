const std = @import("std");
const Config = @import("Config.zig");
const Utils = @import("Utils.zig");

pub fn create(config: Config) type {
    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;

    return struct {
        const Self = @This();

        value_max: usize,
        timestamp_multiplier: usize,
        timestamp_ref: u64,
        timestamp_max: u64,

        pub fn init() Self {
            const value_max = if (config.record.ttl) |ttl| ttl.max_size else 0;
            const timestamp_multiplier = if (config.record.ttl) |ttl| @intFromEnum(ttl.resolution) else 1;
            const timestamp_ref = @as(u64, @intCast(std.time.milliTimestamp())) / timestamp_multiplier;
            const timestamp_max = (timestamp_ref * timestamp_multiplier) + (value_max * timestamp_multiplier);

            return Self{
                .value_max = value_max,
                .timestamp_multiplier = timestamp_multiplier,
                .timestamp_ref = timestamp_ref,
                .timestamp_max = timestamp_max,
            };
        }

        pub inline fn encode(self: Self, value: u64) !ttl_type {
            if (value > self.timestamp_max) {
                // TODO: extract errors
                return error.TimestampOutOfRange;
            }

            return @intCast((value / self.timestamp_multiplier) - self.timestamp_ref);
        }

        pub inline fn decode(self: Self, value: ttl_type) !u64 {
            if (value > self.value_max) {
                // TODO: extract errors
                return error.TimestampOutOfRange;
            }

            return (self.timestamp_ref + @as(u64, value)) * self.timestamp_multiplier;
        }

        pub inline fn get_now_with_ttl(self: Self, ttl: ttl_type) u64 {
            return @as(u64, @intCast(std.time.milliTimestamp())) + (ttl * self.timestamp_multiplier);
        }
    };
}
