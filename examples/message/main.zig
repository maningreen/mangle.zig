const std = @import("std");
const mangle = @import("mangle");
const system = mangle.system;

const Key = u8;

const Message = struct {
    string: []const u8,
    key: Key,
};

const MessageSystem = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{
                .name = "str",
                .type = []const u8,
            },
            .{
                .name = "key",
                .type = Key,
            },
        },
    };

    pub fn process(comptime T: type, args: []T, info: mangle.RegistryInformation) system.Error!void {
        const stdin = std.Io.File.stdin();
        var buf: [128]u8 = undefined;
        var reader = stdin.readerStreaming(info.io, &buf);
        defer stdin.close(info.io);

        // This is asserting that every requirement type is a field in T
        // Will never throw
        comptime {
            for (requirements.fields) |requirement| {
                for (@typeInfo(T).@"struct".fields) |field| {
                    if (field.type == requirement.type) break;
                } else @compileError("Unreachable");
            }
        }

        for (args) |item| {
            std.debug.print("{s}", .{item.str});
            while (reader.interface.takeByte() catch '0' != item.key) {}
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const Registry = mangle.Registry(&.{Message}, &.{MessageSystem});
    var reg = Registry.init(init.io, init.gpa);
    defer reg.deinit();

    try reg.addValue(Message{
        .key = 'e',
        .string = "Enter 'e' to close\n",
    });

    try reg.process(0);
}
