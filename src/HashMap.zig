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

pub fn create(config: Config) type {
    const CustomRecord = Record.create(config);

    const HashMap = struct {
        const Self = @This();

        random_warming_rate: Random.create(f64),
        random_index: Random.create(usize),
        random_temperature: Random.create(config.record.temperature.type),

        records: [config.record.count]CustomRecord,

        pub fn init() Self {
            return Self{
                .random_warming_rate = Random.create(f64).init(config.record.count, {}),
                .random_index = Random.create(usize).init(config.record.count, config.record.count),
                .random_temperature = Random.create(config.record.temperature.type).init(config.record.count, std.math.maxInt(config.record.temperature.type)),

                .records = [_]CustomRecord{undefined} ** config.record.count,
            };
        }

        pub fn put(self: *Self, hash: config.record.hash.type, key: []u8, value: []u8) !void {
            switch (config.record.key) {
                .type => |T| if (key.len != @sizeOf(T)) return error.InvalidKeyLength,
                .max_size => |max| if (key.len > max) return error.InvalidKeyLength,
            }

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
                self.records[index] = try create_record(hash, key, value);
            }
        }

        pub fn get(self: *Self, hash: config.record.hash.type, key: []u8) ?[]u8 {
            const index = get_index(hash);
            var record = self.records[index];

            if (record.hash == undefined or record.hash != hash or Utils.buffer_equals(key, get_key(record)) == false) {
                return null;
            }

            // TODO: check TTL

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

        inline fn get_key(record: CustomRecord) []u8 {
            return switch (config.record.key) {
                .type => std.mem.asBytes(@constCast(&record.key))[0..],
                .max_size => record.data[0..record.key_length],
            };
        }

        inline fn get_value(record: CustomRecord) []u8 {
            return switch (config.record.value) {
                .type => std.mem.asBytes(&record.value),
                .max_size => switch (config.record.key) {
                    .type => record.data[0..record.value_length],
                    .max_size => record.data[record.key_length .. record.key_length + record.value_length],
                },
            };
        }

        inline fn should_warm_up(self: *Self) bool {
            return self.random_warming_rate.next() < config.record.temperature.warming_rate;
        }

        inline fn increase_temperature(record: *CustomRecord) void {
            record.temperature = Utils.saturating_add(config.record.temperature.type, record.temperature, 1);
        }

        inline fn decrease_temperature(record: *CustomRecord) void {
            record.temperature = Utils.saturating_sub(config.record.temperature.type, record.temperature, 1);
        }

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

        inline fn free(record: CustomRecord) void {
            if (can_data_be_freed(record)) {
                allocator.free(record.data[0..get_total_length(record)]);
            }
        }

        inline fn get_index(hash: config.record.hash.type) usize {
            const is_power_of_two = (config.record.count & (config.record.count - 1)) == 0;

            if (is_power_of_two) {
                return hash & (config.record.count - 1);
            } else {
                return hash % config.record.count;
            }
        }

        inline fn should_overwrite(self: *Self, record: CustomRecord) bool {
            return record.temperature < self.random_temperature.next();
        }

        inline fn create_record(hash: config.record.hash.type, key: []u8, value: []u8) !CustomRecord {
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
        },
        .allocator = .{
            .chunk_size = 32 * 1024, // 32 Kb
        },
    };

    const hash = xxhash(0, "hashhash");
    const key: []u8 = @constCast("hashhash")[0..];
    const value: []u8 = @constCast("test")[0..];

    const HashMap = create(config);

    var hash_map = HashMap.init();

    try expect(hash_map.get(hash, key) == null);

    try hash_map.put(hash, key, value);

    if (hash_map.get(hash, key)) |slice| {
        try expect(std.mem.eql(u8, slice, value));
    } else {
        try expect(false);
    }

    hash_map.delete(hash, key);

    try expect(hash_map.get(hash, key) == null);
}
