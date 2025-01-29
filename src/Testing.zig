const Config = @import("Config.zig");

pub const config_default = Config{
    .record = .{
        .count = 1024,
        .layout = .fast,
        .hash = .{
            .type = u64,
        },
        .key = .{
            .type = u64,
            // .max_size = 1024,
        },
        .value = .{
            .type = u32,
            // .max_size = 64 * 1024 * 1024, // 64 Mb
        },
        .temperature = .{
            .type = u8,
            .warming_rate = 0.05,
        },
        .ttl = null,
        // .ttl = .{
        //     .max_size = 4294967296, // 136 years
        //     .max_value = 31556952, // 12 months
        //     .resolution = .second,
        // },
    },
    .allocator = .{
        .chunk_size = 32 * 1024, // 32 Kb
    },
};
