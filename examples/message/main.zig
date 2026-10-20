const std = @import("std");
const mangle = @import("mangle");
const system = mangle.system;

const Message = struct {
    string: []const u8,
    key: u8,

    /// Note: `deinit` doesn't take `Message`, but takes a generic.
    /// The reason is because `mangle` alters the structure, to the point `T != Message`.
    /// However, we can assure that the only thing being inputted is the Registry's internal representation of Message.
    ///
    /// Another thing of note, Systems don't define deinitialization, because they don't define initialization either.
    pub fn deinit(comptime T: type, message: *T, info: anytype) void {
        info.gpa.free(message.string);
    }

    pub fn init(gpa: std.mem.Allocator, str: []const u8, key: u8) !Message {
        const copy = try gpa.alloc(u8, str.len);
        @memcpy(copy, str);
        return .{ .key = key, .string = copy };
    }
};

const MessageSystem = struct {
    pub const requirements = system.Signature{
        .fields = &.{
            .{
                // Message having the field labeled "string", this will still match.
                // The reason is `.type` is the only thing used in matching.
                // `str` is just how the system will access it.
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

        // note how it's `.str` not `.string`
        std.debug.print("{s}", .{item.str});
        while (reader.interface.takeByte() catch 0 != item.key) {}
    }
};

pub fn main(init: std.process.Init) !void {
    const Registry = mangle.Registry(&.{Message}, &.{MessageSystem}, null);
    var reg = Registry.init(init.io, init.gpa, {});
    defer reg.deinit();

    const message = "Enter 'e' to close\n";

    try reg.addValue(try Message.init(init.gpa, message, 'e'));

    // we use 0 for delta because we don't use it otherwise, process is a oneshot.
    try reg.process(0);
}
