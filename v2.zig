const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const CACHE_WIDTH_BITS = 8;
const CACHE_WIDTH_SIZE = std.math.pow(u64, 2, CACHE_WIDTH_BITS);
const CACHE_HEIGHT_BITS = 8;
const CACHE_HEIGHT_SIZE = std.math.pow(u64, 2, CACHE_HEIGHT_BITS);
const CACHE_DEPTH_BITS = 2;
const CACHE_DEPTH_SIZE = std.math.pow(u64, 2, CACHE_DEPTH_BITS);

const HASH_SEED = 0;
const PAGE_SIZE = 4096;

const CACHE_CHUNK_SIZE = CACHE_DEPTH_SIZE * PAGE_SIZE;

const Key = []const u8;

pub fn closest_64(size: u16) u16 {
    return 64 * @as(u8, @intFromFloat(std.math.round(@as(f64, @floatFromInt(size)) / 64)));
}

pub fn createRecord(comptime Temp: type, comptime Value: type) type {
    const temp_size = @bitSizeOf(Temp);
    const value_size = @bitSizeOf(Value);
    const hash_size = 64 - (CACHE_WIDTH_BITS + CACHE_HEIGHT_BITS + CACHE_DEPTH_BITS);
    const packed_size = temp_size + value_size + hash_size;
    const target_size = closest_64(@as(u64, packed_size));

    return packed struct {
        temp: Temp,
        value: Value,
        hash: @Type(.{ .Int = .{ .signedness = .unsigned, .bits = hash_size } }),

        const _pad = @Type(.{ .Int = .{
            .signedness = .unsigned,
            .bits = target_size - packed_size,
        } });
    };
}

const Record = createRecord(u8, u8);

const RECORD_SIZE = @sizeOf(Record);
const RECORDS_PER_PAGE = PAGE_SIZE / RECORD_SIZE;
const DATA_SIZE: u64 = CACHE_WIDTH_SIZE * CACHE_HEIGHT_SIZE * CACHE_DEPTH_SIZE * RECORDS_PER_PAGE;

const Coordinates = struct {
    x: u64,
    y: u64,
    z: u64,

    const Self = @This();

    pub fn from_hash(hash: u64) Self {
        return Self{ .x = (hash >> (64 - CACHE_WIDTH_BITS)) & ((1 << CACHE_WIDTH_BITS) - 1) % CACHE_WIDTH_SIZE, .y = (hash >> (64 - CACHE_WIDTH_BITS - CACHE_HEIGHT_BITS)) & ((1 << CACHE_HEIGHT_BITS) - 1) % CACHE_HEIGHT_SIZE, .z = (hash >> (64 - CACHE_WIDTH_BITS - CACHE_HEIGHT_BITS - CACHE_DEPTH_BITS)) & ((1 << CACHE_DEPTH_BITS) - 1) % CACHE_DEPTH_BITS };
    }
};

pub fn get_index(coordinates: Coordinates) u64 {
    return (coordinates.y * CACHE_WIDTH_SIZE + coordinates.x) * (CACHE_DEPTH_SIZE * RECORDS_PER_PAGE) + (coordinates.z * RECORDS_PER_PAGE);
}

const Cache = struct {
    records: []Record,
    allocator: Allocator,

    const Self = @This();

    pub fn new(allocator: Allocator) !Self {
        const records = try allocator.alloc(Record, DATA_SIZE);

        return Self{ .records = records, .allocator = allocator };
    }

    pub fn free(self: Self) void {
        self.allocator.free(self.records);
    }

    pub fn write(self: Self, key: Key, value: u8) void {
        const hashed_key = std.hash.XxHash64.hash(HASH_SEED, key);
        const coordinates = Coordinates.from_hash(hashed_key);
        const remaining_hash = @as(u46, @truncate(hashed_key & ((1 << (64 - CACHE_WIDTH_BITS - CACHE_HEIGHT_BITS - CACHE_DEPTH_BITS)) - 1)));
        const record_index = get_index(coordinates);

        self.records[record_index] = Record{ .hash = remaining_hash, .temp = 128, .value = value };
    }

    pub fn read(self: Self, key: Key) ?Record {
        const hashed_key = std.hash.XxHash64.hash(HASH_SEED, key);
        const coordinates = Coordinates.from_hash(hashed_key);
        const remaining_hash = @as(u46, @truncate(hashed_key & ((1 << (64 - CACHE_WIDTH_BITS - CACHE_HEIGHT_BITS - CACHE_DEPTH_BITS)) - 1)));
        const record_index = get_index(coordinates);
        const record = self.records[record_index];

        if (record.hash == remaining_hash) {
            return record;
        }

        return null;
    }
};

test "TEST" {
    // const allocator = std.testing.allocator;
    // const cache = try Cache.new(allocator);
    // defer cache.free();

    const c1 = Coordinates{ .x = 1, .y = 0, .z = 0 };
    const c2 = Coordinates{ .x = 255, .y = 255, .z = 4 };

    print("c1 {}\n", .{get_index(c1)});
    print("c2 {}\n", .{get_index(c2)});
    print("DATA_SIZE {}\n", .{DATA_SIZE});
    print("PAGE_SIZE {}\n", .{PAGE_SIZE});
    print("RECORD_SIZE {}\n", .{RECORD_SIZE});
    print("RECORDS_PER_PAGE {}\n", .{RECORDS_PER_PAGE});

    // cache.write("Hello World", 69);
    // print("{any}\n", .{cache.read("Hello World")});
}
