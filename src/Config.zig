const std = @import("std");
const Utils = @import("Utils.zig");

pub const Hash = struct {
    type: type,
};

pub const Size = union(enum) {
    max_size: usize,
    type: type,
};

pub const Temperature = struct {
    type: type,
    warming_rate: f64,
};

pub const Ttl = struct {
    // max_size: usize,
    resolution: enum {
        milisecond,
        second,
        minute,
        hour,
        day,
        month,
    },

    pub fn get_type(self: Ttl) type {
        return Utils.create_uint(std.math.maxInt(u64) / self.get_multiplier());
    }

    pub fn get_multiplier(self: Ttl) usize {
        return switch (self.resolution) {
            .milisecond => 1,
            .second => 1000,
            .minute => 60 * 1000,
            .hour => 60 * 60 * 1000,
            .day => 24 * 60 * 60 * 1000,
            .month => 30 * 24 * 60 * 60 * 1000,
        };
    }
};

pub const Layout = enum {
    fast,
    small,
};

// TODO: add more config
// - bitmap_count
// - bitmap_resolution
// - do bitmaps start from the chunk_size? if not then bitmap_start
// - some way to tune layer selection based on perf/fragmentation
pub const Allocator = struct {
    chunk_size: usize,
};

pub const Record = struct {
    count: usize,
    layout: Layout,
    hash: Hash,
    key: Size,
    value: Size,
    temperature: Temperature,
    ttl: ?Ttl,
};

record: Record,
allocator: ?Allocator,
