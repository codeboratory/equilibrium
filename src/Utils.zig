const std = @import("std");

pub fn bits_needed(number: u64) u16 {
    if (number == 0) return 1;
    return @bitSizeOf(@TypeOf(number)) - @clz(number);
}

pub inline fn saturating_add(comptime T: type, a: T, b: T) T {
    const result = @addWithOverflow(a, b);

    if (result[1] == 1) {
        return std.math.maxInt(T);
    }

    return result[0];
}

pub inline fn saturating_sub(comptime T: type, a: T, b: T) T {
    const result = @subWithOverflow(a, b);

    if (result[1] == 1) {
        return std.math.minInt(T);
    }

    return result[0];
}

pub inline fn buffer_equals(a: []u8, b: []u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn create_uint(value: usize) type {
    return std.meta.Int(.unsigned, bits_needed(value));
}

pub inline fn get_index(comptime T: type, count: usize, hash: T) usize {
    const is_power_of_two = (count & (count - 1)) == 0;

    if (is_power_of_two) {
        return hash & (count - 1);
    } else {
        return hash % count;
    }
}
