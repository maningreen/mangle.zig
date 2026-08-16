const std = @import("std");

/// Given a type, say `std.mem.Allocator`
/// return the basename of the type, in this case `Allocator`
/// | Warning: May be ambiguous for nonunique names, for indexing use @typeName()
pub fn getBaseName(comptime T: type) [:0]const u8 {
    comptime {
        const full_name = @typeName(T);
        // Find the last index of '.'
        if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |index|
            return full_name[index + 1 ..];
        return full_name;
    }
}
