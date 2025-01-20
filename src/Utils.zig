pub fn bits_needed(number: u64) u16 {
    if (number == 0) return 1;
    return @bitSizeOf(@TypeOf(number)) - @clz(number);
}
