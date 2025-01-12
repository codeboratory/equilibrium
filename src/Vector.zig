const BitmapAllocator = @import("BitmapAllocator.zig");

const VECTOR_SIZE = BitmapAllocator.VECTOR_SIZE;

pub fn from(slice: []u8) @Vector(VECTOR_SIZE, u8) {
    return @bitCast(slice[0..VECTOR_SIZE].*);
}

pub fn popcount(vector: @Vector(VECTOR_SIZE, u8)) @Vector(VECTOR_SIZE, u8) {
    return @popCount(vector);
}

pub fn add(vector: @Vector(VECTOR_SIZE, u8)) u8 {
    return @reduce(.Add, vector);
}
