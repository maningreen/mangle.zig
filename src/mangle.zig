const std = @import("std");
const meta = std.meta;
pub const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;
pub const flags = @import("flags.zig");
pub const Compose = flags.Compose;
pub const Leaf = flags.Leaf;
pub const Own = flags.Own;
pub const Alias = flags.Alias;
pub const system = @import("system.zig");

test {
    std.testing.refAllDecls(@This());
}

pub const Array = std.ArrayList;


/// `types` should be all the types the registry will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const type) type {
    // we do a lot of comptime recursion (which is an issue to optimize)
    // so we just set it to an 'arbitrary' big number
    @setEvalBranchQuota(69420);
    comptime {
        // create structure of arrays
        var valueTypes: [types.len]type = undefined;
        for (types, 0..) |T, i|
            valueTypes[i] = Array(T);

        for (requestedSystems) |System|
            std.debug.assert(system.qualifies(System));

        const DataType = @Tuple(&valueTypes);

        return struct {
            /// the raw data of all the types, a tuple of @This().array
            /// recommended to not access manually
            data: DataType,
            info: RegistryInformation,

            pub fn init(io: std.Io, gpa: std.mem.Allocator) @This() {
                var data: DataType = undefined;
                inline for (arrayTypes, 0..) |T, i|
                    @field(data, std.fmt.comptimePrint("{d}", .{i})) = T.empty;

                if (@import("builtin").mode == .Debug)
                    inline for (types) |T| {
                        std.debug.print("Type '{}' qualifies for system(s): ", .{T});
                        inline for (systems) |Sys| {
                            if (Sys.requirements.qualifies(T)) {
                                std.debug.print("'{}', ", .{Sys});
                            }
                        }
                        std.debug.print("\n", .{});
                    };

                return .{
                    .data = data,
                    .info = .{
                        .gpa = gpa,
                        .io = io,
                        .delta = 0.0,
                    },
                };
            }

            pub fn deinit(self: *@This()) void {
                inline for (0..types.len) |i|
                    self.data[i].deinit(self.info.gpa);
            }

            /// Given the registry and a value of a type in the registry, adds the value
            /// Returns a pointer to the type new value
            ///
            ///> **NOTE**:
            ///> - Pointer is owned by `self`
            ///> - Pointer may be invalidated between calls of `process`
            ///
            ///> **WARNING**:
            ///> - Returned pointer is not guaranteed to be the same type as `value`
            ///> - May cause runtime overhead if `@TypeOf(value) != flags.Flatten(@TypeOf(value))`
            pub fn addValue(self: *@This(), value: anytype) std.mem.Allocator.Error!void {
                const T = @TypeOf(value);
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) break i;
                } else @compileError("Error, type \"" ++ @typeName(T) ++ "\" is not in the Registry!");

                try self.data[i].append(self.info.gpa, value);
            }

            pub fn process(self: *@This(), delta: f32) !void {
                self.info.delta = delta;
                inline for (allTypes) |T| {
                    const arr = self.getArrayFromType(T);
                    inline for (systems) |Sys|
                        for (arr.items) |*value|
                            try system.processWrapper(Sys, T, value, self.info);
                }
            }

            fn getArrayFromType(self: *@This(), comptime T: type) *Array(T) {
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J)
                        break i;
                } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in the Registry!");
                return &self.data[i];
            }

            pub const systems: []const type = requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = types;
        };
    }
}
