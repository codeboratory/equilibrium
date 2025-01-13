const Config = @import("Config.zig");
const MemoryBlock = @import("MemoryBlock.zig");
const BitmapManager = @import("BitmapManager.zig");

const Self = @This();

config: Config,
manager: BitmapManager,
memory: MemoryBlock,

pub fn init(config: Config) Self {
    const memory = MemoryBlock.init(config);
    const manager = BitmapManager.init(config);

    return Self{
        .config = config,
        .manager = manager,
        .memory = memory,
    };
}

pub fn create(self: Self, chunk_count: usize) ?[]u8 {
    const chunk_offset = self.manager.create(chunk_count) orelse return null;
    const chunk_slice = self.memory.create(chunk_offset, chunk_count);

    return chunk_slice;
}

pub fn destroy(self: Self, slice: []u8) noreturn {
    const chunk_offset = 0;
    const chunk_count = slice.len / self.config.chunk_size;

    self.manager.destroy(chunk_offset, chunk_count);
    self.memory.destroy(chunk_offset, chunk_count);
}
