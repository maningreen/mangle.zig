const std = @import("std");
const rl = @import("Raylib");
const engine = @import("../engine.zig");
const types = @import("../types.zig");

pub const requirements = engine.system.Signature{
    .items = &.{ types.Position, types.Velocity },
};

pub fn process(comptime T: type, arr: []T, info: engine.RegistryInformation) !void {
    _ = arr;
    _ = info;
}
