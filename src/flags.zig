const std = @import("std");
const util = @import("util.zig");

test {
    std.testing.refAllDecls(@This());
}

pub const pathing = struct {
    const pathSubField = "__internal_registry_type_path__";
    const originalSubfield = "__Internal_registry_original_type__";
    pub const path_delimiter = '_';
};
const formats = struct {
    const composed = "__internal_registry_composed_flag__";
    const leaf = "__internal_registry_leaf_flag__";
    const dissolve = "__internal_registry_dissolve_flag__";
    const identity = "__internal_registry_ownership_path__";
};

const voidValue: void = void{};

/// Flags the engine uses internally
pub const Flags = enum {
    /// Default for field structures
    /// Processed by systems
    owned,

    /// Flattens the field to top level for systems
    composed,

    /// Processed as a non-recursive structure
    /// Can be used in qualification but *not* it's fields
    leaf,

    /// Intended for wrapped data types
    /// Used to differentiate types, similar to `leaf` in matching, and compose after
    /// When dissolving, must have *one* field only
    dissolve,
};

/// used to tag a type with a metadata tag
/// metadata *must* contain no formatting
///> **WARNING**:
///> -  `ApplyMetadata(T) != T` will always be true
///> -  Declarations are lost, on ApplyMetadata(T)
///> -  Methods are lost on ApplyMetadata(T)
///
///>**TODO**:
///> -  - [ ] allow 'unwrapping'
///> -  - [ ] add format checking
pub fn ApplyMetadata(comptime T: type, name: []const u8) type {
    comptime {
        // deconstruct T
        const info = switch (@typeInfo(T)) {
            .@"struct" => |sinfo| sinfo,
            else => @compileError("Error, type " ++ @typeName(T) ++ " is not a type which can be composed!"),
        };

        // construct structure information reflecting the input
        var destructed = util.deStruct(T).expand(1);
        const i = @TypeOf(destructed).size - 1;
        destructed.fieldAttributes[i] = .{ .default_value_ptr = &voidValue };
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

/// used to tag a type as a leaf
///> **WARNING**:
///> -  `Leaf(T) != T` will always be true
///> -  Declarations are lost, on Leaf(T)
///> -  Methods are lost on Leaf(T)
///
///> **NOTE**:
///> - `Leaf(T)` where `@typeInfo(T) != .@"struct"` is identity
///> -  [See also `Compose`](#mangle.flags.Compose)
///> -  TODO: allow 'unwrapping'
pub inline fn Leaf(comptime T: type) type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => {
                if (fieldFlag(T) != .owned)
                    @compileError("Error type '" ++ @typeName(T) ++ "'Already has metadata flag!");
                return ApplyMetadata(T, formats.leaf);
            },
            else => {
                if (@typeInfo(T) != .@"struct") return T;
            },
        }
    }
}

/// used to tag a type as ownership (default behavior)
///
///> **NOTE**:
///> - can be omitted with no semantic differences
///> - Intended for explicit ownership for readability
///> - `Own(T) == T`
pub inline fn Own(comptime T: type) type {
    comptime {
        switch (fieldFlag(T)) {
            .composed, .leaf => @compileError("Error, type '" ++ @typeName(T) ++ "' Is already marked as" ++ @tagName(fieldFlag(T))),
            else => {},
        }
        return T;
    }
}

/// Given a type T
/// flattens the fields of any substructure fields tagged as `flag` into their parent, in which case `Reduce(T) != T`
/// Otherwise does nothing, in which case `Reduce(T) == T`
///
///> **WARNING**:
///> -  `Reduce(T) != T` is dependent on whether or not it contains a field with `flag`!
///> -  **Declarations are not guaranteed**
///> -  **Methods are not guaranteed**
///
///> **NOTE**:
///> - [See also, `flags.reduce`](#mangle.flags.reduce) for a value cast
///
///> **TODO**:
///> - Make name conflicts discarded in preference for higher level ones, and compileError otherwise
pub fn Reduce(comptime T: type, comptime flag: Flags) type {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a struct!"),
        };
        var composedFieldCount: comptime_int = 0;
        // var flagCount = 0;
        for (info.fields) |value| {
            if (fieldFlag(value.type) == flag) {
                // - 1 to account for flag
                composedFieldCount += @typeInfo(value.type).@"struct".fields.len - 1;
                // flagCount += 1;
            }
        }

        var decomposeFields: [composedFieldCount]std.meta.FieldEnum(T) = undefined;
        var i = 0;
        for (info.fields) |value| {
            if (isFlagFormat(value.name)) continue;
            if (fieldFlag(value.type) == flag) {
                decomposeFields[i] = util.strToEnum(std.meta.FieldEnum(T), value.name);
                i += 1;
            }
        }

        const Flattened = util.Decompose(T, &decomposeFields);
        const flattenedInfo = util.deStruct(Flattened);
        var ret: util.DeStructInfo(@TypeOf(flattenedInfo).size - 0) = undefined;
        i = 0;
        for (flattenedInfo.fieldNames, flattenedInfo.fieldTypes, flattenedInfo.fieldAttributes) |name, Type, attr| {
            if (isFlagFormat(name)) continue;

            ret.fieldAttributes[i] = attr;
            ret.fieldTypes[i] = Type;
            ret.fieldNames[i] = name;
            i += 1;
        }
        return ret.Construct();
    }
}

/// given value and flags to reduce from the type, recursed through and copies values over.
///
/// See [Reduce(T)](#mangle.flags.Reduce) for more information
pub fn reduce(value: anytype, comptime flag: Flags) Reduce(@TypeOf(value), flag) {
    const T = @TypeOf(value);
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a struct!"),
    };

    var ret: Reduce(T, flag) = undefined;
    inline for (info.fields) |field| {
        switch (@typeInfo(field.type)) {
            .@"struct" => {
                const reduced = reduce(@field(value, field.name), flag);
                inline for (@typeInfo(@TypeOf(reduced)).@"struct".fields) |subfield| {
                    if (@hasField(@TypeOf(ret), subfield.name))
                        @field(ret, field.name) = @field(reduced, subfield.name)
                    else if (@hasField(@TypeOf(ret), field.name ++ "_" ++ subfield.name))
                        @field(ret, field.name ++ "_" ++ subfield.name) = @field(reduced, subfield.name);
                }
            },
            else => @field(ret, field.name) = @field(value, field.name),
        }
    }
    return ret;
}

/// Returns whether or not str is one of the flag formats
///
///> **NOTE**:
///> [See also flags](#mangle.flags.Flags)
pub fn isFlagFormat(str: []const u8) bool {
    inline for (std.enums.values(std.meta.DeclEnum(formats))) |decl| {
        if (std.mem.eql(u8, str, @field(formats, @tagName(decl))))
            return true;
    } else return false;
}

/// Given type T
/// Looks at fields for metadata
/// If not `@typeInfo(T) == .@"struct"`
/// returns .leaf
pub inline fn fieldFlag(comptime T: type) Flags {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => return .leaf,
        };
        for (&.{ .leaf, .composed, .dissolve }) |flag| {
            const flagMeta = @field(formats, @tagName(flag));
            for (info.fields) |field|
                if (std.mem.eql(u8, flagMeta, field.name)) return flag;
        } else return .owned;
    }
}

/// Applies the `.compose` flag to a type
///
/// When processed **and matched** by systems, substructure fields are brought up to top level with [flatten](#mangle.flags.Flatten) ie:
///
/// ```zig
/// const T = struct {
///     field: Compose(U)
/// };
///
/// const U = struct {
///     x: u32
/// };
///
/// /// Flatten(T) is roughly
/// const FlattenedT = struct {
///     x: u32
/// };
/// ```
///
/// See also:
///     - [Flatten(T)](#mangle.flags.Flatten)
///     - [Flags](#mangle.flags.Flags)
///     - [Own(T)](#mangle.flags.Own)
///     - [Leaf(T)](#mangle.flags.Leaf)
pub inline fn Compose(comptime T: type) type {
    comptime {
        switch (fieldFlag(T)) {
            .owned => {},
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is already flagged!"),
        }
        return ApplyMetadata(T, formats.composed);
    }
}

/// Applies the `.dissolve` flag to a type
///
/// When processed by the system **not matched**, substructure fields are brought up to top level with [flatten](#mangle.flags.Flatten) ie:
///
/// ```zig
/// const T = struct {
///     field: Dissolve(U)
/// };
///
/// const U = struct {
///     x: u32
/// };
///
/// // Erode(T) is roughly
/// const FlattenedT = struct {
///     field: u32
/// };
/// ```
///
///> **WARNING**
///> - Dissolve(T) can only be applied to structures with *one* field, otherwise there's an inherit name collision.
///
///
///> **NOTE**
///> - It's recommended that you just use [Alias(T)](#mangle.flags.Alias), this is for if mainly advanced users
///> - See also:
///>    - [Erode(T)](#mangle.flags.Erode)
///>    - [Flags](#mangle.flags.Flags)
///>    - [Own(T)](#mangle.flags.Own)
///>    - [Leaf(T)](#mangle.flags.Leaf)
///>    - [Alias(T)](#mangle.flags.Alias)
///>    - [Compose(T)](#mangle.flags.Compose)
inline fn Dissolve(comptime T: type) type {
    comptime {
        switch (fieldFlag(T)) {
            .owned => {},
            else => |v| @compileError("Error: type '" ++ @typeName(T) ++ "' is already flagged '" ++ @tagName(fieldFlag(v))),
        }
        switch (@typeInfo(T)) {
            .@"struct" => |i| if (i.fields.len > 1) @compileError("Error: type '" ++ @typeName(T) ++ "' contains more than one field!"),
            else => {},
        }
        return ApplyMetadata(T, formats.dissolve);
    }
}

/// Given a type, creates an **unique** structure alias for systems to match to
///
/// Example:
/// ```zig
/// comptime {
///     std.debug.assert(Key != u8);
///     std.debug.assert(Key == Alias(u8, "key"));
///     std.debug.assert(Key.type == u8);
/// }
///
/// const Key = Alias(u8, "key");
/// const ShouldChange = Alias(void, "ShouldChange");
///
/// const MyType = struct {
///     key: Key // will not match with u8
///     should_change: ShouldChange // will not match with void
/// }
/// ```
///
///> **NOTE**
/// Works for any type, ensure `label` is unique.
/// `label` will be the name of the field, and is of type `T`
pub inline fn Alias(comptime Type: type, comptime label: []const u8) type {
    comptime {
        const T = Dissolve(@Struct(
            .auto,
            null,
            &.{label},
            &.{Type},
            &.{
                std.builtin.Type.StructField.Attributes{
                    .@"align" = null,
                    .default_value_ptr = null,
                    .@"comptime" = false,
                },
            },
        ));
        return T;
    }
}

/// Application of `Dissolve`
///
/// For more information see:
///     - [Alias(T)](#mangle.flags.Alias)
///     - [Dissolve(T)](#mangle.flags.Dissolve)
///
/// For a runtime version, see [erode](#mangle.flags.erode)
pub fn Erode(comptime T: type) type {
    comptime {
        return Reduce(T, .dissolve);
    }
}

/// Runtime application of `Dissolve`
///
/// For more information see:
///     - [Alias(T)](#mangle.flags.Alias)
///     - [Dissolve(T)](#mangle.flags.Dissolve)
///
/// For a type version, see [Erode](#mangle.flags.Erode)
pub inline fn erode(value: anytype) Erode(@TypeOf(value)) {
    const T = @TypeOf(value);
    const TPrime = Erode(T);
    if (util.layoutEql(T, TPrime)) {
        const copy = @as(util.PtrReinterpret(*T, TPrime), @ptrCast(&value)).*;
        return copy;
    } else {
        return reduce(value, .dissolve);
    }
}

/// Application of `Compose`
///
/// For more information see: [Compose(T)](#mangle.flags.Compose)
///
/// For a runtime version, see [flatten](#mangle.flags.flatten)
pub inline fn Flatten(comptime T: type) type {
    comptime {
        return Reduce(T, .composed);
    }
}

/// Runtime application of `Compose`
///
/// For more information see: [Compose(T)](#mangle.flags.Compose)
///
/// For a type version, see [Flatten](#mangle.flags.Flatten)
pub inline fn flatten(value: anytype) Flatten(@TypeOf(value)) {
    return reduce(value, .composed);
}

/// Given a type `T`, if ownership is found, applies a pathing to it for runtime indexing
///
///> **NOTE**
///> - see also [path](#mangle.flags.path)
pub inline fn Path(comptime T: type) type {
    comptime {
        return PathInternal(T, "");
    }
}

pub inline fn PathInternal(comptime T: type, comptime prefix: []const u8) type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => void{},
            else => return T,
        }
        if (@hasField(T, formats.identity)) @compileError("Type '" ++ @typeName(T) ++ "' already has a path!");

        var deconstructed = util.deStruct(T);
        for (deconstructed.fieldTypes, deconstructed.fieldNames, 0..) |U, name, i| {
            const newPrefix = prefix ++ .{pathing.path_delimiter} ++ name;
            deconstructed.fieldTypes[i] = PathInternal(U, newPrefix);
        }
        var new = deconstructed.expand(1);
        const i = deconstructed.fieldNames.len;
        new.fieldNames[i] = formats.identity;
        new.fieldTypes[i] = struct {
            const __internal_registry_type_path__ = prefix;
            const __Internal_registry_original_type__ = T;
        };
        new.fieldAttributes[i] = .{};
        return new.Construct();
    }
}

/// Given a pointer value, retypes it into a pathed version.
///
///> **NOTE**:
///> - See also, [Path](#mangle.flags.Path)
pub fn path(value: anytype) util.PtrReinterpret(@TypeOf(value), Path(@typeInfo(@TypeOf(value)).pointer.child)) {
    const info = switch (@typeInfo(@TypeOf(value))) {
        .pointer => |i| i,
        else => @compileError("Error: Type '" ++ @typeName(@TypeOf(value)) ++ "' is not a pointer!"),
    };
    return @as(util.PtrReinterpret(@TypeOf(value), Path(info.child)), @ptrCast(value));
}

/// Returns the type path relative to a registry top level
/// String is delimited with `.` between each parent
pub inline fn getPath(comptime T: type) []const u8 {
    comptime {
        _ = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a struct!"),
        };

        if (@hasField(T, formats.identity)) {
            return @field(@FieldType(T, formats.identity), pathing.pathSubField);
        } else @compileError("Error: '" ++ @typeName(T) ++ "' is not pathed!");
    }
}

pub inline fn OriginalType(comptime T: type) type {
    comptime {
        _ = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a struct!"),
        };

        if (@hasField(T, formats.identity)) {
            return @field(@FieldType(T, formats.identity), pathing.originalSubfield);
        } else @compileError("Error: '" ++ @typeName(T) ++ "' is not pathed!");
    }
}
