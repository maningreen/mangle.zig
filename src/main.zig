const std = @import("std");
const engine = @import("engine.zig");
const rl = @import("raylib");

comptime {
    std.testing.refAllDecls(@This());
}

const Radius = f32;
const Pos = rl.Vector2;
const Gravity = void;
const Colour = rl.Color;

const testSystem: engine.System = .{
    .requirements = .{ .items = &.{ Radius, Colour, Pos } },
    .process = (struct {
        fn process(val: *anyopaque, _: engine.RegistryInformation) engine.ProcessError!void {
            const T = testSystem.requirements.GetType();
            const circlePtr: *T = @alignCast(@ptrCast(val));
            const circle = circlePtr.*;
            rl.drawCircleV(circle.@"2", circle.@"0", circle.@"1");
        }
    }).process,
};

const gravSystem: engine.System = .{
    .requirements = .{ .items = &.{ Pos, Gravity } },
    .process = (struct {
        fn process(val: *anyopaque, _: engine.RegistryInformation) engine.ProcessError!void {
            const T = testSystem.requirements.GetType();
            const objPtr: *T = @alignCast(@ptrCast(val));
            objPtr[0] -= 10;
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
        g: Gravity,
    };
    const Reg = engine.Registry(&.{T}, &.{testSystem, gravSystem});

    var rt: Reg = .init(io, init.gpa);
    defer rt.deinit();

    rl.initWindow(1920, 1080, "test");
    defer rl.closeWindow();

    rl.beginDrawing();
    try rt.addValue(T{.c = .blue, .p = rl.Vector2.one().scale(30), .r = 30, .g = void{}});
    try rt.process(0);
    rl.endDrawing();


    while (!rl.windowShouldClose()) {
    }
}
