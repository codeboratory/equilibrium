const std = @import("std");
const builtin = @import("builtin");
const StructField = std.builtin.Type.StructField;

pub const Hash = struct {
    size: type,
};

pub const Size = union(enum) {
    max_size: usize,
    size: type,
};

pub const Temperature = struct {
    size: type,
    warming_rate: f64,
};

pub const Ttl = struct {
    size: type,
    resolution: enum {
        ms,
        s,
        m,
        h,
        d,
    },
};

pub const Layout = enum {
    fast,
    small,
};

pub const Allocator = struct {
    chunk_size: usize,
};

pub const Config = struct {
    layout: Layout,
    hash: Hash,
    key: Size,
    value: Size,
    temperature: Temperature,
    allocator: ?Allocator,
    ttl: ?Ttl,
};

const FIELD_COUNT = 10;

const void_value = {};
const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));

fn cmp_struct_field_size(comptime _: [FIELD_COUNT - 1]StructField, a: StructField, b: StructField) bool {
    return @bitSizeOf(a.type) > @bitSizeOf(b.type);
}

pub fn Record(config: Config) type {
    if (config.allocator == null and (config.key == .max_size or config.value == .max_size)) {
        @compileError("You have to provide allocator config");
    }

    const fields = [FIELD_COUNT - 1]StructField{ .{
        .name = "hash",
        .type = config.hash.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.layout == .small) 0 else @alignOf(config.hash.size),
    }, switch (config.key) {
        .size => |k| .{
            .name = "key",
            .type = k,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.layout == .small) 0 else @alignOf(k),
        },
        .max_size => .{
            .name = "key",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    }, switch (config.key) {
        .size => .{
            .name = "key_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| .{
            .name = "key_length",
            .type = std.meta.Int(.unsigned, bits_needed(k)),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, bits_needed(k))),
        },
    }, switch (config.value) {
        .size => |v| .{
            .name = "value",
            .type = v,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.layout == .small) 0 else @alignOf(v),
        },
        .max_size => .{
            .name = "value",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    }, switch (config.value) {
        .size => .{
            .name = "value_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |v| .{
            .name = "value_length",
            .type = std.meta.Int(.unsigned, bits_needed(v)),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, bits_needed(v))),
        },
    }, switch (config.key) {
        .size => .{
            .name = "total_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| switch (config.value) {
            .size => .{
                .name = "total_length",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .max_size => |v| .{
                .name = "total_length",
                .type = std.meta.Int(.unsigned, bits_needed(k + v)),
                .default_value = null,
                .is_comptime = false,
                .alignment = if (config.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, bits_needed(k + v))),
            },
        },
    }, .{
        .name = "temperature",
        .type = config.temperature.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.layout == .small) 0 else @alignOf(config.temperature.size),
    }, if (config.ttl) |t| .{
        .name = "ttl",
        .type = t.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.layout == .small) 0 else @alignOf(t.size),
    } else .{
        .name = "ttl",
        .type = void,
        .default_value = constant_void,
        .is_comptime = false,
        .alignment = 0,
    }, if (config.allocator != null and (config.key == .max_size or config.value == .max_size)) .{
        .name = "data",
        .type = [*]u8,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.layout == .small) 0 else @alignOf([*]u8),
    } else .{
        .name = "data",
        .type = void,
        .default_value = constant_void,
        .is_comptime = false,
        .alignment = 0,
    } };

    if (config.layout == .fast) {
        const sorted_fields = comptime blk: {
            var mutable_fields = fields;
            std.mem.sort(StructField, &mutable_fields, fields, cmp_struct_field_size);
            break :blk mutable_fields;
        };

        return @Type(.{
            .Struct = .{
                .layout = .auto,
                .fields = &sorted_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    } else {
        var struct_size_raw = 0;
        for (fields) |field| {
            struct_size_raw += @bitSizeOf(field.type);
        }

        const struct_size_aligned = @as(usize, @intFromFloat(std.math.ceil(@as(f64, @floatFromInt(struct_size_raw)) / 16.0) * 16.0));
        const padding_size = struct_size_aligned - struct_size_raw;

        const padded_fields = fields ++ [1]StructField{
            .{
                .name = "padding",
                .type = std.meta.Int(.unsigned, padding_size),
                .default_value = @as(?*const anyopaque, @ptrCast(&@as(std.meta.Int(.unsigned, padding_size), 0))),
                .is_comptime = false,
                .alignment = if (config.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, padding_size)),
            },
        };

        return @Type(.{
            .Struct = .{
                .layout = .@"packed",
                .backing_integer = std.meta.Int(.unsigned, struct_size_aligned),
                .fields = &padded_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }
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
    const allocator = std.testing.allocator;
    const data = try allocator.alloc(u8, 10);
    defer allocator.free(data);

    const config = Config{
        .layout = .small,
        .hash = .{
            .size = u64,
        },
        // .key = .{
        //     .size = u8,
        // },
        .key = .{
            .max_size = 256,
        },
        .value = .{
            .max_size = 64 * 1024 * 1024,
        },
        .temperature = .{
            .size = u8,
            .warming_rate = 0.05,
        },
        .ttl = .{
            .size = u26,
            .resolution = .s,
        },
        .allocator = .{
            .chunk_size = 32 * 1024,
        },
    };

    const CustomRecord = Record(config);

    const record = CustomRecord{
        .hash = 12356,
        // .key = 69,
        .key_length = 69,
        .value_length = 384 * 1024,
        .total_length = (384 * 1024) + 69,
        .temperature = 127,
        .ttl = 43433,
        .data = data.ptr,
    };

    std.debug.print("bit_size: {}\n", .{@bitSizeOf(CustomRecord)});
    std.debug.print("align: {}\n", .{@alignOf(CustomRecord)});
    std.debug.print("record: {any}\n", .{record});
}
