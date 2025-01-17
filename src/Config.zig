const Hash = struct {
    size: type,
};

const Size = union(enum) {
    max_size: usize,
    size: type,
};

const Temperature = struct {
    size: type,
    warming_rate: f64,
};

const Ttl = struct {
    size: type,
    resolution: enum {
        s,
        m,
        h,
        d,
    },
};

const Layout = enum {
    fast,
    small,
};

const Allocator = struct {
    chunk_size: usize,
};

const Record = struct {
    layout: Layout,
    hash: Hash,
    key: Size,
    value: Size,
    temperature: Temperature,
    ttl: ?Ttl,
};

const Table = struct {
    record_count: usize,
};

record: Record,
table: Table,
allocator: ?Allocator,
