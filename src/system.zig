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

            inline for (info.field_types, info.field_attrs) |Type, attr| {
                switch (flags.fieldFlag(Type)) {
                    .composed => unreachable,
                    else => {
                        const Original = comptime if (flags.isPathed(Type)) flags.OriginalType(Type) else Type;
                        const contains = comptime lb: switch (flags.fieldFlag(requirement.type)) {
                            .owned => U == Original,
                            .leaf => U == Original,
                            .dissolve => U == Original,
                            .composed => unreachable,
                            .implicit => continue :lb if (attr.@"comptime") .leaf else .owned,
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
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: Type '" ++ @typeName(flags.OriginalType(T)) ++ "' is not a struct!"),
        };
        comptime var collectFields: [info.field_names.len]Item = undefined;
        for (info.field_names, info.field_types, 0..) |fieldName, Field, i| {
            collectFields[i] = .{ .name = fieldName, .type = Field };
        }
        const U = struct {
            const fields: [info.field_names.len]Item = collectFields;
        };
        return .{ .fields = &U.fields };
    }

    const voidValue: void = {};

    ///Returns the inputted structure with names according to the fields
    ///
    ///> **NOTE**:
    ///> - `self.NamedType(T) != T` when `self.qualifies(T)` and `self.fields.len > 0`
    ///> - Asserts `self.qualifies(T)`
    ///> - Returns a memory equivalent type to T[^1]
    ///
    ///[^1]: technically not guaranteed.
    pub fn NamedType(comptime self: Signature, comptime T: type) type {
        var info = util.deStruct(T);
        if (!self.qualifies(T)) {
            for (info.fieldNames, info.fieldTypes) |value, U| {
                @compileLog(value, U);
            }
            @compileError("Error, type '" ++ @typeName(flags.OriginalType(T)) ++ "' does not qualify!");
        }

        for (self.fields) |field| {
            const Flattened = switch (@typeInfo(field.type)) {
                .@"struct" => flags.Flatten(field.type),
                else => field.type,
            };
            for (info.fieldTypes, 0..) |U, i| {
                const Original = if (flags.isPathed(U)) flags.OriginalType(U) else U;
                const fits = Original == Flattened;
                if (fits) {
                    info.fieldNames[i] = field.name;
                }
            }
        }

        for (info.fieldTypes, flags.getFieldFlags(T), 0..) |Field, flag, i| {
            const Original = if (flags.isPathed(Field)) flags.OriginalType(Field) else Field;
            const Type, const default = switch (flag) {
                .dissolve => .{
                    flags.AliasType(Original),
                    if (info.fieldAttributes[i].defaultValue(Field)) |default|
                        &(struct {
                            const value = flags.aliasUnwrap(default);
                        }).value
                    else
                        null,
                },
                .implicit, .leaf, .owned => .{
                    Original,
                    if (info.fieldAttributes[i].defaultValue(Field)) |default|
                        &(struct {
                            const value: Original = flags.originalType(default);
                        }).value
                    else
                        null,
                },
                // composition shouldn't be here
                .composed => unreachable,
            };
            info.fieldAttributes[i].default_value_ptr = default;
            info.fieldTypes[i] = Type;
        }

        return info.Construct();
    }
};

test Signature {
    const NamedCase = struct {
        signature: Signature,
        input: type,
        expected: type,
    };

    const QualifiesCase = struct {
        signature: Signature,
        input: type,
        expected: bool,
    };

    const Empty = struct {};

    const namedTests: []const NamedCase = &.{
        NamedCase{
            .signature = comptime Signature.fromStruct(Empty),
            .input = Empty,
            .expected = Empty,
        },
        NamedCase{
            .signature = comptime Signature.fromStruct(Empty),
            .input = struct { u32 },
            .expected = struct { u32 },
        },
        NamedCase{
            .signature = comptime Signature.fromStruct(struct { item: u32 }),
            .input = struct { u32 },
            .expected = struct { item: u32 },
        },
        NamedCase{
            .signature = comptime Signature.fromStruct(struct {
                item: u32,
            }),
            .input = struct { u32 },
            .expected = struct { item: u32 },
        },
    };

    const qualifyTests: []const QualifiesCase = &.{
        QualifiesCase{
            .signature = comptime Signature.fromStruct(Empty),
            .input = Empty,
            .expected = true,
        },
        QualifiesCase{
            .signature = comptime Signature.fromStruct(struct { u32, usize }),
            .input = Empty,
            .expected = false,
        },
        QualifiesCase{
            .signature = comptime Signature.fromStruct(struct { u32, usize }),
            .input = struct { u32 },
            .expected = false,
        },
        QualifiesCase{
            .signature = comptime Signature.fromStruct(struct { u32, usize }),
            .input = struct { u32, usize },
            .expected = true,
        },
    };

    inline for (namedTests) |case| {
        const Named = case.signature.NamedType(case.signature.NamedType(case.input));
        try std.testing.expect(util.fieldsEql(case.expected, Named) == null);
    }

    inline for (qualifyTests) |case| {
        try std.testing.expectEqual(case.expected, case.signature.qualifies(case.input));
    }
}

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
