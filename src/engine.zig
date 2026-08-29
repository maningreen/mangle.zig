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
                switch (@typeInfo(flags.Flatten(T))) {
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

    pub fn qualifies(comptime System: type) bool {
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

    pub fn getFieldFromType(comptime T: type, instance: anytype) *T {
        const U = @TypeOf(instance);
        const info = switch (@typeInfo(U)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(U) ++ "' is not a struct!"),
        };
        for (info.fields) |field| {
            const V = field.type;
            switch (@typeInfo(V)) {
                .@"struct" => {},
                else => if (V == T) return &@field(instance, field.name) else continue,
            }
        } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in struct '" ++ @typeName(U) ++ "' as a leaf or owned!");
    }
};

const flags = struct {
    const formats = struct {
        const composed = "__internal_registry_composed_flag__";
        const leaf = "__internal_registry_leaf_flag__";
    };

    const Flags = enum {
        /// default for field structures
        /// processed by systems
        owned,

        /// flattens the field to top level for systems
        composed,

        /// equivilent to a single value
        /// fields are not recursed into
        /// but can be processed by systems
        leaf,
    };

    /// used to tag a type with a metadata tag
    /// metadata *must* contain no formatting
    ///> [!WARNING]
    ///>  `ApplyMetadata(T) != T` will always be true
    ///>  Declarations are lost, on ApplyMetadata(T)
    ///>  Methods are lost on ApplyMetadata(T)
    ///
    ///>[!NOTE]
    ///>  todo: allow 'unwrapping'
    ///>  todo: add format checking
    fn ApplyMetadata(comptime T: type, name: []const u8) type {
        comptime {
            // deconstruct T
            const info = switch (@typeInfo(T)) {
                .@"struct" => |sinfo| sinfo,
                else => @compileError("Error, type " ++ @typeName(T) ++ " is not a type which can be composed!"),
            };

            // construct structure information reflecting the input
            var destructed = util.deStruct(T).expand(1);
            const i = @TypeOf(destructed).size - 1;
            destructed.fieldAttributes[i] = .{};
            destructed.fieldTypes[i] = void;
            destructed.fieldNames[i] = name;

            return @Struct(
                info.layout,
                info.backing_integer,
                &destructed.fieldNames,
                &destructed.fieldTypes,
                &destructed.fieldAttributes,
            );
        }
    }

    /// # compose
    ///
    /// used to tag a type as a composition
    ///> [!WARNING]
    ///>  `Compose(T) != T` will always be true
    ///>  Declarations are lost, on Compose(T)
    ///>  Methods are lost on Compose(T)
    ///
    ///> [!NOTE]
    ///>  [See also `Leaf`](#leaf)
    ///>  TODO: allow 'unwrapping'
    inline fn Compose(comptime T: type) type {
        comptime {
            if (fieldFlag(T) != .composed and fieldFlag(T) != .owned)
                @compileError("Error type '" ++ @typeName(T) ++ " 'Already has metadata flag!")
            else
                return ApplyMetadata(T, formats.composed);
        }
    }

    /// # leaf
    ///
    /// used to tag a type as a leaf
    ///> [!WARNING]
    ///>  `Leaf(T) != T` will always be true
    ///>  Declarations are lost, on Leaf(T)
    ///>  Methods are lost on Leaf(T)
    ///
    ///> [!NOTE]
    ///>  [See also `Compose`](#compose)
    ///>  TODO: allow 'unwrapping'
    inline fn Leaf(comptime T: type) type {
        if (fieldFlag(T) != .leaf and fieldFlag(T) != .owned)
            @compileError("Error type '" ++ @typeName(T) ++ "'Already has metadata flag!");
        return ApplyMetadata(T, formats.leaf);
    }

    /// # flatten
    ///
    /// Given a type T
    /// flattens the fields of any substructure fields tagged as `flags.Flags.compose` into their parent, in which case Flatten(T) != T
    /// Otherwise does nothing, in which case Flatten(T) == T
    ///
    ///> [!NOTE]
    ///> **Intended for internal use only**
    ///> [See also, `flags.Flags.compose`](#flags.Flags.compose)
    ///
    ///> [!WARNING]
    ///>  `Flatten(T) != T` is dependent on whether or not it contains a composed field!
    ///>  **Declarations are not guaranteed**!
    ///>  **Methods are not guaranteed**!
    fn Flatten(comptime T: type) type {
        comptime {
            const info = switch (@typeInfo(T)) {
                .@"struct" => |i| i,
                else => return T,
            };

            var addedFieldCount: comptime_int = 0;

            for (info.fields) |field| {
                const U = Flatten(field.type);
                switch (fieldFlag(U)) {
                    .composed => {
                        addedFieldCount += @typeInfo(U).@"struct".fields.len - 1;
                    },
                    else => continue,
                }
            }

            var newInfo = util.deStruct(T).expand(addedFieldCount);
            var i: comptime_int = 0;

            for (info.fields) |field| {
                const U = Flatten(field.type);
                switch (fieldFlag(U)) {
                    .composed => {
                        for (@typeInfo(U).@"struct".fields) |subField| {
                            if (isFlagFormat(subField.name))
                                continue;

                            newInfo.fieldAttributes[i] = .{
                                .default_value_ptr = subField.default_value_ptr,
                                .@"comptime" = subField.is_comptime,
                                .@"align" = subField.alignment,
                            };
                            newInfo.fieldNames[i] = subField.name;
                            newInfo.fieldTypes[i] = subField.type;
                            i += 1;
                        }
                    },
                    else => {
                        newInfo.fieldAttributes[i] = .{
                            .default_value_ptr = field.default_value_ptr,
                            .@"comptime" = field.is_comptime,
                            .@"align" = field.alignment,
                        };
                        newInfo.fieldNames[i] = field.name;
                        newInfo.fieldTypes[i] = field.type;
                        i += 1;
                    },
                }
            }
            return newInfo.Construct();
        }
    }

    /// # isFlag
    ///
    /// Returns whether or not str is one of the flag formats
    ///
    ///> [!NOTE]
    ///> [See also flags](#flags)
    fn isFlagFormat(str: []const u8) bool {
        inline for (std.enums.values(std.meta.DeclEnum(formats))) |decl| {
            if (std.mem.eql(u8, str, @field(formats, @tagName(decl))))
                return true;
        } else return false;
    }
};

pub const Compose = flags.Compose;

/// # own
///
/// used to tag a type as ownership (default behavior)
/// can be omitted with no semantic differences
/// `Own(T) == T`
pub inline fn Own(comptime T: type) type {
    return T;
}

/// #fieldFlag
///
/// Given type T
/// Looks at fields for metadata
/// If not `@typeInfo(T) == .@"struct"`
/// returns .leaf
pub fn fieldFlag(T: type) flags.Flags {
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => return .leaf,
    };
    inline for (&.{ .leaf, .composed }) |flag| {
        const flagMeta = @field(flags.formats, @tagName(flag));
        for (info.fields) |field|
            if (std.mem.eql(u8, flagMeta, field.name)) return flag;
    } else return .owned;
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

                if (@import("builtin").mode == .Debug)
                    inline for (allTypes) |T| {
                        inline for (systems) |Sys| {
                            if (Sys.requirements.qualifies(T)) {
                                std.log.debug("Type '{}' qualifies for system '{}'", .{ T, Sys });
                            }
                        }
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
