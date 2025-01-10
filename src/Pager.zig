const std = @import("std");
const posix = std.posix;
const mmap = posix.mmap;
const assert = std.debug.assert;
const mem = std.mem;
const page_size = std.mem.page_size;

pub fn alloc(size: usize) []u8 {
    const slice = mmap(
        null,
        mem.alignForward(usize, size, page_size),
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch @panic("Couldn't allocate");

    return slice;
}

pub fn free(slice: []u8) void {
    posix.munmap(@alignCast(slice.ptr[0..slice.len]));
}
