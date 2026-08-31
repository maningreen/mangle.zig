const std = @import("std");
const meta = std.meta;
pub const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;
const engine = @This();
pub const flags = @import("flags.zig");
pub const Compose = flags.Compose;
pub const Leaf = flags.Leaf;
pub const Own = flags.Own;

test {
    std.testing.refAllDecls(@This());
}

pub const Array = std.ArrayList;

pub const RegistryInformation = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    delta: f32,
};

pub const system = struct {
    pub const Error = error{ProcessError} || std.mem.Allocator.Error;

    /// Defines required fields used in system.qualifies
    pub const fields = struct {
        /// Name and type of the function of the system
        pub const function = struct {
            const name = "process";
            /// Should be read as
            /// ```zig
            /// fn (comptime T: type, _: []T, _: RegistryInformation) Error!void`
            /// ```
            pub const Type: type = fn (comptime type, anytype, RegistryInformation) Error!void;
        };

        /// Name and type of the signature of the system
        pub const signature = struct {
            pub const name = "requirements";
            pub const Type = Signature;
        };
    };

    pub const Signature = struct {
        /// Used to represent a signature requirement
        pub const Item = struct {
            /// Used to filter qualifications
            type: type,

            /// Used for systems to use dot syntax access
            /// Ignored in qualifications
            name: []const u8,
        };

        /// Requirements
        fields: []const Item,

        /// returns whether or not a structure (if not structure returns whether or not is contained)
        /// qualifies for the signature
        /// maybe: provide recursion in structures for composition
        pub inline fn qualifies(comptime self: Signature, comptime T: type) bool {
            comptime {
                const info = switch (@typeInfo(flags.Flatten(T))) {
                    .@"struct" => |i| i,
                    else => @compileError("Error, type '" ++ @typeName(T) ++ "' is not a struct!"),
                };
                outer: for (self.fields) |Requirement| {
                    for (info.fields) |field| {
                        if (field.type == Requirement.type) continue :outer;
                    } else return false;
                }
                return true;
            }
        }

        /// # NamedType
        ///
        /// Returns the inputed structure with names according to the fields
        ///
        ///> **NOTE**:
        ///> - `self.NamedType(T) != T` when `self.qualifies(T)` and `self.fields.len > 0`
        ///> - Flattens T. See [Flatten](#flatten)
        ///> - Asserts `self.qualifies(T)`
        ///> - Returns a memory equivilent type to T
        pub inline fn NamedType(comptime self: Signature, comptime T: type) type {
            comptime {
                var info = util.deStruct(T);
                if (!self.qualifies(T)) @compileError("Error, type '" ++ @typeName(T) ++ "' does not qualify!");
                field: for (self.fields) |field| {
                    for (info.fieldTypes, 0..) |U, i| {
                        if (U == field.type) {
                            info.fieldNames[i] = field.name;
                            continue :field;
                        }
                    }
                }
                return info.Construct();
            }
        }
    };

    /// # qualifies
    ///
    /// Checks whether the inputed system type qualifies according to `fields`
    pub fn qualifies(comptime System: type) bool {
        comptime {
            switch (@typeInfo(System)) {
                .@"struct" => |info| {
                    for (info.decls) |d| {
                        if (std.mem.eql(u8, d.name, fields.signature.name) and @TypeOf(@field(System, d.name)) == fields.signature.Type)
                            break;
                    } else return false;
                    for (info.decls) |d| {
                        if (std.mem.eql(u8, d.name, fields.function.name) and @TypeOf(@field(System, d.name)) == fields.function.Type)
                            break;
                    } else return false;
                    return true;
                },
                else => return false,
            }
        }
    }

    pub inline fn processWrapper(
        comptime Sys: type,
        comptime T: type,
        arg: []T,
        regInfo: RegistryInformation,
    ) Error!void {
        // if (!@field(Sys, fields.signature.name).qualifies(T)) return;

        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a struct!"),
        };

        inline for (info.fields) |field| {
            switch (@typeInfo(field.type)) {
                .@"struct" => {
                    switch (flags.fieldFlag(field.type)) {
                        .owned => {
                            comptime if (@typeInfo(field.type) != .@"struct") continue;
                            try processWrapper(
                                Sys,
                                util.ProjectionType(T, util.strToTagComptime(field.name, std.meta.FieldEnum(T)).?),
                                util.project(arg, util.strToTagComptime(field.name, std.meta.FieldEnum(T)).?),
                                regInfo,
                            );
                        },
                        .leaf => continue,
                        else => unreachable,
                    }
                },
                else => continue,
            }
        }

        if (!@field(Sys, fields.signature.name).qualifies(T)) return;

        const Named = @field(Sys, fields.signature.name).NamedType(T);
        try @field(Sys, fields.function.name)(Named, @as([]Named, @ptrCast(@alignCast(arg))), regInfo);
    }
};

/// `types` should be all the types the engine will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const type) type {
    // we do a lot of comptime recursion (which is an issue to optimize)
    // so we just set it to an arbitrary big number
    @setEvalBranchQuota(69420);
    comptime {
        // create structure of arrays
        var valueTypes: [types.len]type = undefined;
        var flattenedTypes: [types.len]type = undefined;
        for (types, 0..) |T, i| {
            flattenedTypes[i] = flags.Flatten(T);
            valueTypes[i] = Array(flattenedTypes[i]);
        }

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
                        std.debug.print("Type {} qualifies for: ", .{T});
                        inline for (systems) |Sys| {
                            if (Sys.requirements.qualifies(T)) {
                                std.debug.print("{}, ", .{Sys});
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

            /// # addValue
            ///
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
                const Flattened = flags.Flatten(T);
                const toAdd = if (T != Flattened) flags.flatten(value) else value;
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (Flattened == J) break i;
                } else @compileError("Error, type \"" ++ @typeName(T) ++ "\" is not in the Registry!");

                try self.data[i].append(self.info.gpa, toAdd);
            }

            pub fn process(self: *@This(), delta: f32) !void {
                self.info.delta = delta;
                inline for (allTypes) |T| {
                    const arr = self.getArrayFromType(T);
                    inline for (systems) |Sys|
                        try system.processWrapper(Sys, T, arr.items, self.info);
                }
            }

            fn getArrayFromType(self: *@This(), comptime TPrime: type) *Array(flags.Flatten(TPrime)) {
                const T = flags.Flatten(TPrime);
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) {
                        break i;
                    }
                } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in the Registry!");
                return &self.data[i];
            }

            pub const systems: []const type = requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = flattenedTypes;
        };
    }
}
