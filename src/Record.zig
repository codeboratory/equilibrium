const std = @import("std");
const builtin = @import("builtin");
const StructField = std.builtin.Type.StructField;
const Declaration = std.builtin.Type.Declaration;
const Config = @import("Config.zig");
const Random = @import("Random.zig");
const Utils = @import("Utils.zig");
const Constants = @import("Constants.zig");

fn create_hash_field(comptime config: Config) StructField {
    return .{
        .name = "hash",
        .type = config.record.hash.type,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf(config.record.hash.type),
    };
}

fn create_key_field(comptime config: Config) StructField {
    return switch (config.record.key) {
        .type => |k| .{
            .name = "key",
            .type = k,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(k),
        },
        .max_size => .{
            .name = "key",
            .type = void,
            .default_value = Constants.constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    };
}

fn create_key_length_field(comptime config: Config) StructField {
    return switch (config.record.key) {
        .type => .{
            .name = "key_length",
            .type = void,
            .default_value = Constants.constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| .{
            .name = "key_length",
            .type = Utils.create_uint(k),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(Utils.create_uint(k)),
        },
    };
}

fn create_value_field(comptime config: Config) StructField {
    return switch (config.record.value) {
        .type => |v| .{
            .name = "value",
            .type = v,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(v),
        },
        .max_size => .{
            .name = "value",
            .type = void,
            .default_value = Constants.constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
    };
}

fn create_value_length_field(comptime config: Config) StructField {
    return switch (config.record.value) {
        .type => .{
            .name = "value_length",
            .type = void,
            .default_value = Constants.constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |v| .{
            .name = "value_length",
            .type = Utils.create_uint(v),
            .default_value = null,
            .is_comptime = false,
            .alignment = if (config.record.layout == .small) 0 else @alignOf(Utils.create_uint(v)),
        },
    };
}

fn create_total_length_field(comptime config: Config) StructField {
    return switch (config.record.key) {
        .type => .{
            .name = "total_length",
            .type = void,
            .default_value = Constants.constant_void,
            .is_comptime = false,
            .alignment = 0,
        },
        .max_size => |k| switch (config.record.value) {
            .type => .{
                .name = "total_length",
                .type = void,
                .default_value = Constants.constant_void,
                .is_comptime = false,
                .alignment = 0,
            },
            .max_size => |v| .{
                .name = "total_length",
                .type = Utils.create_uint(k + v),
                .default_value = null,
                .is_comptime = false,
                .alignment = if (config.record.layout == .small) 0 else @alignOf(Utils.create_uint(k + v)),
            },
        },
    };
}

fn create_temperature_field(comptime config: Config) StructField {
    return .{
        .name = "temperature",
        .type = config.record.temperature.type,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf(config.record.temperature.type),
    };
}

fn create_data_field(comptime config: Config) StructField {
    return if (config.allocator != null and (config.record.key == .max_size or config.record.value == .max_size)) .{
        .name = "data",
        .type = [*]u8,
        .default_value = null,
        .is_comptime = false,
        .alignment = if (config.record.layout == .small) 0 else @alignOf([*]u8),
    } else .{
        .name = "data",
        .type = void,
        .default_value = Constants.constant_void,
        .is_comptime = false,
        .alignment = 0,
    };
}

fn create_ttl_field(comptime config: Config) StructField {
    return if (config.record.ttl) |ttl| .{
        .name = "ttl",
        .type = Utils.create_uint(ttl.max_size),
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    } else .{
        .name = "ttl",
        .type = void,
        .default_value = Constants.constant_void,
        .is_comptime = false,
        .alignment = 0,
    };
}

fn create_padding_field(comptime struct_size_aligned: usize, comptime struct_size_raw: usize) StructField {
    const padding_size = struct_size_aligned - struct_size_raw;

    return .{
        .name = "padding",
        .type = Utils.create_uint(padding_size),
        .default_value = @as(?*const anyopaque, @ptrCast(&@as(Utils.create_uint(padding_size), 0))),
        .is_comptime = false,
        .alignment = 0,
    };
}

fn get_struct_size_raw(comptime fields: anytype) usize {
    var struct_size_raw = 0;

    for (fields) |field| {
        struct_size_raw += @bitSizeOf(field.type);
    }

    return struct_size_raw;
}

// NOTE: optimized for larger than u64 structs
// TODO: handle sub-u64 struct sizes
fn get_struct_size_aligned(comptime struct_size_raw: usize) usize {
    return @as(usize, @intFromFloat(std.math.ceil(@as(f64, @floatFromInt(struct_size_raw)) / 16.0) * 16.0));
}

fn create_fast_struct(comptime fields: anytype) type {
    const sorted_fields = comptime blk: {
        var mutable_fields = fields;

        std.mem.sort(StructField, &mutable_fields, fields, cmp_struct_field_alignment);

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
}

fn create_small_struct(comptime fields: anytype) type {
    const struct_size_raw = get_struct_size_raw(fields);
    const struct_size_aligned = get_struct_size_aligned(struct_size_raw);

    const padded_fields = fields ++ [_]StructField{
        create_padding_field(struct_size_aligned, struct_size_raw),
    };

    return @Type(.{
        .Struct = .{
            .layout = .@"packed",
            .backing_integer = Utils.create_uint(struct_size_aligned),
            .fields = &padded_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn cmp_struct_field_alignment(comptime _: anytype, a: StructField, b: StructField) bool {
    return @alignOf(a.type) > @alignOf(b.type);
}

pub fn create(comptime config: Config) type {
    if (config.allocator == null and (config.key == .max_size or config.value == .max_size)) {
        @compileError("You have to provide allocator config");
    }

    const fields = [_]StructField{
        create_hash_field(config),
        create_key_field(config),
        create_key_length_field(config),
        create_value_field(config),
        create_value_length_field(config),
        create_total_length_field(config),
        create_temperature_field(config),
        create_data_field(config),
        create_ttl_field(config),
    };

    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;

    return struct {
        pub const Type = switch (config.record.layout) {
            .fast => create_fast_struct(fields),
            .small => create_small_struct(fields),
        };

        pub inline fn increase_temperature(record: *Type) void {
            record.temperature = Utils.saturating_add(config.record.temperature.type, record.temperature, 1);
        }

        pub inline fn decrease_temperature(record: *Type) void {
            record.temperature = Utils.saturating_sub(config.record.temperature.type, record.temperature, 1);
        }

        pub inline fn get_key(record: Type) []u8 {
            return switch (config.record.key) {
                .type => std.mem.asBytes(@constCast(&record.key))[0..],
                .max_size => record.data[0..record.key_length],
            };
        }

        pub inline fn get_value(record: Type) []u8 {
            return switch (config.record.value) {
                .type => std.mem.asBytes(@constCast(&record.value))[0..],
                .max_size => switch (config.record.key) {
                    .type => record.data[0..record.value_length],
                    .max_size => record.data[record.key_length .. record.key_length + record.value_length],
                },
            };
        }

        pub inline fn get_total_length(record: Type) usize {
            return switch (config.record.key) {
                .type => switch (config.record.value) {
                    .type => unreachable,
                    .max_size => record.value_length,
                },
                .max_size => switch (config.record.value) {
                    .type => record.key_length,
                    .max_size => record.total_length,
                },
            };
        }

        pub inline fn can_data_be_freed(record: Type) bool {
            return switch (config.record.key) {
                .type => switch (config.record.value) {
                    .type => false,
                    .max_size => record.value_length != 0,
                },
                .max_size => switch (config.record.value) {
                    .type => record.key_length != 0,
                    .max_size => record.total_length != 0,
                },
            };
        }

        pub inline fn should_warm_up(random_warming_rate: f64) bool {
            return random_warming_rate < config.record.temperature.warming_rate;
        }

        pub inline fn should_overwrite(random_temperature: config.record.temperature.type, record: Type) bool {
            return record.temperature < random_temperature;
        }

        pub inline fn free(allocator: std.mem.Allocator, record: Type) void {
            if (can_data_be_freed(record)) {
                allocator.free(record.data[0..get_total_length(record)]);
            }
        }

        pub inline fn create(allocator: std.mem.Allocator, hash: config.record.hash.type, key: []u8, value: []u8, ttl: ttl_type) !Type {
            return Type{
                .hash = hash,
                .key = switch (config.record.key) {
                    .type => std.mem.bytesToValue(config.record.key.type, key),
                    .max_size => {},
                },
                .key_length = switch (config.record.key) {
                    .type => {},
                    .max_size => @intCast(key.len),
                },
                .value = switch (config.record.value) {
                    .type => std.mem.bytesToValue(config.record.value.type, value),
                    .max_size => {},
                },
                .value_length = switch (config.record.value) {
                    .type => {},
                    .max_size => @intCast(value.len),
                },
                .total_length = switch (config.record.key) {
                    .type => {},
                    .max_size => |k| switch (config.record.value) {
                        .type => {},
                        .max_size => |v| @as(Utils.create_uint(k + v), @intCast(key.len + value.len)),
                    },
                },
                .temperature = std.math.maxInt(config.record.temperature.type) / 2,
                .data = block: {
                    if (config.record.key == .type and config.record.value == .type) {
                        break :block undefined;
                    }

                    const key_length = switch (config.record.key) {
                        .type => 0,
                        .max_size => key.len,
                    };

                    const value_length = switch (config.record.value) {
                        .type => 0,
                        .max_size => value.len,
                    };

                    // TODO: use bitmap allocator instead
                    const data = try allocator.alloc(u8, key_length + value_length);

                    if (config.record.key == .max_size and config.record.value == .type) {
                        @memcpy(data, key);
                    }

                    if (config.record.key == .type and config.record.value == .max_size) {
                        @memcpy(data, value);
                    }

                    if (config.record.key == .max_size and config.record.value == .max_size) {
                        @memcpy(data[0..key.len], key);
                        @memcpy(data[key.len .. key.len + value.len], value);
                    }

                    break :block data.ptr;
                },
                .ttl = if (config.record.ttl) |_| ttl else undefined,
                // .ttl = if (config.record.ttl) |_|
                //     try self.encode_ttl(self.get_now_with_ttl(ttl))
                // else
                //     undefined,
            };
        }
    };
}
