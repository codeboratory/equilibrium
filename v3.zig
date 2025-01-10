const std = @import("std");
const print = std.debug.print;
const xxHash64 = std.hash.XxHash64.hash;

const HASH_BITS = 64;

const Config = struct {
    size_bits: u6,
    hash_seed: u64,
    temp_type: type,
    key_type: type,
    value_type: type,
};

pub fn multiple_of(size: u16, value: u16) u16 {
    return size * @as(u8, @intFromFloat(std.math.round(@as(f64, @floatFromInt(value)) / 64)));
}

pub fn createCache(comptime config: Config) type {
    const DATA_SIZE = std.mem.pow(2, config.size_bits);
    const TEMP_SIZE = @bitSizeOf(config.temp_type);
    const VALUE_SIZE = @bitSizeOf(config.value_type);
    const HASH_SIZE = HASH_BITS - config.size_bits;
    const STRUCT_SIZE = TEMP_SIZE + VALUE_SIZE + HASH_SIZE;
    const TARGET_SIZE = multiple_of(64, STRUCT_SIZE); 
    const PADDING_SIZE = TARGET_SIZE - STRUCT_SIZE;

    const Value = config.value_type;
    const Key = config.key_type;
    // const Temp = config.temp_type;

    const Record = packed struct {
        temp: config.temp_type,
        value: config.value_type,
        hash: @Type(.{ .Int = .{
            .signedness = .unsigned,
            .bits = HASH_SIZE
        } }),

        const padding = @Type(.{ .Int = .{
            .signedness = .unsigned,
            .bits = PADDING_SIZE,
        } });
    };

    const Cache = struct {
        data: [DATA_SIZE]Record,

        const Self = @This();

        pub fn write(
            self: Self,
            key: Key,
            value: Value
        ) void {
            const hash = xxHash64(config.hash_seed, key);
        }
    };

    return Cache{
        .data = []Record{undefined} ** DATA_SIZE
    };
}

test "TEST" {
    const cache = createCache(Config{
        .size_bits = 8,
        .hash_seed= 0,
        .key_type= []const u8,
        .value_type= u8
    });

    const key = "Hello, World!";
    const value = 69;

    print("{}\n", .{cache.read(key)});
    print("{}\n", .{cache.write(key, value)});
    print("{}\n", .{cache.read(key)});
    print("{}\n", .{cache.delete(key)});
    print("{}\n", .{cache.read(key)});
}
