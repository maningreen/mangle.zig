const std = @import("std");
const engine = @import("../engine.zig");

pub fn process(_: engine.GenerateDataType(Child), _: u64) engine.ProcessError!void {}
pub fn render(_: []const Child) engine.ProcessError!void {}
pub const Child = void;
