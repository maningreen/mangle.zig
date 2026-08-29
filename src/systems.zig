const engine = @import("engine.zig");
const std = @import("std");

pub const systems: []const type = &.{
    @import("systems/drawRect.zig")
    ,
};
