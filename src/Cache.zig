const Config = @import("Cache.zig");
const HashMap = @import("HashMap.zig");
const Self = @This();

config: Config,
hash_map: HashMap,

pub fn init(config: Config) Self {
    const hash_map = HashMap.init(config);

    return Self{
        .config = config,
        .hash_map = hash_map,
    };
}

pub fn write(key: []u8, value: []u8) noreturn {

}

pub fn read(key: []u8) noreturn {

}

pub fn delete(key: []u8) noreturn {

}
