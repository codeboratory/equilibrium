const std = @import("std");
const builtin = @import("builtin");
const StructField = std.builtin.Type.StructField;
const Config = @import("Config.zig");
const Utils = @import("Utils.zig");

const FIELD_COUNT = 10;

const void_value = {};
const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));

pub fn create(config: Config) type {
    if (config.allocator == null and (config.key == .max_size or config.value == .max_size)) {
        @compileError("You have to provide allocator config");
    }

    const fields = [FIELD_COUNT - 1]StructField{ .{
        .name = "hash",
        .type = config.record.hash.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf(config.record.hash.size),
    }, switch (config.record.key) {
        .size => |k| .{
            .name = "key",
            .type = k,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(k),
        },
        .max_size => .{
            .name = "key",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    }, switch (config.record.key) {
        .size => .{
            .name = "key_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| .{
            .name = "key_length",
            .type = std.meta.Int(.unsigned, Utils.bits_needed(k)),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, Utils.bits_needed(k))),
        },
    }, switch (config.record.value) {
        .size => |v| .{
            .name = "value",
            .type = v,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(v),
        },
        .max_size => .{
            .name = "value",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    }, switch (config.record.value) {
        .size => .{
            .name = "value_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |v| .{
            .name = "value_length",
            .type = std.meta.Int(.unsigned, Utils.bits_needed(v)),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, Utils.bits_needed(v))),
        },
    }, switch (config.record.key) {
        .size => .{
            .name = "total_length",
            .type = void,
            .default_value = constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| switch (config.record.value) {
            .size => .{
                .name = "total_length",
                .type = void,
                .default_value = constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .max_size => |v| .{
                .name = "total_length",
                .type = std.meta.Int(.unsigned, Utils.bits_needed(k + v)),
                .default_value = null,
                .is_comptime = false,
                .alignment = if (config.record.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, Utils.bits_needed(k + v))),
            },
        },
    }, .{
        .name = "temperature",
        .type = config.record.temperature.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf(config.record.temperature.size),
    }, if (config.record.ttl) |t| .{
        .name = "ttl",
        .type = t.size,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf(t.size),
    } else .{
        .name = "ttl",
        .type = void,
        .default_value = constant_void,
        .is_comptime = false,
        .alignment = 0,
    }, if (config.allocator != null and (config.record.key == .max_size or config.record.value == .max_size)) .{
        .name = "data",
        .type = [*]u8,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf([*]u8),
    } else .{
        .name = "data",
        .type = void,
        .default_value = constant_void,
        .is_comptime = false,
        .alignment = 0,
    } };

    if (config.record.layout == .fast) {
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
                .alignment = if (config.record.layout == .small) 0 else @alignOf(std.meta.Int(.unsigned, padding_size)),
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

fn cmp_struct_field_size(comptime _: [FIELD_COUNT - 1]StructField, a: StructField, b: StructField) bool {
    return @bitSizeOf(a.type) > @bitSizeOf(b.type);
}
