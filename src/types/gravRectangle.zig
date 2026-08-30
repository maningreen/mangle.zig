const std = @import("std");
const types = @import("../types.zig");
const Rectangle = @import("rectangle.zig");
const engine = @import("../engine.zig");

rect: engine.Compose(Rectangle),
grav: types.Gravity,
