const std = @import("std");
const Allocator = std.mem.Allocator;
const xxhash = std.hash.XxHash3.hash;
const random = std.crypto.random;
const expect = std.testing.expect;

const RATE_CONSTANT = 4096;

pub const Record = packed struct {
    const padding = u14;

    data: ?[*]u8,
    hash: u64,
    key_length: u26,
    value_length: u26,
    total_length: u28,
    temperature: u8,
    ttl: u26,
};

const Self = @This();

allocator: Allocator,
record_count: usize,
records: []Record,

random_rate: []u16,
random_rate_length: u16,

random_temperature: []u8,
random_temperature_length: u8,

random_index: []usize,
random_index_length: usize,

fn get_random(comptime T: type, slice: []T, length: T) T {
    if (slice[slice[0]] == length - 1) {
        slice[0] = 1;
    } else {
        slice[0] += 1;
    }

    return slice[slice[0]];
}

fn get_random_rate(self: Self) u16 {
    return get_random(u16, self.random_rate, self.random_rate_length);
}

fn increase_rate(self: Self) bool {
    return self.get_random_rate() < RATE_CONSTANT;
}

fn get_random_temperature(self: Self) u8 {
    return get_random(u8, self.random_temperature, self.random_temperature_length);
}

fn get_random_index(self: Self) usize {
    return get_random(usize, self.random_index, self.random_index_length);
}

fn u16_to_usize(value: u16) usize {
    return @intCast(value);
}

pub fn init(allocator: Allocator, record_count: usize) !Self {
    const records = try allocator.alloc(Record, record_count);

    @memset(std.mem.sliceAsBytes(records), 0);

    const random_rate_length = std.math.maxInt(u16);
    var random_rate = try allocator.alloc(u16, random_rate_length);

    for (1..random_rate_length) |i| {
        random_rate[i] = random.intRangeAtMost(u16, 0, random_rate_length);
    }

    random_rate[0] = 0;

    const random_temperature_length = std.math.maxInt(u8);
    var random_temperature = try allocator.alloc(u8, random_temperature_length);

    for (1..random_temperature_length) |i| {
        random_temperature[i] = random.intRangeAtMost(u8, 0, random_temperature_length);
    }

    random_temperature[0] = 0;

    const random_index_length = record_count;
    var random_index = try allocator.alloc(usize, random_index_length);

    for (1..random_index_length) |i| {
        random_index[i] = random.intRangeAtMost(usize, 0, random_index_length);
    }

    random_index[0] = 0;

    return Self{
        .allocator = allocator,
        .record_count = record_count,
        .records = records,

        .random_rate_length = random_rate_length,
        .random_rate = random_rate,

        .random_temperature_length = random_temperature_length,
        .random_temperature = random_temperature,

        .random_index_length = random_index_length,
        .random_index = random_index,
    };
}

pub fn put(self: Self, hash: u64, key: []u8, value: []u8) !void {
    const index = hash % self.record_count;
    const record = self.records[index];

    if (record.key_length == 0) {
        const data = try self.allocator.alloc(u8, key.len + value.len);

        @memcpy(data[0..key.len], key);
        @memcpy(data[key.len .. key.len + value.len], value);

        self.records[index] = Record{
            .temperature = 127,
            .key_length = @intCast(key.len),
            .value_length = @intCast(value.len),
            .total_length = @intCast(key.len + value.len),
            .hash = hash,
            .data = data.ptr,
        };
    } else if (self.get_random_temperature() > record.temperature) {
        self.allocator.free(record.data.?[0..record.total_length]);

        const data = try self.allocator.alloc(u8, key.len + value.len);

        @memcpy(data[0..key.len], key);
        @memcpy(data[key.len .. key.len + value.len], value);

        self.records[index] = Record{
            .temperature = 127,
            .key_length = @intCast(key.len),
            .value_length = @intCast(value.len),
            .total_length = @intCast(key.len + value.len),
            .hash = hash,
            .data = data.ptr,
        };
    }
}

pub fn get(self: Self, hash: u64, key: []u8) ?[]u8 {
    const index = hash % self.record_count;
    var record = self.records[index];

    if (key.len != record.key_length) {
        return null;
    }

    const record_key = record.data.?[0..record.key_length];

    if (std.mem.eql(u8, key, record_key) == false) {
        return null;
    }

    if (self.increase_rate()) {
        record.temperature = @addWithOverflow(record.temperature, 1)[0];

        const victim_index = self.get_random_index();
        var victim = self.records[victim_index];

        victim.temperature = @subWithOverflow(victim.temperature, 1)[0];
    }

    const record_value = record.data.?[record.key_length..record.total_length];

    return record_value;
}

pub fn delete(self: Self, hash: u64, key: []u8) ?void {
    const index = hash % self.record_count;
    const record = self.records[index];

    if (key.len != record.key_length) {
        return null;
    }

    const record_key = record.data.?[0..record.key_length];

    if (std.mem.eql(u8, key, record_key) == false) {
        return null;
    }

    self.allocator.free(record.data.?[0..record.total_length]);

    self.records[index] = Record{
        .temperature = 127,
        .key_length = 0,
        .value_length = 0,
        .total_length = 0,
        .hash = 0,
        .data = null,
    };
}

pub fn free(self: Self) void {
    for (self.records) |record| {
        if (record.data != null) {
            self.allocator.free(record.data.?[0..record.total_length]);
        }
    }

    self.allocator.free(self.records);
    self.allocator.free(self.random_rate);
    self.allocator.free(self.random_temperature);
    self.allocator.free(self.random_index);
}

test "HashMap" {
    const allocator = std.testing.allocator;
    const hash_map = try init(allocator, 4096);
    defer hash_map.free();

    const hash = xxhash(0, "Hello, World!");
    const key_slice: []u8 = @constCast("Hello, World!")[0..];
    const value_slice: []u8 = @constCast("How are you doing?")[0..];

    _ = try hash_map.put(hash, key_slice, value_slice);

    if (hash_map.get(hash, key_slice)) |v| {
        try expect(std.mem.eql(u8, v, value_slice));
    }

    _ = hash_map.delete(hash, key_slice);

    try expect(hash_map.get(hash, key_slice) == null);
}
