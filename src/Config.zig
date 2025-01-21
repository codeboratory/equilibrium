const Hash = struct {
    type: type,
};

const Size = union(enum) {
    max_size: usize,
    type: type,
};

const Temperature = struct {
    type: type,
    warming_rate: f64,
};

const Layout = enum {
    fast,
    small,
};

// TODO: add more config
// - bitmap_count
// - bitmap_resolution
// - do bitmaps start from the chunk_size? if not then bitmap_start
// - some way to tune layer selection based on perf/fragmentation
const Allocator = struct {
    chunk_size: usize,
};

const Record = struct {
    count: usize,
    layout: Layout,
    hash: Hash,
    key: Size,
    value: Size,
    temperature: Temperature,
};

record: Record,
allocator: ?Allocator,
