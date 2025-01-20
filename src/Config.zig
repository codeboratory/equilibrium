// NOTE: maybe add a function since this config will
// most likely be also used for proxy
const Hash = struct {
    size: type,
};

const Size = union(enum) {
    max_size: usize,
    // NOTE: shouldn't it be called type?
    size: type,
};

const Temperature = struct {
    // NOTE: shouldn't it be called type?
    size: type,
    warming_rate: f64,
};

const Ttl = struct {
    // NOTE: shouldn't it be called type?
    size: type,
    // NOTE: is there any use case for ms or months/years?
    resolution: enum {
        s,
        m,
        h,
        d,
    },
};

// NOTE: maybe call it packed and auto
// to not confuse myself?
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
    ttl: ?Ttl,
};

record: Record,
allocator: ?Allocator,
