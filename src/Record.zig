pub const Record = packed struct {
    temperature: u8,
    key_length: usize,
    value_length: usize,
    hash: u64,
    data: []u8,
};
