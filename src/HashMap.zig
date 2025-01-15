const std = @import("std");
const Config = @import("Config.zig");
const createRecord = @import("Record.zig").create;
const xxhash = std.hash.XxHash64.hash;
const Utils = @import("Utils.zig");

const allocator = std.heap.page_allocator;
const void_value = {};
const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));

pub fn create(config: Config) type {
    const Record = createRecord(config);

    const ttl_type = if (config.record.ttl) |t| t.size else void;

    const HashMap = struct {
        const Self = @This();

        records: [config.table.record_count]Record,

        pub fn init() Self {
            return Self{
                .records = [_]Record{undefined} ** config.table.record_count,
            };
        }

        pub fn put(self: *Self, hash: config.record.hash.size, key: []u8, value: []u8, ttl: ttl_type) !void {
            self.records[0] = Record{
                .hash = hash,
                .key = switch (config.record.key) {
                    .size => block: {
                        const bytes = @sizeOf(config.record.key.size);
                        var tmp_array: [bytes]u8 = undefined;

                        @memset(tmp_array[0..], 0);
                        @memcpy(tmp_array[0..key.len], key);

                        break :block std.mem.readInt(config.record.key.size, &tmp_array, .big);
                    },
                    .max_size => {},
                },
                .key_length = switch (config.record.key) {
                    .size => {},
                    .max_size => @intCast(key.len),
                },
                .value = switch (config.record.value) {
                    .size => block: {
                        const bytes = @sizeOf(config.record.value.size);
                        var tmp_array: [bytes]u8 = undefined;

                        @memset(tmp_array[0..], 0);
                        @memcpy(tmp_array[0..value.len], value);

                        break :block std.mem.readInt(config.record.value.size, &tmp_array, .big);
                    },
                    .max_size => {},
                },
                .value_length = switch (config.record.value) {
                    .size => {},
                    .max_size => @intCast(value.len),
                },
                .total_length = switch (config.record.key) {
                    .size => {},
                    .max_size => |k| switch (config.record.value) {
                        .size => {},
                        .max_size => |v| @as(std.meta.Int(.unsigned, Utils.bits_needed(k + v)), @intCast(key.len + value.len)),
                    },
                },
                .temperature = 127,
                .ttl = if (config.record.ttl == null) {} else ttl,
                .data = block: {
                    if (config.record.key == .size and config.record.value == .size) {
                        break :block {};
                    } else {
                        const total_length = length: {
                            const key_length = switch (config.record.key) {
                                .size => 0,
                                .max_size => key.len,
                            };

                            const value_length = switch (config.record.value) {
                                .size => 0,
                                .max_size => value.len,
                            };

                            break :length key_length + value_length;
                        };

                        const data = try allocator.alloc(u8, total_length);

                        if (config.record.key == .max_size and config.record.value == .size) {
                            @memcpy(data, key);
                        }

                        if (config.record.key == .size and config.record.value == .max_size) {
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

        pub fn check(self: Self) void {
            const records = self.records;

            std.debug.print("check: {any}\n", .{records[0]});
        }
    };

    return HashMap;
}

test "Record" {
    const config = Config{
        .record = .{
            .layout = .small,
            .hash = .{
                .size = u64,
            },
            .key = .{
                .size = u64,
                // .max_size = 1024,
            },
            .value = .{
                // .size = u256,
                .max_size = 64 * 1024 * 1024, // 64 Mb
            },
            .temperature = .{
                .size = u8,
                .warming_rate = 0.05,
            },
            .ttl = null,
            // .ttl = .{
            //     .size = u20,
            //     .resolution = .s,
            // },
        },
        .table = .{
            .record_count = 1024,
        },
        .allocator = .{
            .chunk_size = 32 * 1024, // 32 Kb
        },
    };

    const hash = xxhash(0, "hashhash");
    const key: []u8 = @constCast("hashhash")[0..];
    const value: []u8 = @constCast("Hello, World!")[0..];

    var hash_map = create(config).init();

    hash_map.check();
    try hash_map.put(hash, key, value, {});
    hash_map.check();
}
