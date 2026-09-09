//* This is an example for the mangle.Compose(T), with a particle system
//* It also contains `mangle.Alias(T)`

const std = @import("std");
const mangle = @import("mangle");
const ansi = @import("ansi.zig");
const Vec2 = @import("vec2.zig");
const print = std.debug.print;

// constants
const replicateThreshold = 0.95;

// Simple data types
const Position = mangle.Alias(Vec2, "position");
const Velocity = mangle.Alias(Vec2, "velocty");
const Char = mangle.Alias(u8, "char");
const Rectangle = struct {
    pos: Vec2,
    dim: Vec2,
};
const ReplicateData = struct {
    target_char: Char,
    child: type,
};

// Behavior flags
const Wrap = mangle.Alias(void, "wrap");
const Bounce = mangle.Alias(void, "bounce");

const Particle = struct {
    pos: Position,
    vel: Velocity,
    char: Char = .{ .char = 'a' },
};

const WrappingParticle = struct {
    particle: mangle.Compose(Particle),
    wrap: Wrap = .{ .wrap = {} },
};

const ReplicatingWrap = struct {
    particle: mangle.Compose(WrappingParticle),
    comptime copy: mangle.Leaf(ReplicateData) = .{
        .target_char = mangle.alias(Char, 'w'),
        .child = WrappingParticle,
    },
};

const BouncingParticle = struct {
    particle: mangle.Compose(Particle),
    bounce: Bounce = .{ .bounce = void{} },
};

const ReplicatingBounce = struct {
    bouncing: mangle.Compose(BouncingParticle),
    comptime copy: mangle.Leaf(ReplicateData) = .{
        .target_char = mangle.alias(Char, 'b'),
        .child = BouncingParticle,
    },
};

const DrawParticle = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "pos", .type = Position },
            .{ .name = "char", .type = Char },
        },
    };

    pub fn process(comptime T: type, value: *T, _: anytype) !void {
        value.pos.add(world_border.pos).draw(&.{value.char});
    }
};

const MoveParticle = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "pos", .type = Position },
            .{ .name = "vel", .type = Velocity },
        },
    };

    pub fn process(comptime T: type, value: *T, info: anytype) void {
        value.pos = value.pos.add(value.vel.scale(info.delta));
    }
};

const WrapParticle = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "pos", .type = Position },
            .{ .name = "_", .type = Wrap },
        },
    };

    pub fn process(comptime T: type, value: *T, _: anytype) void {
        value.pos.x -=
            world_border.dim.x * @trunc((2 * (value.pos.x - world_border.dim.x / 2) / world_border.dim.x));
        value.pos.y -=
            world_border.dim.y * @trunc((2 * (value.pos.y - world_border.dim.y / 2) / world_border.dim.y));
    }
};

const BounceParticle = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "pos", .type = Position },
            .{ .name = "vel", .type = Velocity },
            .{ .name = "_", .type = Bounce },
        },
    };

    pub fn process(comptime T: type, value: *T, _: anytype) void {
        if (@abs(value.pos.x - world_border.dim.x / 2) > world_border.dim.x / 2)
            value.vel.x *= -1;
        if (@abs(value.pos.y - world_border.dim.y / 2) > world_border.dim.y / 2)
            value.vel.y *= -1;
    }
};

const ReplicateSystem = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "pos", .type = Position },
            .{ .name = "vel", .type = Velocity },
            .{ .name = "copy", .type = ReplicateData },
        },
    };

    pub fn process(comptime T: type, value: *T, info: anytype) !void {
        if (info.extra.rand.float(f32) > replicateThreshold) {
            const velMag = value.vel.mag();
            try info.appendDeferred(
                value.copy.child{
                    .particle = .{
                        .pos = mangle.alias(Position, value.pos),
                        .vel = mangle.alias(
                            Velocity,
                            Vec2.fromPolar(info.extra.rand.float(f32) * std.math.pi * 2, velMag),
                        ),
                        .char = value.copy.target_char,
                    },
                },
            );
        }
    }
};

const Registry = mangle.Registry(
    &.{
        // Not directly usd in the registry, therefore can be omited
        // Particle,
        WrappingParticle,
        BouncingParticle,
        ReplicatingBounce,
        ReplicatingWrap,
    },
    &.{
        DrawParticle,
        MoveParticle,
        WrapParticle,
        BounceParticle,
        ReplicateSystem,
    },
    struct { rand: std.Random },
);

const timestep: std.Io.Duration = .{ .nanoseconds = 0.1 * std.time.ns_per_s };
const world_border: Rectangle = .{
    .pos = .{ .x = 1, .y = 1 },
    .dim = .{ .x = 50, .y = 25 },
};

comptime {
    @setEvalBranchQuota(100_000);
}

pub fn main(init: std.process.Init) !void {
    const rand = std.Random.IoSource{
        .io = init.io,
    };
    var registry = Registry.init(
        init.io,
        init.gpa,
        .{ .rand = rand.interface() },
    );
    defer registry.deinit();

    try registry.addValue(ReplicatingWrap{
        .particle = .{
            .particle = .{
                .pos = mangle.alias(Position, Vec2{ .x = 2, .y = 2 }),
                .vel = mangle.alias(Velocity, Vec2{ .x = 10, .y = 10 }),
                .char = mangle.alias(Char, 'W'),
            },
        },
    });
    try registry.addValue(ReplicatingBounce{
        .bouncing = .{
            .particle = .{
                .pos = mangle.alias(Position, Vec2{ .x = 3, .y = 4 }),
                .vel = mangle.alias(Velocity, Vec2{ .x = -10, .y = 10 }),
                .char = mangle.alias(Char, 'R'),
            },
        },
    });

    const exit_message = "Press 'q' + enter to quit";

    print(ansi.clear.screen, .{});
    defer print(ansi.clear.screen, .{});

    print(ansi.cursor.hide, .{});
    defer print(ansi.cursor.show, .{});


    outer: while (true) {
        try init.io.sleep(timestep, .real);
        print(ansi.clear.screen, .{});

        // calculate delta during compile time
        const delta: comptime_float = @as(f32, @floatFromInt(timestep.nanoseconds)) / std.time.ns_per_s;
        try registry.process(delta);

        // read from stdin (posix for non-blocking)
        // sorry for non posix :(
        {
            var fds = [_]std.posix.pollfd{.{
                .fd = std.posix.STDIN_FILENO,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};
            if (try std.posix.poll(&fds, 0) != 0) {
                var buf: [128]u8 = undefined;
                const readBytes = try std.posix.read(std.posix.STDIN_FILENO, &buf);
                const read = buf[0..readBytes];
                for (read) |val|
                    // if character 'q' is inputted, break
                    switch (std.ascii.toLower(val)) {
                        'q' => break :outer,
                        else => continue,
                    };
            }
        }

        // draw the world (corners only because i'm lazy)
        // + weird abstraction in order to make it easier
        {
            const box_chars = struct {
                const topLeft = "┌";
                const topRight = "┐";
                const bottomLeft = "└";
                const bottomRight = "┘";
            };

            const corners = &.{
                .{ box_chars.topLeft, Vec2{ .x = 0, .y = 0 } },
                .{ box_chars.topRight, Vec2{ .x = world_border.dim.x + 1, .y = 0 } },
                .{ box_chars.bottomLeft, Vec2{ .x = 0, .y = world_border.dim.y + 2 } },
                .{ box_chars.bottomRight, Vec2{ .x = world_border.dim.x + 1, .y = world_border.dim.y + 2 } },
            };
            inline for (corners) |corner|
                corner[1].draw(corner[0]);
        }

        // draw the exit message
        {
            const position: Vec2 = .{
                .x = (world_border.dim.x - @as(f32, @floatFromInt(exit_message.len))) / 2,
                .y = 0,
            };
            position.draw(exit_message);
        }
    }
}
