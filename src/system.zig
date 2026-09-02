const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const flags = @import("flags.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;

/// Defines required fields used in system.qualifies
pub const fields = struct {
    /// Name and type of the function of the system
    pub const function = struct {
        const name = "process";
        /// Should be read as
        /// ```zig
        /// fn (comptime T: type, _: T, _: *const RegistryInformation) Error!void`
        /// ```
        pub const Type: type = fn (comptime type, anytype, anytype) anyerror!void;
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
    regInfo: anytype,
) !void {
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
                    .leaf, .dissolve => continue,
                    else => unreachable,
                }
            },
            else => continue,
        }
    }

    if (!@field(Sys, fields.signature.name).qualifies(T)) return;

    const Eroded = flags.Erode(T);
    comptime {
        std.debug.assert(util.layoutEql(T, Eroded));
    }
    const Named = @field(Sys, fields.signature.name).NamedType(Eroded);
    try @field(Sys, fields.function.name)(Named, @as(*Named, @ptrCast(@alignCast(arg))), regInfo);
}
