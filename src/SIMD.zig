const std = @import("std");

pub const VECTOR_SIZE = std.simd.suggestVectorLength(u8) orelse @panic("SIMD not supported");
pub const VECTOR_BIT_SIZE = VECTOR_SIZE * 8;

pub fn from(slice: []u8) @Vector(VECTOR_SIZE, u8) {
    return @bitCast(slice[0..VECTOR_SIZE].*);
}

pub fn popcount(vector: @Vector(VECTOR_SIZE, u8)) @Vector(VECTOR_SIZE, u8) {
    return @popCount(vector);
}

pub fn add(vector: @Vector(VECTOR_SIZE, u8)) u8 {
    return @reduce(.Add, vector);
}
