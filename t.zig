const std = @import("std");

fn Test(comptime T: type) type {
    return struct { value: T };
}
pub fn main(init: std.process.Init) !void {
    _ = init;
    const T = u32;
    std.log.debug("{}", .{ Test(T) == Test(u32)});
}
