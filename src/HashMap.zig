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

        inline fn get_index(hash: config.record.hash.type) usize {
            const is_power_of_two = (config.record.count & (config.record.count - 1)) == 0;

            if (is_power_of_two) {
                return hash & (config.record.count - 1);
            } else {
                return hash % (config.record.count - 1);
            }
        }

        pub fn put(self: *Self, hash: config.record.hash.type, key: []u8, value: []u8) !void {
            if (config.record.key == .type) {
                if (key.len != @sizeOf(config.record.key.type)) {
                    return error.InvalidKeyLength;
                }
            }

            if (config.record.value == .type) {
                if (value.len != @sizeOf(config.record.value.type)) {
                    return error.InvalidKeyLength;
                }
            }

            const index = get_index(hash);
            const record = self.records[index];
            const hash_equals = record.hash == hash;
            const key_equals = std.mem.eql(u8, key, switch (config.record.key) {
                .type => std.mem.asBytes(&record.key),
                .max_size => record.data[0..record.key_length],
            });

            if (hash_equals and key_equals or record.temperature < self.random_temperature.next()) {
                self.free(record);
                self.records[index] = CustomRecord{
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
                            // TODO: extract into utils
                            .max_size => |v| @as(std.meta.Int(.unsigned, Utils.bits_needed(k + v)), @intCast(key.len + value.len)),
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
        }

        pub fn get(self: *Self, hash: config.record.hash.type, key: []u8) ?[]u8 {
            const index = get_index(hash);
            var record = self.records[index];

            if (record.hash == 0 or record.hash != hash or std.mem.eql(u8, key, switch (config.record.key) {
                .type => std.mem.asBytes(&record.key),
                .max_size => record.data[0..record.key_length],
            }) == false) {
                return null;
            }

            const should_warm_up = self.random_warming_rate.next() < config.record.temperature.warming_rate;

            if (should_warm_up) {
                record.temperature = if (record.temperature < std.math.maxInt(config.record.temperature.type) - 1) record.temperature + 1 else 0;

                var victim = self.records[self.random_index.next()];

                victim.temperature = if (victim.temperature < std.math.maxInt(config.record.temperature.type) - 1) victim.temperature + 1 else 0;
            }

            return switch (config.record.value) {
                .type => std.mem.asBytes(&record.value),
                .max_size => switch (config.record.key) {
                    .type => record.data[0..record.value_length],
                    .max_size => record.data[record.key_length .. record.key_length + record.value_length],
                },
            };
        }

        fn free(_: Self, record: CustomRecord) void {
            if (switch (config.record.key) {
                .type => switch (config.record.value) {
                    .type => false,
                    .max_size => record.value_length != 0,
                },
                .max_size => switch (config.record.value) {
                    .type => record.key_length != 0,
                    .max_size => record.total_length != 0,
                },
            }) {
                allocator.free(record.data[0..switch (config.record.key) {
                    .type => switch (config.record.value) {
                        .type => unreachable,
                        .max_size => record.value_length,
                    },
                    .max_size => switch (config.record.value) {
                        .type => record.key_length,
                        .max_size => record.total_length,
                    },
                }]);
            }
        }

        pub fn delete(self: *Self, hash: config.record.hash.type, key: []u8) void {
            const index = get_index(hash);
            const record = self.records[index];
            const hash_equals = record.hash == hash;
            const key_equals = std.mem.eql(u8, key, switch (config.record.key) {
                .type => std.mem.asBytes(&record.key),
                .max_size => record.data[0..record.key_length],
            });

            if (hash_equals and key_equals) {
                self.free(record);
                self.records[index] = undefined;
            }
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
