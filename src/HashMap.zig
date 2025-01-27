const std = @import("std");
const Config = @import("Config.zig");
const record_create = @import("Record.zig").create;
const Random = @import("Random.zig");
const Utils = @import("Utils.zig");
const Constants = @import("Constants.zig");
const ttl_create = @import("Ttl.zig").create;

const xxhash = std.hash.XxHash64.hash;
const expect = std.testing.expect;

pub fn create(config: Config) type {
    const Record = record_create(config);
    const Ttl = ttl_create(config);

    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;
    const hash_type = config.record.hash.type;
    const temp_type = config.record.temperature.type;
    const record_count = config.record.count;

    const HashMap = struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        ttl: Ttl,

        random_index: Random.create(usize),
        // NOTE: should be in Record but Record
        // is comptime so we cannot init it
        random_warming_rate: Random.create(f64),
        random_temperature: Random.create(temp_type),

        records: [record_count]Record.Type,

        pub fn init(allocator: std.mem.Allocator) Self {
            const ttl = Ttl.init();
            var records = [_]Record.Type{undefined} ** record_count;

            for (0..record_count) |index| {
                records[index] = Record.default();
            }

            return Self{
                .allocator = allocator,

                .ttl = ttl,

                .random_warming_rate = Random.create(f64).init(record_count, {}),
                .random_index = Random.create(usize).init(record_count, record_count),
                .random_temperature = Random.create(temp_type).init(record_count, std.math.maxInt(temp_type)),

                .records = records,
            };
        }

        pub fn put(self: *Self, hash: hash_type, key: []u8, value: []u8, ttl: ttl_type) !void {
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

            const index = Utils.get_index(hash_type, record_count, hash);
            const record = self.records[index];
            const hash_undefined = record.hash == 0;
            const hash_equals = record.hash == hash;
            const key_equals = Utils.buffer_equals(key, Record.get_key(record));

            if (hash_undefined or (hash_equals and key_equals) or Record.should_overwrite(self.random_temperature.next(), record)) {
                const ttl_value = if (config.record.ttl) |_|
                    try self.ttl.encode(self.ttl.get_now_with_ttl(ttl))
                else {};

                Record.free(self.allocator, record);
                self.records[index] = try Record.new(self.allocator, hash, key, value, ttl_value);
            }
        }

        pub fn get(self: *Self, hash: hash_type, key: []u8) !?[]u8 {
            const index = Utils.get_index(hash_type, record_count, hash);
            var record = self.records[index];

            if (record.hash == 0 or record.hash != hash or Utils.buffer_equals(key, Record.get_key(record)) == false) {
                return null;
            }

            if (config.record.ttl) |_| {
                const now = std.time.milliTimestamp();
                const ttl = try self.ttl.decode(record.ttl);

                if (now > ttl) {
                    self.free(index, record);
                    return null;
                }
            }

            if (Record.should_warm_up(self.random_warming_rate.next())) {
                Record.increase_temperature(&record);

                var victim = self.get_victim();

                Record.decrease_temperature(&victim);
            }

            return Record.get_value(record);
        }

        pub fn delete(self: *Self, hash: hash_type, key: []u8) void {
            const index = Utils.get_index(hash_type, record_count, hash);
            const record = self.records[index];
            const hash_equals = record.hash == hash;
            const key_equals = Utils.buffer_equals(key, Record.get_key(record));

            if (hash_equals and key_equals) {
                self.free(index, record);
            }
        }

        inline fn get_victim(self: *Self) Record.Type {
            return self.records[self.random_index.next()];
        }

        inline fn free(self: *Self, index: usize, record: Record.Type) void {
            Record.free(self.allocator, record);
            self.records[index] = Record.default();
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

    const allocator = std.testing.allocator;

    const hash = xxhash(0, "hashhash");
    const key: []u8 = @constCast("hashhash")[0..];
    const value: []u8 = @constCast("test")[0..];
    const ttl = 1;

    const HashMap = create(config);

    var hash_map = HashMap.init(allocator);

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

    if (try hash_map.get(hash, key)) |slice| {
        try expect(std.mem.eql(u8, slice, value));
    } else {
        try expect(false);
    }

    std.time.sleep(2000 * 1000000);

    try expect(try hash_map.get(hash, key) == null);
}
