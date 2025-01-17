pub const void_value = {};
pub const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));
