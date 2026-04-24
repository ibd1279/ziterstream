const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var buf: [4096]u8 = undefined;
    var bw = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &bw.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // don't forget to flush!
}

test "simple test" {
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
