//* This is an example for the mangle.Compose(T), with a particle system

const std = @import("std");
const mangle = @import("mangle");

const Vec2 = struct {
    x: u8,
    y: u8,
};

const Position = Vec2;
const Velocity = Position;
const Char = u8;

const Particle = struct {
    pos: Position,
    vel: Velocity,
    char: Char,
};

pub fn main(init: std.process.Init) !void {
    _ = init;
}
