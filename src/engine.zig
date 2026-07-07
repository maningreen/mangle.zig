//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;

const ArrayType = std.ArrayList;

pub const System = struct {
    requirements: Signature,
    /// it's ensured `anytype` will be of self.Type()
    process: fn (anytype, RegistryInformation) ProcessError!void,
    pub const ArrayType = @This().ArrayType;

    pub inline fn Type(comptime self: System) type {
        return @This().ArrayType(self.requirements.GetType());
    }
};

pub const RegistryInformation = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
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
    pub inline fn qualifies(comptime self: Signature, comptime T: type) bool {
        comptime {
            if (@typeInfo(T) == .@"struct")
                for (@typeInfo(T).@"struct".fields) |j| {
                    if (!std.mem.containsAtLeastScalar2(type, self.items, j.type, 1))
                        return false;
                } else return true;

            if (!std.mem.containsAtLeastScalar2(type, self.items, T, 1))
                return false;
        }
    }
};

/// `types` should be all the types the engine will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const System) type {
    comptime {
        // create structure of arrays
        var valueTypes: [types.len]type = undefined;
        for (types, 0..) |T, i|
            valueTypes[i] = ArrayType(T);

        const DataType = @Tuple(&valueTypes);

        return struct {
            /// the raw data of all the types, a tuple of @This().arrayTypes
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

            pub const systems: [requestedSystems.len]System = &requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = types;
        };
    }
}

pub const ProcessError = error{ProcessError} || std.mem.Allocator.Error;
