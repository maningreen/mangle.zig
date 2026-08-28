const engine = @import("engine.zig");
const std = @import("std");

pub const systems: []const type = &.{(struct {
    pub const requirements = engine.Signature{ .items = &.{} };
    pub fn process(comptime T: type, arr: *engine.Array(T), i: engine.RegistryInformation) engine.system.Error!void {
        arr.append(i.gpa, .{}) catch return error.ProcessError;
        std.log.debug("{d}", .{arr.items.len});
    }
})};
