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
pub const alias = flags.alias;

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
            /// fn (comptime T: type, _: T, _: RegistryInformation) Error!void`
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
            /// See, also [NamedType](#mangled.system.Signature.NamedType)
            name: []const u8,
        };

        /// Requirements
        fields: []const Item,

        /// returns whether or not a structure (if not structure returns whether or not is contained)
        /// qualifies for the signature
        pub inline fn qualifies(comptime self: Signature, comptime T: type) bool {
            comptime {
                const info = switch (@typeInfo(flags.Flatten(T))) {
                    .@"struct" => |i| i,
                    else => @compileError("Error, type '" ++ @typeName(T) ++ "' is not a struct!"),
                };
                outer: for (self.fields) |Requirement| {
                    for (info.fields) |field| {
                        switch (flags.fieldFlag(field.type)) {
                            .composed => unreachable,
                            else => {
                                switch (flags.fieldFlag(Requirement.type)) {
                                    .owned, .composed, .leaf => {
                                        if (Requirement.type == field.type) continue :outer;
                                    },
                                    .dissolve => {
                                        if (Requirement.type == field.type or @typeInfo(Requirement.type).@"struct".fields[0].type == field.type)
                                            continue :outer;
                                    },
                                }
                            },
                        }
                    } else return false;
                }
                return true;
            }
        }

        /// Returns the inputed structure with names according to the fields
        ///
        ///> **NOTE**:
        ///> - `self.NamedType(T) != T` when `self.qualifies(T)` and `self.fields.len > 0`
        ///> - Flattens T. See [Flatten](#mangle.flags.Flatten)
        ///> - Asserts `self.qualifies(T)`
        ///> - Returns a memory equivilent type to T
        pub inline fn NamedType(comptime self: Signature, comptime T: type) type {
            comptime {
                var info = util.deStruct(T);
                if (!self.qualifies(T)) @compileError("Error, type '" ++ @typeName(T) ++ "' does not qualify!");
                field: for (self.fields, 0..) |field, i| {
                    for (self.fields) |requirement| {
                        if (requirement.type == field.type) {
                            switch (flags.fieldFlag(requirement.type)) {
                                .dissolve => {
                                    // info.fieldNames[i] = requirement.name;
                                    info.fieldTypes[i] = flags.AliasType(requirement.type);
                                    continue :field;
                                },
                                .leaf, .owned => {
                                    // info.fieldNames[i] = requirement.name;
                                    continue :field;
                                },
                                .composed => unreachable,
                            }
                        }
                    } else {
                        info.fieldNames[i] = std.fmt.comptimePrint("__hidden_field_{d}__", .{i});
                    }
                }
                // for (info.fieldNames, 0..) |name, i| {
                    // @compileLog(std.fmt.comptimePrint("name: {s}, i: {d}", .{ name, i }));
                // }
                return info.Construct();
            }
        }
    };

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
        arg: *T,
        regInfo: RegistryInformation,
    ) Error!void {
        @setEvalBranchQuota(69420);
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
                                field.type,
                                &@field(arg, field.name),
                                regInfo,
                            );
                        },
                        else => continue,
                    }
                },
                else => continue,
            }
        }

        if (!@field(Sys, fields.signature.name).qualifies(T)) return;

        const Named = @field(Sys, fields.signature.name).NamedType(T);
        try @field(Sys, fields.function.name)(Named, @as(*Named, @ptrCast(@alignCast(arg))), regInfo);
    }
};

/// `types` should be all the types the registry will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const type) type {
    // we do a lot of comptime recursion (which is an issue to optimize)
    // so we just set it to an 'arbitrary' big number
    @setEvalBranchQuota(69420);
    comptime {
        // create structure of arrays
        var valueTypes: [types.len]type = undefined;
        var flattened: [types.len]type = undefined;
        for (types, 0..) |T, i| {
            flattened[i] = flags.Flatten(T);
            valueTypes[i] = Array(flattened[i]);
        }

        for (requestedSystems) |System|
            if (!system.qualifies(System)) @compileError("Error: System '" ++ @typeName(System) ++ "' is not a valid system!");

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
                const T = flags.Flatten(@TypeOf(value));
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) break i;
                } else @compileError("Error, type \"" ++ @typeName(T) ++ "\" is not in the Registry!");

                try self.data[i].append(self.info.gpa, flags.flatten(value));
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
            pub const allTypes = flattened;
        };
    }
}
