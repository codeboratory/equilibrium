pub fn bits_needed(number: u64) u16 {
    if (number == 0) return 1;

    var n = number;
    var bits: u16 = 0;
    while (n > 0) : (bits += 1) {
        n >>= 1;
    }

    return bits;
}
