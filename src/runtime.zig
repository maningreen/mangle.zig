const std = @import("std");
const engine = @import("engine.zig");
const meta = std.meta;

const TypesEnum = engine.TypesEnum;
const Types = engine.Types;

/// Data container with all the types
data: engine.GenerateDataType(&.{ @import("systems/example.zig") }) = .{},
