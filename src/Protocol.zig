const std = @import("std");
const Config = @import("Config.zig");
const Utils = @import("Utils.zig");
const expect = std.testing.expect;

pub fn create(config: Config) type {
    const hash_type = config.record.hash.type;
    const ttl_type = if (config.record.ttl) |ttl| Utils.create_uint(ttl.max_size) else void;

    return struct {
        const Self = @This();

        command: Command,
        // hash: hash_type,
        key: []u8,
        // value: []u8,
        // ttl: ttl_type,

        pub const Command = enum {
            Get,
            Put,
            Del,
        };

        pub inline fn get_command(buf: []u8, cursor: *usize) Command {
            const result = @as(Command, @enumFromInt(buf[0]));
            cursor.* += @as(usize, 1);

            return result;
        }

        pub inline fn get_hash(buf: *[@sizeOf(hash_type)]u8) hash_type {
            return std.mem.readInt(hash_type, buf[0..], .big);
        }

        pub inline fn get_key(buf: []u8, cursor: *usize) []u8 {
            return switch (config.record.key) {
                .type => |t| block: {
                    const result = buf[0..@sizeOf(t)];
                    cursor.* += @sizeOf(t);

                    break :block result;
                },
                .max_size => block: {
                    const length = std.mem.readInt(u16, buf[0..], .big);
                    const result = buf[2 .. 2 + length];
                    cursor.* += 2 + length;

                    break :block result;
                },
            };
        }

        pub inline fn get_value(buf: []u8) []u8 {
            return switch (config.record.value) {
                .type => |t| buf[0..@sizeOf(t)],
                .max_size => buf[2 .. 2 + std.mem.readInt(u16, buf[0..], .big)],
            };
        }

        pub inline fn get_ttl(buf: []u8) ttl_type {
            return if (config.record.ttl) |_| std.mem.readInt(ttl_type, buf, .big) else {};
        }

        pub fn init(buf: []u8) !Self {
            var cursor: usize = 0;

            const command = get_command(buf, &cursor);

            // const hash = get_hash(buf[0..@sizeOf(hash_type)]);
            // tmp = tmp[@sizeOf(hash_type)..];

            const key = get_key(buf, &cursor);

            // const value = get_value(tmp);
            // tmp = tmp[value.len..];

            // const ttl = get_ttl(tmp);

            return Self{
                .command = command,
                // .hash = hash,
                .key = key,
                // .value = value,
                // .ttl = ttl,
            };
        }
    };
}
