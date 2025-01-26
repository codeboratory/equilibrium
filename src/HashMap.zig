const std = @import("std");
const Config = @import("Config.zig");
const Record = @import("Record.zig");
const Random = @import("Random.zig");
const Utils = @import("Utils.zig");
const Constants = @import("Constants.zig");

const xxhash = std.hash.XxHash64.hash;
const expect = std.testing.expect;

// TODO: use bitmap allocator instead
const allocator = std.heap.page_allocator;

// NOTE: can I somehow split this up
// into smaller chunks to make it
// more readable?
pub fn create(config: Config) type {
    const CustomRecord = Record.create(config);

    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;

    const HashMap = struct {
        const Self = @This();

        // TODO: move into a struct
        value_max: usize,
        timestamp_multiplier: usize,
        timestamp_ref: u64,
        timestamp_max: u64,

        random_index: Random.create(usize),

        // NOTE: maybe move into Record
        random_warming_rate: Random.create(f64),
        random_temperature: Random.create(config.record.temperature.type),

        // NOTE: maybe use page allocator instead
        // so this could be provided in a JSON config
        records: [config.record.count]CustomRecord,

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

                .random_warming_rate = Random.create(f64).init(config.record.count, {}),
                .random_index = Random.create(usize).init(config.record.count, config.record.count),
                .random_temperature = Random.create(config.record.temperature.type).init(config.record.count, std.math.maxInt(config.record.temperature.type)),

                .records = [_]CustomRecord{undefined} ** config.record.count,
            };
        }

        pub fn put(self: *Self, hash: config.record.hash.type, key: []u8, value: []u8, ttl: ttl_type) !void {
            // TODO: extract errors
            switch (config.record.key) {
                .type => |T| if (key.len != @sizeOf(T)) return error.InvalidKeyLength,
                .max_size => |max| if (key.len > max) return error.InvalidKeyLength,
            }

            // TODO: extract errors
            switch (config.record.value) {
                .type => |T| if (value.len != @sizeOf(T)) return error.InvalidValueLength,
                .max_size => |max| if (value.len > max) return error.InvalidValueLength,
            }

            const index = get_index(hash);
            const record = self.records[index];
            const hash_equals = record.hash == hash;
            const key_equals = Utils.buffer_equals(key, get_key(record));

            if (hash_equals and key_equals or self.should_overwrite(record)) {
                free(record);
                self.records[index] = try self.create_record(hash, key, value, ttl);
            }
        }

        pub fn get(self: *Self, hash: config.record.hash.type, key: []u8) !?[]u8 {
            const index = get_index(hash);
            var record = self.records[index];

            if (record.hash == undefined or record.hash != hash or Utils.buffer_equals(key, get_key(record)) == false) {
                return null;
            }

            if (config.record.ttl) |_| {
                // NOTE: what if now > timestamp_max?
                // TODO: compare if it's faster
                // to encode now or decode ttl
                const now = std.time.milliTimestamp();
                const decoded_ttl = try self.decode_ttl(record.ttl);

                if (now > decoded_ttl) {
                    free(record);
                    self.records[index] = undefined;

                    return null;
                }
            }

            if (self.should_warm_up()) {
                increase_temperature(&record);

                var victim = self.get_victim();

                decrease_temperature(&victim);
            }

            return get_value(record);
        }

        pub fn delete(self: *Self, hash: config.record.hash.type, key: []u8) void {
            const index = get_index(hash);
            const record = self.records[index];
            const hash_equals = record.hash == hash;
            const key_equals = Utils.buffer_equals(key, get_key(record));

            if (hash_equals and key_equals) {
                free(record);
                self.records[index] = undefined;
            }
        }

        inline fn get_victim(self: *Self) CustomRecord {
            return self.records[self.random_index.next()];
        }

        // NOTE: maybe move to Record
        inline fn get_key(record: CustomRecord) []u8 {
            return switch (config.record.key) {
                .type => std.mem.asBytes(@constCast(&record.key))[0..],
                .max_size => record.data[0..record.key_length],
            };
        }

        // NOTE: maybe move to Record
        inline fn get_value(record: CustomRecord) []u8 {
            return switch (config.record.value) {
                .type => std.mem.asBytes(&record.value),
                .max_size => switch (config.record.key) {
                    .type => record.data[0..record.value_length],
                    .max_size => record.data[record.key_length .. record.key_length + record.value_length],
                },
            };
        }

        // NOTE: maybe move to Record
        inline fn should_warm_up(self: *Self) bool {
            return self.random_warming_rate.next() < config.record.temperature.warming_rate;
        }

        // NOTE: maybe move to Record
        inline fn increase_temperature(record: *CustomRecord) void {
            record.temperature = Utils.saturating_add(config.record.temperature.type, record.temperature, 1);
        }

        // NOTE: maybe move to Record
        inline fn decrease_temperature(record: *CustomRecord) void {
            record.temperature = Utils.saturating_sub(config.record.temperature.type, record.temperature, 1);
        }

        // NOTE: maybe move to Record
        inline fn get_total_length(record: CustomRecord) usize {
            return switch (config.record.key) {
                .type => switch (config.record.value) {
                    .type => unreachable,
                    .max_size => record.value_length,
                },
                .max_size => switch (config.record.value) {
                    .type => record.key_length,
                    .max_size => record.total_length,
                },
            };
        }

        // NOTE: maybe move to Record
        inline fn can_data_be_freed(record: CustomRecord) bool {
            return switch (config.record.key) {
                .type => switch (config.record.value) {
                    .type => false,
                    .max_size => record.value_length != 0,
                },
                .max_size => switch (config.record.value) {
                    .type => record.key_length != 0,
                    .max_size => record.total_length != 0,
                },
            };
        }

        // NOTE: maybe move to Record
        inline fn free(record: CustomRecord) void {
            if (can_data_be_freed(record)) {
                allocator.free(record.data[0..get_total_length(record)]);
            }
        }

        // NOTE: maybe move to Utils
        inline fn get_index(hash: config.record.hash.type) usize {
            const is_power_of_two = (config.record.count & (config.record.count - 1)) == 0;

            if (is_power_of_two) {
                return hash & (config.record.count - 1);
            } else {
                return hash % config.record.count;
            }
        }

        // NOTE: maybe move to Record
        inline fn should_overwrite(self: *Self, record: CustomRecord) bool {
            return record.temperature < self.random_temperature.next();
        }

        // NOTE: maybe move to TTL
        inline fn encode_ttl(self: Self, value: u64) !ttl_type {
            if (value > self.timestamp_max) {
                // TODO: extract errors
                return error.TimestampOutOfRange;
            }

            return @intCast((value / self.timestamp_multiplier) - self.timestamp_ref);
        }

        // NOTE: maybe move to TTL
        inline fn decode_ttl(self: Self, value: ttl_type) !u64 {
            if (value > self.value_max) {
                // TODO: extract errors
                return error.TimestampOutOfRange;
            }

            return (self.timestamp_ref + @as(u64, value)) * self.timestamp_multiplier;
        }

        // NOTE: maybe move to TTL
        inline fn get_now_with_ttl(self: Self, ttl: ttl_type) u64 {
            return @as(u64, @intCast(std.time.milliTimestamp())) + (ttl * self.timestamp_multiplier);
        }

        // NOTE: maybe move to Record
        inline fn create_record(self: Self, hash: config.record.hash.type, key: []u8, value: []u8, ttl: ttl_type) !CustomRecord {
            return CustomRecord{
                .hash = hash,
                .key = switch (config.record.key) {
                    .type => std.mem.bytesToValue(config.record.key.type, key),
                    .max_size => {},
                },
                .key_length = switch (config.record.key) {
                    .type => {},
                    .max_size => @intCast(key.len),
                },
                .value = switch (config.record.value) {
                    .type => std.mem.bytesToValue(config.record.value.type, value),
                    .max_size => {},
                },
                .value_length = switch (config.record.value) {
                    .type => {},
                    .max_size => @intCast(value.len),
                },
                .total_length = switch (config.record.key) {
                    .type => {},
                    .max_size => |k| switch (config.record.value) {
                        .type => {},
                        .max_size => |v| @as(Utils.create_uint(k + v), @intCast(key.len + value.len)),
                    },
                },
                .temperature = std.math.maxInt(config.record.temperature.type) / 2,
                .data = block: {
                    if (config.record.key == .type and config.record.value == .type) {
                        break :block undefined;
                    }

                    const key_length = switch (config.record.key) {
                        .type => 0,
                        .max_size => key.len,
                    };

                    const value_length = switch (config.record.value) {
                        .type => 0,
                        .max_size => value.len,
                    };

                    // TODO: use bitmap allocator instead
                    const data = try allocator.alloc(u8, key_length + value_length);

                    if (config.record.key == .max_size and config.record.value == .type) {
                        @memcpy(data, key);
                    }

                    if (config.record.key == .type and config.record.value == .max_size) {
                        @memcpy(data, value);
                    }

                    if (config.record.key == .max_size and config.record.value == .max_size) {
                        @memcpy(data[0..key.len], key);
                        @memcpy(data[key.len .. key.len + value.len], value);
                    }

                    break :block data.ptr;
                },
                .ttl = if (config.record.ttl) |_|
                    try self.encode_ttl(self.get_now_with_ttl(ttl))
                else
                    undefined,
            };
        }
    };

    return HashMap;
}

test "Record" {
    const config = Config{
        .record = .{
            .count = 1024,
            .layout = .fast,
            .hash = .{
                .type = u64,
            },
            .key = .{
                .type = u64,
                // .max_size = 1024,
            },
            .value = .{
                // .type = u32,
                .max_size = 64 * 1024 * 1024, // 64 Mb
            },
            .temperature = .{
                .type = u8,
                .warming_rate = 0.05,
            },
            // NOTE: maybe ttl could also be .small/.fast
            .ttl = .{
                // ~136 years
                .max_size = 4294967296,
                // NOTE: maybe I could cap the TTL size
                // and make it different from the absolute
                // size which is max_size
                .resolution = .second,
            },
        },
        .allocator = .{
            .chunk_size = 32 * 1024, // 32 Kb
        },
    };

    const hash = xxhash(0, "hashhash");
    const key: []u8 = @constCast("hashhash")[0..];
    const value: []u8 = @constCast("test")[0..];
    const ttl = 1;

    const HashMap = create(config);

    var hash_map = HashMap.init();

    try expect(try hash_map.get(hash, key) == null);

    try hash_map.put(hash, key, value, ttl);

    if (try hash_map.get(hash, key)) |slice| {
        try expect(std.mem.eql(u8, slice, value));
    } else {
        try expect(false);
    }

    hash_map.delete(hash, key);

    try expect(try hash_map.get(hash, key) == null);

    try hash_map.put(hash, key, value, ttl);

    std.time.sleep(2 * 1000000);

    try expect(try hash_map.get(hash, key) == null);
}
