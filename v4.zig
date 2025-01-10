const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Type = union(enum) {
    none,
    fixed: struct {
        type: type,
    },
    variable: struct {
        type: type,
        avg_size: u16,
    },
};

const Hash = fn (seed: u64, input: anytype) u64;

const Config = struct { table_size: u64, key_type: Type, value_type: Type, temp_type: Type, hash: Hash };

pub fn is_p2(value: u64) bool {
    return value != 0 and @popCount(value) == 1;
}

pub fn Cache(comptime config: Config) type {
    if (is_p2(config.table_size) == false) {
        @compileError("table_size has to be a power of two");
    }

    const record_type = struct {
        temp: switch (config.temp_type) {
            .fixed => |v| v.type,
            .variable => @compileError("temp_type cannot be variable"),
            .none => @compileError("temp_type cannot be none"),
        },
        key: switch (config.key_type) {
            .fixed => |v| v.type,
            .variable => u8,
            .none => @compileError("key_type cannot be none"),
        },
        value: switch (config.value_type) {
            .fixed => |v| v.type,
            .variable => u8,
            .none => @compileError("value_type cannot be none"),
        },
    };

    const key_type = switch (config.key_type) {
        .fixed => |v| v.type,
        .variable => |v| v.type,
        .none => @compileError("key_type cannot be none"),
    };

    const value_type = switch (config.value_type) {
        .fixed => |v| v.type,
        .variable => |v| v.type,
        .none => @compileError("value_type cannot be none"),
    };

    return struct {
        const Self = @This();

        hash_table: *[config.table_size]record_type,
        data_buffer: *[config.table_size * 16]u8,

        pub fn init() Self {
            var hash_table = [_]record_type{undefined} ** config.table_size;
            var data_buffer = [_]u8{undefined} ** (config.table_size * 16);

            return .{ .hash_table = hash_table[0..], .data_buffer = data_buffer[0..] };
        }

        pub fn put(self: Self, key: key_type, value: value_type) void {
            const hash = config.hash(0, key);
            const index = hash & (config.table_size - 1);
            const bytes = std.mem.asBytes(&key);
            const length = bytes.len;

            @memcpy(self.data_buffer[0..length], bytes);

            // TODO: get temp as half of the max of its type
            self.hash_table[index] = record_type{ .temp = 127, .key = &self.data_buffer[0..length], .value = value };

            print("{any}\n", .{self.data_buffer[0..length]});
        }
    };
}

test "TEST" {
    const config = Config{ .table_size = 128, .key_type = .{ .variable = .{ .type = *[]u8, .avg_size = 16 } }, .value_type = .{ .fixed = .{ .type = u8 } }, .temp_type = .{ .fixed = .{ .type = u8 } }, .hash = std.hash.XxHash64.hash };

    const cache = Cache(config).init();

    var string = "Yoyo";

    cache.put(string[0..], 1);
}
