//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;
const engine = @This();

const ArrayType = std.ArrayList;

pub const System = struct {
    requirements: Signature,
    /// it's ensured `*anyopaque` will be of self.Type()
    process: fn (*anyopaque, RegistryInformation) ProcessError!void,
    pub const ArrayType = engine.ArrayType;

    pub inline fn Type(comptime self: System) type {
        return self.requirements.GetType();
    }

    /// uses the first instances of all the types
    /// also see: read()
    /// maybe: provide recursion in structures for composition
    pub fn from(comptime self: System, value: anytype) self.Type() {
        const T = @TypeOf(value);
        const tInfo = @typeInfo(T);
        const fieldNames: []const []const u8 = comptime blk: {
            if (!self.requirements.qualifies(T))
                @compileError("Error, type '" ++ @typeName(T) ++ "' doesn't qualify for system requirements! (" ++ std.fmt.comptimePrint("{any}", .{self.requirements.items}));

            var names: [self.requirements.items.len][]const u8 = undefined;

            req: for (self.requirements.items, 0..) |J, i| {
                for (tInfo.@"struct".fields) |f| {
                    if (f.type == J) {
                        names[i] = f.name;
                        continue :req;
                    }
                }
            }
            break :blk &names;
        };

        var tuple: self.requirements.GetType() = undefined;
        inline for (fieldNames, 0..) |fname, i| {
            tuple[i] = @field(value, fname);
        }
        return tuple;
    }

    /// uses the first instances of all the types in requirements
    /// given a signature type and pointer copies values of the signature into the pointer
    /// also see: from()
    /// maybe: provide recursion in structures for composition
    pub fn read(comptime self: System, comptime T: type, ptr: *T, value: self.Type()) void {
        comptime {
            if (!self.requirements.qualifies(T))
                @compileError("Error: Type " ++ @typeName(T) ++ " does not qualify for system!");
        }

        switch (@typeInfo(T)) {
            .@"struct" => |structInfo| {
                inline for (self.requirements.items, 0..) |ReqField, i| {
                    inline for (structInfo.fields) |field| {
                        if (field.type == ReqField) {
                            @field(ptr.*, field.name) = value[i];
                        }
                    }
                }
            },
            else => @compileError("Error, type " ++ @typeName(T) ++ " is not a structure!"),
        }
    }
};

pub const RegistryInformation = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    delta: f32,
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
                else => if (!std.mem.containsAtLeastScalar2(type, self.items, T, 1))
                    return false,
            }
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
                    inline for (systems) |sys| {
                        if (sys.requirements.qualifies(T)) {
                            for (arr.items) |*i| {
                                var t = sys.from(i.*);
                                try sys.process(&t, self.info);
                                sys.read(T, i, t);
                            }
                        }
                    }
                }
            }

            fn getArrayFromType(self: *@This(), comptime T: type) *ArrayType(T) {
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) break i;
                } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in the Registry!");
                return &self.data[i];
            }

            pub const systems: []const System = requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = types;
        };
    }
}

pub const ProcessError = error{ProcessError} || std.mem.Allocator.Error;
