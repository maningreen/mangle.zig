const std = @import("std");
const engine = @import("engine.zig");
const Runtime = @import("runtime.zig");
const rl = @import("raylib");

comptime {
    std.testing.refAllDecls(@This());
}

const testSystem: engine.System = .{
    .Types = .{ .items = &.{ i32, u32 } },
    .process = (struct {
        fn process(_: anytype, _: engine.RegistryInformation) engine.ProcessError!void {}
    }).process,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const stdout = std.Io.File.stdout();
    defer stdout.close(io);

    var outBuf: [64]u8 = undefined;
    var writer = stdout.writer(io, &outBuf);
    try writer.interface.print("Hello, World!\n", .{});
    try writer.flush();

    const Arc = engine.Archetype(.{ .items = &.{ u32, u32 } });
    var arc = Arc{ .data = .empty };
    try arc.appendItem(init.gpa, .{ 3, 4 });
    defer arc.deinit(init.gpa);

    const Reg = engine.Registry(&.{i32}, &.{testSystem});
    _ = Reg;

    rl.initWindow(1920, 1080, "test");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.drawCircle(0, 0, 30, .ray_white);
        rl.endDrawing();
    }
}
