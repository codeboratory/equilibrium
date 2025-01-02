const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const CACHE_MAXIMUM_SIZE = 512000000;
const CACHE_SIZE_EXPONENT = 3;
const CACHE_LEVEL_COUNT = 3;
const CACHE_LAST_LEVEL = CACHE_LEVEL_COUNT - 1;

const LEVEL_CHUNK_BITS = 8;
const LEVEL_CHUNK_COUNT = std.math.pow(u32, 2, LEVEL_CHUNK_BITS);

const RECORD_HASH_TYPE = u56;
const RECORD_VALUE_TYPE = u8;

const CHUNK_PAGE_SIZE = 4096;
const CHUNK_RECORDS_PER_PAGE = CHUNK_PAGE_SIZE / RECORD_SIZE;
const CHUNK_ROW_SIZE = LEVEL_CHUNK_COUNT * CHUNK_PAGE_SIZE;
const CHUNK_MAX_ROWS = CACHE_MAXIMUM_SIZE / CHUNK_ROW_SIZE;

const HASH_MASK = (@as(u64, 1) << LEVEL_CHUNK_BITS) - 1;

const CACHE_LEVEL_SIZES: [CACHE_LEVEL_COUNT]u32 = blk: {
    var sizes = [_]u32{undefined} ** CACHE_LEVEL_COUNT;
    var sum: f64 = 0;

    for (0..CACHE_LEVEL_COUNT) |i| {
        sum += std.math.pow(f64, i + 1, CACHE_SIZE_EXPONENT);
    }

    for (0..CACHE_LEVEL_COUNT) |i| {
        sizes[i] = @intFromFloat(std.math.pow(f64, i + 1, CACHE_SIZE_EXPONENT) / sum * CHUNK_MAX_ROWS);
    }

    break :blk sizes;
};

fn get_level_size(chunk_page_count: u32) u64 {
    return CHUNK_RECORDS_PER_PAGE * chunk_page_count;
}

const Positions = packed struct {
    chunk: u64,
    row: u64,
};

fn hash(value: []const u8) Positions {
    const hashed = std.hash.XxHash64.hash(0, value);

    return Positions{ .chunk = (hashed & HASH_MASK) % LEVEL_CHUNK_COUNT, .row = (hashed >> LEVEL_CHUNK_BITS) % get_level_size(CACHE_LEVEL_SIZES[CACHE_LAST_LEVEL]) };
}

const Size = packed struct {
    max: u64,
    current: u64,
    error_rate: f64,
};

const Record = packed struct {
    hash: u56,
    value: u8,
};

const RECORD_SIZE = @sizeOf(Record);

const Level = struct {
    chunk_data: []Record,
    chunk_size: [LEVEL_CHUNK_COUNT]Size,
    chunk_pages: u32,

    pub fn new(allocator: std.mem.Allocator, chunk_page_count: u32) !Level {
        var chunk_size = [_]Size{undefined} ** LEVEL_CHUNK_COUNT;
        const max = get_level_size(chunk_page_count);

        for (0..LEVEL_CHUNK_COUNT) |i| {
            chunk_size[i] = Size{ .max = max, .current = 0, .error_rate = 0 };
        }

        const chunk_data = try allocator.alloc(Record, max);

        return Level{ .chunk_data = chunk_data, .chunk_size = chunk_size, .chunk_pages = chunk_page_count };
    }
};

const Cache = struct {
    levels: [CACHE_LEVEL_COUNT]Level,
    allocator: Allocator,

    pub fn new(allocator: std.mem.Allocator) !Cache {
        var levels = [_]Level{undefined} ** CACHE_LEVEL_COUNT;

        for (CACHE_LEVEL_SIZES, 0..) |size, i| {
            levels[i] = try Level.new(allocator, size);
        }

        return Cache{ .levels = levels, .allocator = allocator };
    }

    pub fn free(self: Cache) void {
        for (self.levels) |level| {
            self.allocator.free(level.chunk_data);
        }
    }

    pub fn write(self: Cache, key: []const u8, value: RECORD_VALUE_TYPE) void {
        const positions = hash(key);

        self.levels[CACHE_LAST_LEVEL].chunk_data[positions.row] = Record{ .hash = @truncate(positions.row), .value = value };
    }

    pub fn read(self: Cache, key: []const u8) ?RECORD_VALUE_TYPE {
        const positions = hash(key);

        const record = self.levels[CACHE_LAST_LEVEL].chunk_data[positions.row];

        if (record.hash == @as(RECORD_HASH_TYPE, @truncate(positions.row))) {
            return record.value;
        }

        return null;
    }

    pub fn delete(self: Cache, key: []const u8) void {
        const positions = hash(key);

        self.levels[CACHE_LAST_LEVEL].chunk_data[positions.row] = std.mem.zeroes(Record);
    }
};

test "TEST" {
    const allocator = std.testing.allocator;
    const cache = try Cache.new(allocator);
    defer cache.free();

    const init_key = "Hello, World!";
    const init_value = 69;

    cache.write(init_key, init_value);

    print("{any}\n", .{init_value});
    print("{any}\n", .{cache.read(init_key)});

    cache.delete(init_key);

    print("{any}\n", .{cache.read(init_key)});
}
