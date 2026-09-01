const std = @import("std");
const mangle = @import("mangle");
const system = mangle.system;

const Message = struct {
    string: []const u8,
    key: u8,
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
                .type = u8,
            },
        },
    };

    pub fn process(comptime T: type, item: *T, info: mangle.RegistryInformation) system.Error!void {
        const stdin = std.Io.File.stdin();
        var buf: [128]u8 = undefined;
        var reader = stdin.readerStreaming(info.io, &buf);
        defer stdin.close(info.io);

        std.debug.print("{s}", .{item.str});
        while (reader.interface.takeByte() catch '0' != item.key) {}
    }
};

pub fn main(init: std.process.Init) !void {
    const Registry = mangle.Registry(&.{Message}, &.{MessageSystem});
    var reg = Registry.init(init.io, init.gpa);
    defer reg.deinit();

    try reg.addValue(Message{
        .key = .{ .key = 'e' },
        .string = "Enter 'e' to close\n",
    });

    try reg.process(0);
}
