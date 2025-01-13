const std = @import("std");
const Allocator = std.mem.Allocator;
const hash = std.hash.XxHash3.hash;
const random = std.crypto.random;
const expect = std.testing.expect;

pub const Record = packed struct {
    const padding = u14;

    data: [*]u8,
    hash: u64,
    key_length: u16,
    value_length: u16,
    temperature: u8,

    pub fn total_size(self: Record) usize {
        return @as(usize, @intCast(self.key_length)) + @as(usize, @intCast(self.value_length));
    }
};

const Self = @This();

allocator: Allocator,
record_count: usize,
records: []Record,

fn increase_rate() bool {
    return random.intRangeAtMost(u16, 0, 65535) < 4096;
}

fn u16_to_usize(value: u16) usize {
    return @intCast(value);
}

pub fn init(allocator: Allocator, record_count: usize) !Self {
    const records = try allocator.alloc(Record, record_count);

    return Self{
        .allocator = allocator,
        .record_count = record_count,
        .records = records,
    };
}

pub fn put(self: Self, key: []u8, value: []u8) !void {
    const key_hash = hash(0, key);
    const index = key_hash % self.record_count;
    const record = self.records[index];

    if (record.key_length == 0) {
        const data = try self.allocator.alloc(u8, key.len + value.len);

        @memcpy(data[0..key.len], key);
        @memcpy(data[key.len .. key.len + value.len], value);

        self.records[index] = Record{
            .temperature = 127,
            .key_length = @intCast(key.len),
            .value_length = @intCast(value.len),
            .hash = key_hash,
            .data = data.ptr,
        };
    }

    if (random.intRangeAtMost(u8, 0, 255) > record.temperature) {
        self.allocator.free(record.data[0..record.total_size()]);

        const data = try self.allocator.alloc(u8, key.len + value.len);

        @memcpy(data[0..key.len], key);
        @memcpy(data[key.len .. key.len + value.len], value);

        self.records[index] = Record{
            .temperature = 127,
            .key_length = @intCast(key.len),
            .value_length = @intCast(value.len),
            .hash = key_hash,
            .data = data.ptr,
        };
    }
}

pub fn get(self: Self, key: []u8) ?[]u8 {
    const key_hash = hash(0, key);
    const index = key_hash % self.record_count;
    var record = self.records[index];

    if (key.len != record.key_length) {
        return null;
    }

    const record_key = record.data[0..record.key_length];

    if (std.mem.eql(u8, key, record_key) == false) {
        return null;
    }

    if (increase_rate()) {
        record.temperature = @addWithOverflow(record.temperature, 1)[0];

        const victim_index = random.intRangeAtMost(usize, 0, self.record_count);
        var victim = self.records[victim_index];

        victim.temperature = @subWithOverflow(victim.temperature, 1)[0];
    }

    const record_value = record.data[record.key_length..record.total_size()];

    return record_value;
}

pub fn delete(self: Self, key: []u8) ?void {
    const key_hash = hash(0, key);
    const index = key_hash % self.record_count;
    const record = self.records[index];

    if (key.len != record.key_length) {
        return null;
    }

    const record_key = record.data[0..record.key_length];

    if (std.mem.eql(u8, key, record_key) == false) {
        return null;
    }

    self.allocator.free(record.data[0..record.total_size()]);

    self.records[index] = Record{
        .temperature = 127,
        .key_length = 0,
        .value_length = 0,
        .hash = 0,
        .data = undefined,
    };
}

pub fn free(self: Self) void {
    for (self.records) |record| {
        if (record.key_length == 0) {
            self.allocator.free(record.data[0..record.total_size()]);
        }
    }

    self.allocator.free(self.records);
}

test "HashMap" {
    const allocator = std.testing.allocator;
    const hash_map = try init(allocator, 4096);
    defer hash_map.free();

    const key_slice: []u8 = @constCast("Hello, World!")[0..];
    const value_slice: []u8 = @constCast("How are you doing?")[0..];

    _ = try hash_map.put(key_slice, value_slice);

    if (hash_map.get(key_slice)) |v| {
        try expect(std.mem.eql(u8, v, value_slice));
    }

    _ = hash_map.delete(key_slice);

    try expect(hash_map.get(key_slice) == null);
}
