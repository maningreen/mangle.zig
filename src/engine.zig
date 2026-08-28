//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;
const engine = @This();

pub const Array = std.ArrayList;

pub const RegistryInformation = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    delta: f32,
};

pub const system = struct {
    pub const Error = error{ProcessError} || std.mem.Allocator.Error;
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

    pub fn qualifies(comptime System: type) bool {
        switch (@typeInfo(System)) {
            .@"struct" => |info| {
                for (info.decls) |d| {
                    if (std.mem.eql(u8, d.name, signature.name) and @TypeOf(@field(System, d.name)) == signature.Type)
                        break;
                } else return false;
                for (info.decls) |d| {
                    if (std.mem.eql(u8, d.name, function.name) and @TypeOf(@field(System, d.name)) == function.Type)
                        break;
                } else return false;
                return true;
            },
            else => return false,
        }
    }
};

pub const Signature = struct {
    items: []const type,

    /// returns a tuple
    /// order is dependent on the items
    pub inline fn GetType(self: Signature) type {
        comptime return @Tuple(self.items);
    }

    /// returns whether or not a structure (if not structure returns whether or not is contained)
    /// qualifies for the signature
    /// maybe: provide recursion in structures for composition
    pub inline fn qualifies(comptime self: Signature, comptime T: type) bool {
        comptime {
            switch (@typeInfo(T)) {
                .@"struct" => |tinfo| {
                    return outer: for (self.items) |requirement| {
                        for (tinfo.fields) |field| {
                            if (requirement == field.type)
                                continue :outer;
                        } else break false;
                    } else true;
                },
                else => if (!std.mem.containsAtLeastScalar2(type, self, T, 1))
                    return false,
            }
        }
    }
};

const compositionFormat = "registry_composition_{d}";

pub const FieldStats = enum {
    owned,
    composed,
};

test "Compose" {
}

/// used to tag a type as composition
///     Warnings:
///         `Compose(T) != T` will always be true
///         Declarations are lost, on Compose(T)
///         Methods are lost on Compose(T)
///     TODO: allow 'unwrapping'
pub inline fn Compose(comptime T: type) type {
    comptime {
        // deconstruct T
        const info = switch (@typeInfo(T)) {
            .@"struct" => |sinfo| sinfo,
            else => @compileError("Error, type " ++ @typeName(T) ++ " is not a type which can be composed!"),
        };

        // construct name for field
        var i: comptime_int = 0;
        const name = outer: while (info.fields.len > 0) : (i += 1) {
            for (info.fields) |field| {
                if (!std.mem.eql(u8, std.fmt.comptimePrint(compositionFormat, .{ i }), field.name)) {
                    break :outer std.fmt.comptimePrint(compositionFormat, .{ i });
                }
            }
        } else std.fmt.comptimePrint(compositionFormat, .{ i });
        // construct structure information reflecting the input
        var fieldNames: [info.fields.len + 1][]const u8 = undefined;
        var fieldTypes: [info.fields.len + 1]type = undefined;
        var fieldAttrs: [info.fields.len + 1]std.builtin.Type.StructField.Attributes = undefined;
        fieldNames[0] = name;
        fieldTypes[0] = void;
        fieldAttrs[0] = .{
            .default_value_ptr = null,
            .@"align" = null,
            .@"comptime" = false,
        };
        for (info.fields, 1..) |field, j| {
            fieldNames[j] = field.name;
            fieldTypes[j] = field.type;
            fieldAttrs[j] = std.builtin.Type.StructField.Attributes{
                .default_value_ptr = field.default_value_ptr,
                .@"align" = field.alignment,
                .@"comptime" = field.is_comptime,
            };
        }

        return @Struct(.auto, info.backing_integer, &fieldNames, &fieldTypes, &fieldAttrs);
    }
}

/// used to tag a type as ownership (default behavior)
pub inline fn Own(comptime T: type) type {
    return T;
}

pub fn fieldStatus() !void {

}

/// `types` should be all the types the engine will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const type) type {
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
                        if (Sys.requirements.qualifies(T))
                            try Sys.process(T, arr, self.info);
                }
            }

            fn getArrayFromType(self: *@This(), comptime T: type) *Array(T) {
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) break i;
                } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in the Registry!");
                return &self.data[i];
            }

            pub const systems: []const type = requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = types;
        };
    }
}
