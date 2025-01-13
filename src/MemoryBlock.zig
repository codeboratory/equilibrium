const Config = @import("Config.zig");

const Self = @This();

config: Config,
memory: []u8,

pub fn init(config: Config) Self {
    return Self{
        .config = config,
    };
}

pub fn create(self: Self, chunk_offset: usize, chunk_count: usize) []u8 {
    return self.memory[self.config.chunk_size * chunk_offset .. (self.config.chunk_size * chunk_offset) + (self.config.chunk_size & chunk_count)];
}

pub fn destroy(self: Self, chunk_offset: usize, chunk_count: usize) noreturn {
    @memset(self.create(chunk_offset, chunk_count), 0);
}
