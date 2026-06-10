const std = @import("std");
const engine = @import("engine.zig");

comptime {
    std.testing.refAllDecls(@import("./engine.zig"));
    std.testing.refAllDecls(@import("./runtime.zig"));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const stdout = std.Io.File.stdout();
    defer stdout.close(io);

    var outBuf: [64]u8 = undefined;
    var writer = stdout.writer(io, &outBuf);
    try writer.interface.print("Hello, World!\n", .{});
    try writer.flush();
}
