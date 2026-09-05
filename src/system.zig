//* The definition and implementations of systems<br>
//* A system requires:
//*     - `requirements: Signature`
//*     - `process: fn` and/or `recieve: fn`
//* In order to qualify

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const flags = @import("flags.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;

const Argument = struct {
    @"comptime": bool,
    type: ?type,
};

/// Defines required fields used in system.qualifies
pub const fields = struct {
    /// Name and type of the processing function of the system
    pub const process = struct {
        pub const name = "process";
        /// Should be read as
        /// ```zig
        /// fn (comptime T: type, _: *T, _: *const RegistryInformation) Error!void`
        /// ```
        pub const fields: []const Argument = &.{
            .{
                .@"comptime" = true,
                .type = type,
            },
            .{
                .@"comptime" = false,
                .type = null,
            },
            .{
                .@"comptime" = false,
                .type = null,
            },
        };
    };

    /// Name and type of the event function of the system
    pub const recieve = struct {
        pub const name = "recieve";

        /// Should be read as
        /// ```zig
        /// fn (comptime T: type, _: *T, _: *const RegistryInformation) Error!void`
        /// ```
        pub const fields: []const Argument = &.{
            .{
                .@"comptime" = true,
                .type = type,
            },
            .{
                .@"comptime" = false,
                .type = null,
            },
            .{
                .@"comptime" = false,
                .type = null,
            },
            .{
                .@"comptime" = false,
                .type = null,
            },
        };
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

    /// returns whether or not a structure (if not structure returns whether or not it is contained)
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
            .@"struct" => {
                const hasProcess = @hasDecl(System, fields.process.name);
                const hasRecieve = @hasDecl(System, fields.recieve.name);
                if (!(hasProcess or hasRecieve)) return false;
                for (&.{ .{ hasProcess, fields.process }, .{ hasRecieve, fields.recieve } }) |value| {
                    const has, const func = value;
                    if (!has) continue;
                    const funcInfo = switch (@typeInfo(@TypeOf(@field(System, func.name)))) {
                        .@"fn" => |i| i,
                        else => return false,
                    };
                    outer: for (funcInfo.params) |param| {
                        for (func.fields) |arg| {
                            if (param.type == arg.type and param.is_generic == (arg.type == null))
                                continue :outer;
                        } else return false;
                    }
                }
                if (@hasDecl(System, fields.signature.name)) {
                    if (@TypeOf(@field(System, fields.signature.name)) != fields.signature.Type)
                        return false;
                } else return false;
                return true;
            },
            else => return false,
        }
    }
}
