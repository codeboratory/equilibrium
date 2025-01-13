const Config = @import("Config.zig");
const Bitmap = @import("Bitmap.zig");

const Self = @This();

config: Config,
bitmaps: []Bitmap,

layer_min: usize,
layer_max: usize,
layer_count: usize,

pub fn init(config: Config) Self {
    var bitmaps: []Bitmap = undefined;

    const layer_min = 0;
    const layer_max = 0;
    const layer_count = 0;

    return Self{
        .config = config,
        .bitmaps = bitmaps,
        .layer_min = layer_min,
        .layer_max = layer_max,
        .layer_count = layer_count,
    };
}

fn get_bitmap(self: Self, chunk_count: usize) Bitmap {
    return self.bitmaps[0];
}

pub fn create(self: Self, chunk_count: usize) ?usize {
    const bitmap = self.get_bitmap(chunk_count);
    const bits_needed = 0;
    const bit_offset = bitmap.find(bits_needed) orelse return null;

    // TODO: loop from this layer all the way to the lowest level
    // and for each level call bitmap.set_bits(offset, length, false)
    // (each level offset/length has to be adjusted by multiplier)

    return bit_offset;
}

pub fn destroy(self: Self, chunk_offset: usize, chunk_count: usize) noreturn {
    // TODO: loop from this layer all the way to the lowest level
    // and for each level call bitmap.set_bits(offset, length, true)
    // (each level offset/length has to be adjusted by multiplier)
}
