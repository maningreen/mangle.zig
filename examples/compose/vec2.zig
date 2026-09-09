const std = @import("std");
const ansi = @import("ansi.zig");
const Vec2 = @This();

x: f32,
y: f32,

pub fn add(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}
pub fn mul(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x * b.x, .y = a.y * b.y };
}
pub fn sub(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}
pub fn scale(a: Vec2, scalar: f32) Vec2 {
    return .{ .x = a.x * scalar, .y = a.y * scalar };
}

pub fn draw(self: Vec2, str: []const u8) void {
    const casted = .{ @trunc(self.y / 2), @trunc(self.x) };
    std.debug.print(ansi.cursor.set, casted);
    std.debug.print("{s}", .{str});
}
