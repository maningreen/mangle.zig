const rl = @import("raylib");

pub const Velocity = rl.Vector2;
pub const Position = rl.Vector2;
pub const Dimensions = rl.Vector2;
pub const Gravity = void;

pub const types: []const type = &.{
    @import("types/rectangle.zig"),
    @import("types/gravRectangle.zig"),
};
