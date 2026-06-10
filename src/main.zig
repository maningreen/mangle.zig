const std = @import("std");
const engine = @import("engine.zig");
const Runtime = @import("runtime.zig");
const raylib = @import("raylib");

comptime {
    std.testing.refAllDecls(@import("./engine.zig"));
    std.testing.refAllDecls(@import("./runtime.zig"));
    std.testing.refAllDecls(raylib);
}

pub fn main(init: std.process.Init) !void {
    raylib.initWindow(30, 30, "good news");
    defer raylib.closeWindow();
    const io = init.io;

    const stdout = std.Io.File.stdout();
    defer stdout.close(io);

    var outBuf: [64]u8 = undefined;
    var writer = stdout.writer(io, &outBuf);
    try writer.interface.print("Hello, World!\n", .{});
    try writer.flush();

    var runtime: Runtime = .{};
    try runtime.process();

    while (!raylib.windowShouldClose()) {}
}
