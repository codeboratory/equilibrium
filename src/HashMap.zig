const std = @import("std");
const Config = @import("Config.zig");
// NOTE: I don't like the import
const createRecord = @import("Record.zig").create;
const xxhash = std.hash.XxHash64.hash;
const Utils = @import("Utils.zig");
const Constants = @import("Constants.zig");
const expect = std.testing.expect;
const random = std.crypto.random;

const allocator = std.heap.page_allocator;

pub fn create(config: Config) type {
    const Record = createRecord(config);

    // NOTE: maybe I could create a new struct which
    // will hold all these pre-computed config sizes
    const ttl_type = if (config.record.ttl) |t| t.type else void;
    const buffer_size = switch (config.record.value) {
        .type => |size| @sizeOf(size),
        .max_size => 0,
    };

    const HashMap = struct {
        const Self = @This();

        records: [config.record.count]Record,
        buffer: [buffer_size]u8,
        now: i64,

        pub fn init() Self {
            return Self{
                .records = [_]Record{undefined} ** config.record.count,
                .buffer = [_]u8{0} ** buffer_size,
                .now = std.time.timestamp(),
            };
        }

        pub fn put(self: *Self, hash: config.record.hash.type, key: []u8, value: []u8, ttl: ttl_type) !void {
            const index = hash % config.record.count;
            const record = self.records[index];

            // NOTE: shouldn't be the 2nd and 3rd condition be grouped together?
            // I think this is wrong and it doesn't work the way I want it to work
            if (record.hash == hash or std.mem.eql(u8, key, switch (config.record.key) {
                // NOTE: could this be done in one step?
                .type => block: {
                    const bytes = @sizeOf(config.record.key.type);
                    // NOTE: will this work the same on big endian
                    const size = bytes - (@clz(record.key) / 8);
                    const num: []u8 = @constCast(&@as([bytes]u8, @bitCast(record.key)))[0..size];

                    break :block num;
                },
                .max_size => record.data[0..record.key_length],
                // TODO: precompute random values
            }) or record.temperature < random.intRangeAtMost(config.record.temperature.type, 0, std.math.maxInt(config.record.temperature.type))) {
                self.free(record);

                // NOTE: maybe move into Record?
                self.records[index] = Record{
                    .hash = hash,
                    .key = switch (config.record.key) {
                        // NOTE: could this be done in one step?
                        .type => block: {
                            const bytes = @sizeOf(config.record.key.type);
                            var tmp_array: [bytes]u8 = undefined;

                            @memset(tmp_array[0..], 0);
                            @memcpy(tmp_array[0..key.len], key);

                            break :block std.mem.readInt(config.record.key.type, &tmp_array, Constants.native_endian);
                        },
                        .max_size => {},
                    },
                    .key_length = switch (config.record.key) {
                        .type => {},
                        .max_size => @intCast(key.len),
                    },
                    .value = switch (config.record.value) {
                        // NOTE: could this be done in one step?
                        .type => block: {
                            const bytes = @sizeOf(config.record.value.type);
                            var tmp_array: [bytes]u8 = undefined;

                            @memset(tmp_array[0..], 0);
                            @memcpy(tmp_array[0..value.len], value);

                            break :block std.mem.readInt(config.record.value.type, &tmp_array, Constants.native_endian);
                        },
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
                            .max_size => |v| @as(std.meta.Int(.unsigned, Utils.bits_needed(k + v)), @intCast(key.len + value.len)),
                        },
                    },
                    .temperature = std.math.maxInt(config.record.temperature.type) / 2,
                    .ttl = if (config.record.ttl == null) {} else ttl,
                    .data = block: {
                        if (config.record.key == .type and config.record.value == .type) {
                            break :block undefined;
                        } else {
                            const key_length = switch (config.record.key) {
                                .type => 0,
                                .max_size => key.len,
                            };

                            const value_length = switch (config.record.value) {
                                .type => 0,
                                .max_size => value.len,
                            };

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
                        }
                    },
                };
            }
        }

        pub fn get(self: *Self, hash: config.record.hash.type, key: []u8) ?[]u8 {
            var record = self.records[hash % config.record.count];

            if (record.hash == 0 or record.hash != hash or std.mem.eql(u8, key, switch (config.record.key) {
                // NOTE: ugh I don't like this
                .type => block: {
                    const bytes = @sizeOf(config.record.key.type);
                    const size = bytes - (@clz(record.key) / 8);
                    const num: []u8 = @constCast(&@as([bytes]u8, @bitCast(record.key)))[0..size];

                    break :block num;
                },
                .max_size => record.data[0..record.key_length],
            }) == false) {
                return null;
            }

            if (config.record.ttl) |ttl| {
                if (std.time.timestamp() >= self.now + @as(i64, @intCast(switch (ttl.resolution) {
                    .s => record.ttl,
                    .m => record.tll * 60,
                    .h => record.ttl * 3600,
                    .d => record.ttl * 86400,
                }))) {
                    // TODO: do not do duplicate work
                    self.delete(hash, key);
                    return null;
                }
            }

            // TODO: precompute random values
            if (random.float(f64) < config.record.temperature.warming_rate) {
                record.temperature = if (record.temperature < std.math.maxInt(config.record.temperature.type) - 1) record.temperature + 1 else 0;

                // TODO: precompute random values
                var victim = self.records[random.intRangeAtMost(usize, 0, config.record.count)];

                victim.temperature = if (victim.temperature < std.math.maxInt(config.record.temperature.type) - 1) victim.temperature + 1 else 0;
            }

            return switch (config.record.value) {
                // NOTE: ugh I don't like this
                .type => block: {
                    const bytes = @sizeOf(config.record.value.type);
                    const size = bytes - (@clz(record.value) / 8);
                    const num: []u8 = @constCast(&@as([bytes]u8, @bitCast(record.value)))[0..size];

                    @memset(self.buffer[0..], 0);
                    @memcpy(self.buffer[0..type], num);

                    break :block self.buffer[0..type];
                },
                .max_size => switch (config.record.key) {
                    .type => record.data[0..record.value_length],
                    .max_size => record.data[record.key_length .. record.key_length + record.value_length],
                },
            };
        }

        fn free(_: Self, record: Record) void {
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
            const record = self.records[hash % config.record.count];

            if (record.hash == hash and std.mem.eql(u8, key, switch (config.record.key) {
                // NOTE: ugh I don't like this
                .type => block: {
                    const bytes = @sizeOf(config.record.key.type);
                    const size = bytes - (@clz(record.key) / 8);
                    const num: []u8 = @constCast(&@as([bytes]u8, @bitCast(record.key)))[0..size];

                    break :block num;
                },
                .max_size => record.data[0..record.key_length],
            })) {
                self.free(record);

                self.records[hash % config.record.count] = undefined;
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
                // .type = u256,
                .max_size = 64 * 1024 * 1024, // 64 Mb
            },
            .temperature = .{
                .type = u8,
                .warming_rate = 0.05,
            },
            .ttl = null,
            // .ttl = .{
            //     .type = u25,
            //     .resolution = .s,
            // },
        },
        .allocator = .{
            .chunk_size = 32 * 1024, // 32 Kb
        },
    };

    const hash = xxhash(0, "hashhash");
    const key: []u8 = @constCast("hashhash")[0..];
    const value: []u8 = @constCast("Hello, World!")[0..];

    const HashMap = create(config);

    var hash_map = HashMap.init();

    try expect(hash_map.get(hash, key) == null);

    try hash_map.put(hash, key, value, {});
    // try hash_map.put(hash, key, value, 2);

    if (hash_map.get(hash, key)) |slice| {
        try expect(std.mem.eql(u8, slice, value));
    } else {
        try expect(false);
    }

    // std.time.sleep(std.time.ns_per_s * 3);

    // try expect(hash_map.get(hash, key) == null);

    // try hash_map.put(hash, key, value, 5);

    // if (hash_map.get(hash, key)) |slice| {
    //     try expect(std.mem.eql(u8, slice, value));
    // } else {
    //     try expect(false);
    // }

    hash_map.delete(hash, key);

    try expect(hash_map.get(hash, key) == null);
}
