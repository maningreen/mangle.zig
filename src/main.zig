const std = @import("std");
const engine = @import("engine.zig");
const rl = @import("raylib");

// const testSystem: engine.System = .{
// .requirements = .{ .items = &.{ Radius, Colour, Pos } },
// .process = (struct {
// fn process(val: *anyopaque, _: engine.RegistryInformation) engine.ProcessError!void {
// const T = testSystem.requirements.GetType();
// const circlePtr: *T = @ptrCast(@alignCast(val));
// const circle = circlePtr.*;
// rl.drawCircleV(circle.@"2", circle.@"0", circle.@"1");
// }
// }).process,
// };

// const gravSystem: engine.System = .{
// .requirements = .{ .items = &.{ Pos, Gravity } },
// .process = (struct {
// fn process(val: *anyopaque, i: engine.RegistryInformation) engine.ProcessError!void {
// const T = gravSystem.requirements.GetType();
// const objPtr: *T = @ptrCast(@alignCast(val));
// objPtr[0].y += i.delta * 100;
// }
// }).process,
// };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const stdout = std.Io.File.stdout();
    defer stdout.close(io);

    // const T = struct {
        // r: Radius,
        // c: Colour,
        // p: Pos,
        // g: Gravity,
    // };
    // std.log.debug("size of T: {}", .{@sizeOf(T)});
    const Reg = engine.Registry(&.{}, &.{});

    var rt: Reg = .init(io, init.gpa);

    const ratio: rl.Vector2 = .{ .x = 1920, .y = 1080 };
    const scale: f32 = 0.9;
    rl.initWindow(@intFromFloat(ratio.scale(scale).x), @intFromFloat(ratio.scale(scale).y), "test");
    defer rl.closeWindow();

    rl.setTargetFPS(30);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(.blank);
        try rt.process(rl.getFrameTime());
        rl.endDrawing();
    }
}
