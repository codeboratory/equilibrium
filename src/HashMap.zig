const std = @import("std");
const Config = @import("Config.zig");
const record_create = @import("Record.zig").create;
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
    const Record = record_create(config);

    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;
    const hash_type = config.record.hash.type;
    const temp_type = config.record.temperature.type;
    const record_count = config.record.count;

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
        random_temperature: Random.create(temp_type),

        // NOTE: maybe use page allocator instead
        // so this could be provided in a JSON config
        records: [record_count]Record.Type,

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

                .random_warming_rate = Random.create(f64).init(record_count, {}),
                .random_index = Random.create(usize).init(record_count, record_count),
                .random_temperature = Random.create(temp_type).init(record_count, std.math.maxInt(temp_type)),

                .records = [_]Record.Type{undefined} ** record_count,
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
            const hash_equals = record.hash == hash;
            const key_equals = Utils.buffer_equals(key, Record.get_key(record));

            if (hash_equals and key_equals or Record.should_overwrite(self.random_temperature.next(), record)) {
                Record.free(allocator, record);
                self.records[index] = try Record.create(allocator, hash, key, value, ttl);
            }
        }

        pub fn get(self: *Self, hash: hash_type, key: []u8) !?[]u8 {
            const index = Utils.get_index(hash_type, record_count, hash);
            var record = self.records[index];

            if (record.hash == undefined or record.hash != hash or Utils.buffer_equals(key, Record.get_key(record)) == false) {
                return null;
            }

            if (config.record.ttl) |_| {
                // NOTE: what if now > timestamp_max?
                // TODO: compare if it's faster
                // to encode now or decode ttl
                const now = std.time.milliTimestamp();
                const decoded_ttl = try self.decode_ttl(record.ttl);

                if (now > decoded_ttl) {
                    Record.free(allocator, record);
                    self.records[index] = undefined;

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
                Record.free(allocator, record);
                self.records[index] = undefined;
            }
        }

        inline fn get_victim(self: *Self) Record.Type {
            return self.records[self.random_index.next()];
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
