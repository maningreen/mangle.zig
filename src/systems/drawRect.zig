const std = @import("std");
const engine = @import("../engine.zig");
const system = engine.system;
const types = @import("../types.zig");
const rl = @import("raylib");

pub const requirements = system.Signature{
    .fields = &.{
        .{
            .name = "pos",
            .type = types.Position,
        },
        .{
            .name = "dem",
            .type = types.Dimensions,
        },
    },
};

pub fn process(comptime T: type, arr: []T, info: engine.RegistryInformation) system.Error!void {
    _ = &.{
        arr,
        info,
    };
    for (arr) |rect| 
        rl.drawRectangleV(rect.pos, rect.dem, .white);
}
