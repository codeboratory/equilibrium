const std = @import("std");
const net = std.net;
const Server = @import("Server.zig");

pub fn main() !void {
    var server = try Server.init();
    defer server.deinit();

    while (true) {
        _ = try server.accept();
    }
}

fn client(listen_address: net.Address) !void {
    const testeMessage = "This message is a test.";

    var clientCon = try net.tcpConnectToAddress(listen_address);
    defer clientCon.close();

    _ = try clientCon.writeAll(testeMessage);

    var buf: [1024]u8 = undefined;

    @memset(&buf, 0);

    _ = try clientCon.read(&buf);
}
