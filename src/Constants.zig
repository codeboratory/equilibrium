const std = @import("std");

pub const VECTOR_SIZE = std.simd.suggestVectorLength(u8) orelse @panic("SIMD not supported");
pub const VECTOR_BIT_SIZE = VECTOR_SIZE * 8;
