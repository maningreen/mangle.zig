const std = @import("std");
const mangle = @import("mangle");
const system = mangle.system;

const Message = struct {
    string: []const u8,
    key: u8,

    pub fn deinit(comptime T: type, message: *T, info: anytype) void {
        info.gpa.free(message.string);
    }
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

    pub fn process(comptime T: type, item: *T, info: anytype) !void {
        const stdin = std.Io.File.stdin();
        var buf: [128]u8 = undefined;
        var reader = stdin.readerStreaming(info.io, &buf);
        defer stdin.close(info.io);

        std.debug.print("{s}", .{item.str});
        while (reader.interface.takeByte() catch '0' != item.key) {}
        try info.dropDeferred(item);
        try info.appendDeferred(Message{
            .key = 'q',
            .string = "press q",
        });
    }
};

pub fn main(init: std.process.Init) !void {
    const Registry = mangle.Registry(&.{Message}, &.{MessageSystem}, null);
    var reg = Registry.init(init.io, init.gpa, void{});
    defer reg.deinit();

    const message = "Enter 'e' to close\n";
    const ptr = try init.gpa.alloc(u8, message.len);
    for (message, ptr) |char, *set|
        set.* = char;

    try reg.addValue(Message{
        .key = 'e',
        .string = ptr,
    });

    while (true) {
        try reg.process(0);
    }
}
