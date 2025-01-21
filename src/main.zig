const std = @import("std");

pub fn main() !void {
    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker, .{i});
    }

    for (threads) |thread| {
        thread.join();
    }
}

fn worker(id: usize) void {
    std.debug.print("Thread {d} is running\n", .{id});
}
