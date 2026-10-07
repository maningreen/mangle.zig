//! The definition and implementations of systems<br>
//! A system requires:
//!     - `requirements: Signature`
//!     - `process: fn` and/or `receive: fn`
//! In order to qualify

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const flags = @import("flags.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.lang.Type.Struct.FieldAttributes;

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
    pub const receive = struct {
        pub const name = "receive";

        /// Should be read as
        /// ```zig
        /// fn (comptime T: type, value: *T, event: anytype, registry_info: *RegistryInformation) Error!void`
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
        /// See, also [NamedType](#mangle.system.Signature.NamedType)
        name: []const u8,

        /// Used for matching
        /// `.required` is default behavior,
        /// for other behaviors see [Status](#mangle.system.Signature.Item.Status)
        status: Status = .required,

        pub const Status = enum {
            /// Default behavior:
            /// Item is necessary to match
            required,
            /// Item isn't required, but will be named if present
            /// check with `@hasField()` for presence
            optional,
            /// Item will never be matched with.
            /// If the field is present, matching fails
            excluded,
        };
    };

    /// Requirements
    fields: []const Item,

    /// returns whether or not a structure (if not structure returns whether or not it is contained)
    /// qualifies for the signature
    pub fn qualifies(comptime self: Signature, comptime T: type) bool {
        const info = switch (@typeInfo(flags.Flatten(T))) {
            .@"struct" => |i| i,
            else => @compileError("Error, type '" ++ @typeName(flags.OriginalType(T)) ++ "' is not a struct!"),
        };

        inline for (self.fields) |requirement| {
            if (requirement.status == .optional) continue;

            const U = switch (@typeInfo(requirement.type)) {
                .@"struct" => flags.Flatten(requirement.type),
                else => requirement.type,
            };

            inline for (info.field_types) |Type| {
                switch (flags.fieldFlag(Type)) {
                    .composed => unreachable,
                    else => {
                        const Original = comptime if (flags.isPathed(Type)) flags.OriginalType(Type) else Type;
                        const contains = comptime switch (flags.fieldFlag(requirement.type)) {
                            .owned => U == Original,
                            .leaf => U == Original,
                            .dissolve => U == Original,
                            .composed => unreachable,
                        };
                        switch (requirement.status) {
                            .required => if (contains) break,
                            .excluded => if (contains) return false,
                            else => unreachable,
                        }
                    },
                }
            } else {
                return false;
            }
        }
        return true;
    }

    /// Given a structure type `T` generates a signature from it.
    /// Status for all fields is `required`
    pub fn fromStruct(comptime T: type) Signature {
        comptime {
            const info = switch (@typeInfo(T)) {
                .@"struct" => |i| i,
                else => @compileError("Error: Type '" ++ @typeName(flags.OriginalType(T)) ++ "' is not a struct!"),
            };
            var collectFields: [info.field_names.len]Item = undefined;
            for (info.field_names, info.field_types, 0..) |fieldName, Field, i| {
                collectFields[i] = .{ .name = fieldName, .type = Field };
            }
            const U = struct {
                const fields: [info.field_names.len]Item = collectFields;
            };
            return .{ .fields = &U.fields };
        }
    }

    const voidValue: void = {};

    /// Returns the inputed structure with names according to the fields
    ///
    ///> **NOTE**:
    ///> - `self.NamedType(T) != T` when `self.qualifies(T)` and `self.fields.len > 0`
    ///> - Asserts `self.qualifies(T)`
    ///> - Returns a memory equivilent type to T
    pub fn NamedType(comptime self: Signature, comptime T: type) type {
        var info = util.deStruct(T);
        if (!self.qualifies(T)) {
            for (info.fieldNames, info.fieldTypes) |value, U| {
                @compileLog(value, U);
            }
            @compileLog(info.fieldTypes.len);
            @compileError("Error, type '" ++ @typeName(flags.OriginalType(T)) ++ "' does not qualify!");
        }
        field: for (self.fields) |field| {
            const Flattened = switch (@typeInfo(field.type)) {
                .@"struct" => flags.Flatten(field.type),
                else => field.type,
            };
            for (info.fieldTypes, 0..) |U, i| {
                const Original = if (flags.isPathed(U)) flags.OriginalType(U) else U;
                switch (flags.fieldFlag(Original)) {
                    .dissolve => {
                        if (Original == Flattened) {
                            info.fieldNames[i] = field.name;
                            info.fieldTypes[i] = flags.AliasType(U);
                            info.fieldAttributes[i].default_value_ptr = null;
                            continue :field;
                        }
                    },
                    .leaf, .owned => {
                        if (Original == Flattened) {
                            info.fieldNames[i] = field.name;
                            info.fieldTypes[i] = field.type;
                            continue :field;
                        }
                    },
                    else => unreachable,
                }
            }
        }
        return info.Construct();
    }
};

/// Checks whether the inputed system type qualifies according to `fields`
pub fn qualifies(comptime System: type) bool {
    comptime {
        switch (@typeInfo(System)) {
            .@"struct" => {
                const hasProc = hasProcess(System);
                const hasreceive = hasReceive(System);
                if (!(hasProc or hasreceive)) return false;
                for (&.{ .{ hasProc, fields.process }, .{ hasreceive, fields.receive } }) |value| {
                    const has, const func = value;
                    if (!has) continue;
                    const funcInfo = switch (@typeInfo(@TypeOf(@field(System, func.name)))) {
                        .@"fn" => |i| i,
                        else => return false,
                    };
                    outer: for (funcInfo.param_types) |Param| {
                        for (func.fields) |arg| {
                            if (Param == arg.type)
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

/// returns whether or not `Sys` has a declaration named [fields.receive.name](#mangle.system.fields.receive.name)
pub fn hasReceive(comptime Sys: type) bool {
    return @hasDecl(Sys, fields.receive.name);
}

/// returns whether or not `Sys` has a declaration named [fields.process.name](#mangle.system.fields.process.name)
pub fn hasProcess(comptime Sys: type) bool {
    return @hasDecl(Sys, fields.process.name);
}
