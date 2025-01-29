const std = @import("std");
const Config = @import("Config.zig");
const Utils = @import("Utils.zig");

pub fn create(config: Config) type {
    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;
    const max_size = if (config.record.ttl) |ttl| ttl.max_size else 0;
    const max_value = if (config.record.ttl) |ttl| ttl.max_value else 0;
    const timestamp_multiplier = if (config.record.ttl) |ttl| @intFromEnum(ttl.resolution) else 1;

    return struct {
        const Self = @This();

        timestamp_ref: u64,
        timestamp_max: u64,

        pub fn init() Self {
            const timestamp_ref = @as(u64, @intCast(std.time.milliTimestamp())) / timestamp_multiplier;
            const timestamp_max = (timestamp_ref * timestamp_multiplier) + (max_size * timestamp_multiplier);

            return Self{
                .timestamp_ref = timestamp_ref,
                .timestamp_max = timestamp_max,
            };
        }

        pub inline fn encode(self: Self, value: u64) !ttl_type {
            if (value > self.timestamp_max) {
                return error.TimestampOutOfRange;
            }

            return @intCast((value / timestamp_multiplier) - self.timestamp_ref);
        }

        pub inline fn decode(self: Self, value: ttl_type) !u64 {
            if (value > max_size) {
                return error.TimestampOutOfRange;
            }

            return (self.timestamp_ref + @as(u64, value)) * timestamp_multiplier;
        }

        pub inline fn get_now_with_ttl(_: Self, value: ttl_type) !u64 {
            if (value > max_value) {
                return error.TimestampOutOfRange;
            }

            return @as(u64, @intCast(std.time.milliTimestamp())) + (value * timestamp_multiplier);
        }
    };
}
