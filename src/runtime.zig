const std = @import("std");
const engine = @import("engine.zig");
const meta = std.meta;
const System = engine.System;

pub fn GenerateRuntime(comptime DataTypes: []const type, comptime systems: []const System) type {
    _ = systems;
    return struct {
        const Runtime = @This();
        const SystemsEnum = engine.SystemsEnum;
        const ProcessError = engine.ProcessError;

        /// Data container with all the types
        data: DataType = .{},
        pub const DataType = engine.GenerateDataType(DataTypes);

        pub fn process(self: *Runtime) ProcessError!void {
            inline for (comptime std.enums.values(SystemsEnum)) |tag| {
                std.log.info("running process for {}", .{tag});
                try engine.getSystemType(tag).process(@field(self.data, @tagName(tag)), 0);
            }
        }
    };
}
