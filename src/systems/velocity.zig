const std = @import("std");
const rl = @import("Raylib");
const engine = @import("../engine.zig");
const types = @import("../types.zig");

pub const requirements = engine.Signature{
    .items = &.{ types.Position, types.Velocity },
};
