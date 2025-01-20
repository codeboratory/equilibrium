pub const void_value = {};
pub const constant_void = @as(?*const anyopaque, @ptrCast(&void_value));
pub const native_endian = @import("builtin").target.cpu.arch.endian();
