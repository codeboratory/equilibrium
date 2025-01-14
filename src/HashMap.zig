const std = @import("std");
const builtin = @import("builtin");

pub const Dynamic = struct {
    min_size: usize,
    max_size: usize,
};

pub const Fixed = struct {
    bit_size: usize,
};

pub const Size = union(enum) {
    dynamic: Dynamic,
    fixed: Fixed,
};

pub const Config = struct {
    hash: Fixed,
    key: Size,
    value: Size,
    temperature: Fixed,
    ttl: ?Fixed,
};

pub fn get_struct_size(config: Config) usize {
    const hash_size = @as(usize, config.hash.bit_size);

    // std.debug.print("hash_size: {}\n", .{hash_size});

    const key_size = @as(usize, switch (config.key) {
        .fixed => |k| k.bit_size,
        .dynamic => 0,
    });

    // std.debug.print("key_size: {}\n", .{key_size});

    const key_length_size = @as(usize, switch (config.key) {
        .fixed => 0,
        .dynamic => |k| bits_needed(k.max_size),
    });

    // std.debug.print("key_length_size: {}\n", .{key_length_size});

    const value_size = @as(usize, switch (config.value) {
        .fixed => |v| v.bit_size,
        .dynamic => 0,
    });

    // std.debug.print("value_size: {}\n", .{value_size});

    const value_length_size = @as(usize, switch (config.value) {
        .fixed => 0,
        .dynamic => |v| bits_needed(v.max_size),
    });

    // std.debug.print("value_length_size: {}\n", .{value_length_size});

    const total_length_size = @as(usize, switch (config.key) {
        .fixed => 0,
        .dynamic => |k| switch (config.value) {
            .fixed => 0,
            .dynamic => |v| bits_needed(k.max_size + v.max_size),
        },
    });

    // std.debug.print("total_length_size: {}\n", .{total_length_size});

    const temperature_size = @as(usize, config.temperature.bit_size);

    // std.debug.print("temperature_size: {}\n", .{temperature_size});

    const ttl_size = @as(usize, if (config.ttl) |t| t.bit_size else 0);

    // std.debug.print("ttl_size: {}\n", .{ttl_size});

    const struct_size = @as(usize, hash_size + key_size + key_length_size + value_size + value_length_size + total_length_size + temperature_size + ttl_size);

    return struct_size;
}

pub fn Record(config: Config) type {
    const void_value = {};
    const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));
    const struct_size_raw = get_struct_size(config);
    const struct_size_aligned = @as(usize, @intFromFloat(std.math.ceil(@as(f64, @floatFromInt(struct_size_raw)) / 16.0) * 16.0));
    const padding_size = struct_size_aligned - struct_size_raw;

    const fields = &[_]std.builtin.Type.StructField{
        .{
            .name = "hash",
            .type = std.meta.Int(.unsigned, config.hash.bit_size),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        },
        if (config.ttl) |t| .{
            .name = "ttl",
            .type = std.meta.Int(.unsigned, t.bit_size),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        } else .{
            .name = "ttl",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        switch (config.key) {
            .fixed => .{
                .name = "total_length",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .dynamic => |k| switch (config.value) {
                .fixed => .{
                    .name = "total_length",
                    .type = void,
                    .default_value = constant_void,
                    .is_comptime = false,
                    .alignment = 0,
                },
                .dynamic => |v| .{
                    .name = "total_length",
                    .type = std.meta.Int(.unsigned, bits_needed(k.max_size + v.max_size)),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                },
            },
        },
        switch (config.key) {
            .fixed => .{
                .name = "key_length",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .dynamic => |k| .{
                .name = "key_length",
                .type = std.meta.Int(.unsigned, bits_needed(k.max_size)),
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
        },
        switch (config.value) {
            .fixed => .{
                .name = "value_length",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .dynamic => |v| .{
                .name = "value_length",
                .type = std.meta.Int(.unsigned, bits_needed(v.max_size)),
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
        },
        switch (config.value) {
            .fixed => |v| .{
                .name = "value",
                .type = std.meta.Int(.unsigned, v.bit_size),
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
            .dynamic => .{
                .name = "value",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
        },
        switch (config.key) {
            .fixed => |k| .{
                .name = "key",
                .type = std.meta.Int(.unsigned, k.bit_size),
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
            .dynamic => .{
                .name = "key",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
        },
        .{
            .name = "temperature",
            .type = std.meta.Int(.unsigned, config.temperature.bit_size),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        },
        .{
            .name = "padding",
            .type = std.meta.Int(.unsigned, padding_size),
            .default_value = @as(?*const anyopaque, @ptrCast(&@as(std.meta.Int(.unsigned, padding_size), 0))),
            .is_comptime = false,
            .alignment = 0,
        },
    };

    return @Type(.{
        .Struct = .{
            .layout = .@"packed",
            .backing_integer = std.meta.Int(.unsigned, struct_size_aligned),
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn bits_needed(number: u64) u16 {
    if (number == 0) return 1;

    var n = number;
    var bits: u16 = 0;
    while (n > 0) : (bits += 1) {
        n >>= 1;
    }

    return bits;
}

test "Record" {
    const config = Config{
        .hash = .{
            .bit_size = 64,
        },
        .key = .{ .fixed = .{
            .bit_size = 8,
        } },
        .value = .{ .dynamic = .{
            .min_size = 128 * 1024,
            .max_size = 1024 * 1024,
        } },
        .temperature = .{
            .bit_size = 8,
        },
        .ttl = .{
            .bit_size = 28,
        },
    };

    const CustomRecord = Record(config);

    const record = CustomRecord{
        .hash = 12356,
        .key = 69,
        .value_length = 384 * 1024,
        .temperature = 127,
        .ttl = 4343312,
    };

    std.debug.print("bit_size: {}\n", .{@bitSizeOf(CustomRecord)});
    std.debug.print("align: {}\n", .{@alignOf(CustomRecord)});
    std.debug.print("record: {any}\n", .{record});
}
