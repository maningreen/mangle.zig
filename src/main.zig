const std = @import("std");
const engine = @import("engine.zig");
const Runtime = @import("runtime.zig");
const rl = @import("raylib");

comptime {
    std.testing.refAllDecls(@This());
}

const Radius = f32;
const Pos = rl.Vector2;
const Colour = rl.Color;

const testSystem: engine.System = .{
    .requirements = .{ .items = &.{ Radius, Colour, Pos } },
    .process = (struct {
        fn process(val: anytype, _: engine.RegistryInformation) engine.ProcessError!void {
            const T = testSystem.requirements.GetType();
            const circle: T = @as(T, val);
            rl.drawCircleV(circle[2], circle[0], circle[1]);
        }
    }).process,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const stdout = std.Io.File.stdout();
    defer stdout.close(io);

    const T = struct {
        r: Radius,
        c: Colour,
        p: Pos,
    };
    const Reg = engine.Registry(&.{T}, &.{testSystem});

    var rt: Reg = .init(io, init.gpa);
    defer rt.deinit();
    try rt.addValue(T{.c = .white, .p = .one(), .r = 30});

    rl.initWindow(1920, 1080, "test");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.drawCircle(0, 0, 30, .ray_white);
        rl.endDrawing();
    }
}
