const std = @import("std");
const net = std.net;
const protocol_create = @import("Protocol.zig").create;
const Testing = @import("Testing.zig");

const Protocol = protocol_create(Testing.config_default);

const Self = @This();

server: net.Server,

pub fn init() !Self {
    const localhost = try net.Address.parseIp("127.0.0.1", 3000);

    var server = try localhost.listen(.{});

    std.debug.print("[DEBUG] - Server listening on port {}\n", .{server.listen_address.getPort()});
    return Self{ .server = server };
}

pub fn deinit(self: *Self) void {
    self.server.deinit();
}

pub fn accept(self: *Self) !void {
    const conn = try self.server.accept();
    defer conn.stream.close();

    var buf: [1024]u8 = undefined;
    @memset(&buf, 0);
    const msg_size = try conn.stream.read(buf[0..]);

    std.debug.print("[DEBUG] - Message recived {any}\n", .{buf[0..msg_size]});

    const message = Protocol.init(buf[0..]) catch return;

    std.debug.print("[DEBUG] - Message {any}\n", .{message});

    _ = try conn.stream.writeAll("Your message: " ++ buf);
}
