//* This is an example for the mangle.Compose(T), with a particle system

const std = @import("std");
const mangle = @import("mangle");
const system = mangle.system;
const ansi = @import("ansi.zig");
const print = std.debug.print;

const Vec2 = struct {
    // swapped for ease of use in printing
    y: f32,
    x: f32,

    fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    fn scale(a: Vec2, scalar: f32) Vec2 {
        return .{ .x = a.x * scalar, .y = a.y * scalar };
    }
    fn value(v: f32) Vec2 {
        return .{ .x = v, .y = v };
    }
    fn draw(self: Vec2, str: []const u8) void {
        print(ansi.cursor_controls.set_pos, .{ @floor(self.y), @floor(self.x) });
        print("{s}", .{str});
    }
};

const Rectangle = struct {
    pos: Vec2,
    dim: Vec2,

    pub fn drawOutside(self: Rectangle) void {
        const horizontal = "━";
        const vertical = "┃";

        const bases: []const Vec2 = &.{
            self.pos,
            self.pos.add(self.dim),
        };

        for (bases) |base| {
            const castedBase = .{
                .x = @as(u32, @trunc(base.x)),
                .y = @as(u32, @trunc(base.y)),
            };
            for (@as(u32, @trunc(self.pos.x)) + 1..@as(u32, @trunc(self.dim.x)) + @as(u32, @trunc(self.pos.x))) |x| {
                print(ansi.cursor_controls.set_pos, .{ castedBase.y, x });
                print("{s}", .{horizontal});
            }
            for (@as(u32, @trunc(self.pos.y)) + 1..@as(u32, @trunc(self.dim.y)) + @as(u32, @trunc(self.pos.y))) |y| {
                print(ansi.cursor_controls.set_pos, .{ y, castedBase.x });
                print("{s}", .{vertical});
            }
        }
        const tR = "┓";
        const bR = "┛";
        const tL = "┏";
        const bL = "┗";
        const cornerPos: []const struct { char: []const u8, pos: Vec2 } = &.{
            .{
                .char = tL,
                .pos = Vec2{
                    .y = self.pos.y,
                    .x = self.pos.x,
                },
            },
            .{
                .char = tR,
                .pos = Vec2{
                    .y = self.pos.y,
                    .x = self.pos.x + self.dim.x,
                },
            },
            .{
                .char = bL,
                .pos = Vec2{
                    .y = self.pos.y + self.dim.y,
                    .x = self.pos.x,
                },
            },
            .{
                .char = bR,
                .pos = Vec2{
                    .y = self.pos.y + self.dim.y,
                    .x = self.pos.x + self.dim.x,
                },
            },
        };
        for (cornerPos) |t| {
            print(ansi.cursor_controls.set_pos, .{ @as(u32, @trunc(t.pos.y)), @as(u32, @trunc(t.pos.x)) });
            print("{s}", .{t.char});
        }
    }
};

const Position = mangle.Alias(Vec2, "Position");
const Velocity = mangle.Alias(Vec2, "Velocity");
const Wraps = mangle.Alias(void, "Wraps");
const Bounce = mangle.Alias(void, "Bounce");
const Char = u8;

const grid_dimensions: Rectangle = .{
    .pos = Vec2{
        .x = 1,
        .y = 1,
    },
    .dim = Vec2{
        .x = 50,
        .y = 10,
    },
};

const Particle = struct {
    pos: Position,
    vel: Velocity,
    char: Char,
};

const WrappingParticle = struct {
    particle: mangle.Compose(Particle),
    wrap: Wraps = .{ .Wraps = void{} },
};

const DrawParticle = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{ .type = Position, .name = "pos" },
            .{ .type = Char, .name = "char" },
        },
    };

    pub fn process(comptime T: type, item: *T, _: mangle.RegistryInformation) system.Error!void {
        print(ansi.cursor_controls.set_pos, .{ @floor(item.pos.y + grid_dimensions.pos.y), @floor(item.pos.x + grid_dimensions.pos.x) });
        print("{c}", .{item.char});
    }
};

const VelocitySystem = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{ .type = Position, .name = "pos" },
            .{ .type = Velocity, .name = "vel" },
        },
    };

    pub fn process(comptime T: type, item: *T, info: mangle.RegistryInformation) system.Error!void {
        // position += vel * delta
        item.pos = item.pos.add(item.vel.scale(info.delta));
    }
};

const WrapSystem = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{ .type = Position, .name = "pos" },
            .{ .type = Wraps, .name = "wrap" },
        },
    };

    pub fn process(comptime T: type, item: *T, _: mangle.RegistryInformation) system.Error!void {
        if (item.pos.x < grid_dimensions.pos.x)
            item.pos.x = grid_dimensions.pos.x + grid_dimensions.dim.x;

        if (item.pos.y < grid_dimensions.pos.y)
            item.pos.y = grid_dimensions.pos.y + grid_dimensions.dim.y;

        if (item.pos.x > grid_dimensions.dim.x + grid_dimensions.pos.y)
            item.pos.x = grid_dimensions.pos.x;

        if (item.pos.y > grid_dimensions.dim.y + grid_dimensions.pos.y)
            item.pos.y = grid_dimensions.pos.y;
    }
};

const BounceSystem = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{
                .type = Position,
                .name = "pos",
            },
            .{
                .type = Velocity,
                .name = "vel",
            },
            .{
                .type = Bounce,
                .name = "bounce",
            },
        },
    };

    // pub fn process(comptime T: type, item: T, _: mangle.RegistryInformation) system.Error!void {
    // }

};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const realClock = std.Io.Clock.real;
    var last_time = realClock.now(init.io);

    const fd = std.posix.STDIN_FILENO;

    // then poll:
    var fds = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    print(ansi.cursor_controls.hide, .{});
    defer print(ansi.cursor_controls.show, .{});
    defer print(ansi.cursor_controls.clear, .{});

    const systems = &.{
        DrawParticle,
        VelocitySystem,
        WrapSystem,
    };
    const types = &.{
        WrappingParticle,
    };
    const Reg = mangle.Registry(types, systems);
    var registry = Reg.init(io, init.gpa);
    defer registry.deinit();

    try registry.addValue(WrappingParticle{ .particle = .{
        .pos = mangle.alias(Position, Vec2{
            .x = 30,
            .y = 30,
        }),
        .vel = mangle.alias(Velocity, Vec2{
            .x = 10,
            .y = 5,
        }),
        .char = 'h',
    } });

    const time_step_s = 0.05;

    while (true) {
        try std.Io.Timeout.sleep(
            .{ .duration = .{
                .raw = .{
                    .nanoseconds = @floor(time_step_s * std.time.ns_per_s),
                },
                .clock = .real,
            } },
            init.io,
        );
        print(ansi.cursor_controls.clear, .{});
        const current = realClock.now(io);
        const delta = @as(f32, @floatFromInt(current.toMilliseconds() - last_time.toMilliseconds())) / std.time.ms_per_s;
        last_time = current;
        try registry.process(delta);

        if (try std.posix.poll(&fds, 0) != 0) {
            // Now it's safe to read
            var buf: [1024]u8 = undefined;
            const n = try std.posix.read(fd, &buf);
            if (std.mem.containsAtLeastScalar(u8, buf[0..n], 1, 'q')) {
                break;
            }
            if (std.mem.containsAtLeastScalar(u8, buf[0..n], 1, 'Q')) {
                break;
            }
        }

        (Rectangle{
            .dim = grid_dimensions.dim.add(.value(2)),
            .pos = grid_dimensions.pos.sub(.value(1)),
        }).drawOutside();

        const quitMessage = "Type 'q' + enter to close";
        print(ansi.cursor_controls.set_pos, .{
            .x = 0,
            .y = @divFloor(grid_dimensions.dim.x, 2) - @divFloor(quitMessage.len, 2),
        });
        print("{s}", .{quitMessage});
    }
}
