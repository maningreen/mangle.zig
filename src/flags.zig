const std = @import("std");
const util = @import("util.zig");

test {
    std.testing.refAllDecls(@This());
}

const formats = struct {
    const composed = "__internal_registry_composed_flag__";
    const leaf = "__internal_registry_leaf_flag__";
    const dissolve = "__internal_registry_dissolve_flag__";

    const flags = &.{ .composed, .leaf, .dissolve };
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
        @setEvalBranchQuota(69420);
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => return T,
        };

        var decomposeCount = 0;
        for (info.fields) |field| {
            const U = Reduce(field.type, flag);
            if (fieldFlag(field.type) == flag)
                switch (@typeInfo(U)) {
                    .@"struct" => decomposeCount += 1,
                    else => continue,
                };
        }

        var decomposeFields: [decomposeCount]std.meta.FieldEnum(T) = undefined;
        var i = 0;
        for (info.fields) |field| {
            const U = Reduce(field.type, flag);
            if (fieldFlag(field.type) == flag)
                switch (@typeInfo(U)) {
                    .@"struct" => {
                        decomposeFields[i] = util.strToEnum(std.meta.FieldEnum(T), field.name);
                        i += 1;
                    },
                    else => continue,
                };
        }

        const TPrime = util.Decompose(T, &decomposeFields);
        const deconPrime = util.deStruct(TPrime);
        decomposeCount = 0;
        for (deconPrime.fieldNames) |name| {
            if (util.strEql(name, @field(formats, @tagName(flag))))
                decomposeCount += 1;
        }
        var retInfo: util.DeStructInfo(@TypeOf(deconPrime).size - decomposeCount) = undefined;
        i = 0;
        for (deconPrime.fieldNames, deconPrime.fieldTypes, deconPrime.fieldAttributes) |name, Type, attr| {
            if (util.strEql(name, @field(formats, @tagName(flag)))) {
                continue;
            }
            retInfo.fieldNames[i] = name;
            retInfo.fieldTypes[i] = Type;
            retInfo.fieldAttributes[i] = attr;
            i += 1;
        }
        return deconPrime.Construct();
    }
}

/// given value and flags to reduce from the type, recursed through and copies values over.
///
/// See [Reduce(T)](#mangle.flags.Reduce) for more information
pub fn reduce(value: anytype, comptime flag: Flags) Reduce(@TypeOf(value), flag) {
    const T = @TypeOf(value);
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Type '" ++ @typeName(T) ++ "' is not a struct!"),
    };

    const Reduced = Reduce(T, flag);
    const dropFields = comptime blk: {
        var fieldCount = 0;
        for (info.fields) |field| {
            if (@typeInfo(field.type) == .@"struct" and fieldFlag(field.type) == flag)
                fieldCount += 1;
        }

        var fieldsToDrop: [fieldCount]std.meta.FieldEnum(T) = undefined;

        var i = 0;
        for (info.fields, std.enums.values(std.meta.FieldEnum(T))) |field, tag| {
            if (@typeInfo(field.type) == .@"struct" and fieldFlag(field.type) == flag) {
                fieldsToDrop[i] = tag;
                i += 1;
            }
        }
        break :blk fieldsToDrop;
    };
    const casted = util.decompose(value, &dropFields);
    return @as(*const Reduced, @ptrCast(&casted)).*;
}

/// Returns whether or not str is one of the flag formats
///
///> **NOTE**:
///> [See also flags](#mangle.flags.Flags)
pub fn isFlagFormat(str: []const u8) bool {
    @setEvalBranchQuota(5000);
    inline for (formats.flags) |decl| {
        if (std.mem.containsAtLeast(u8, str, 1, @field(formats, @tagName(decl)))) {
            @branchHint(.unlikely);
            return true;
        }
    } else {
        return false;
    }
}

/// Given type T
/// Looks at fields for metadata
/// If not `@typeInfo(T) == .@"struct"`
/// returns .leaf
pub inline fn fieldFlag(comptime T: type) Flags {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct" => {},
            else => return .leaf,
        }
        for (&.{ .leaf, .composed, .dissolve }) |flag| {
            const flagMeta = @field(formats, @tagName(flag));
            if (@hasField(T, flagMeta)) return flag;
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
/// - Works for any type, ensure `label` is unique.
/// - `label` will be the name of the field, and is of type `T`
/// - See [alias](#mangle.flags.alias) for a runtime conversion
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

/// Given an alias type, and the value to wrap, return the wrapped type
///
///> **NOTE**:
///>    - See also, [Alias](mangle.flags.Alias)
pub inline fn alias(comptime T: type, value: anytype) T {
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Error, type '" ++ @typeName(T) ++ "' is not a struct!"),
    };
    comptime {
        switch (fieldFlag(T)) {
            .dissolve => void{},
            inline else => |tag| @compileError("Error: type '" ++ @typeName(T) ++ "' is marked as '" ++ @tagName(tag) ++ "' not `dissolve`!"),
        }
    }
    const field = comptime for (info.fields) |field| {
        if (!isFlagFormat(field.name))
            break field;
    } else @compileError("Error, missing value in '" ++ @typeName(T) ++ "'");

    var t: T = undefined;
    @field(t, field.name) = @as(field.type, value);
    return t;
}

pub fn AliasType(comptime T: type) type {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error, type '" ++ @typeName(T) ++ "' is not a struct!"),
        };
        switch (fieldFlag(T)) {
            .dissolve => void{},
            inline else => |tag| @compileError("Error: type '" ++ @typeName(T) ++ "' is marked as '" ++ @tagName(tag) ++ "' not `dissolve`!"),
        }
        for (info.fields) |field| {
            if (!isFlagFormat(field.name))
                return field.type;
        } else @compileError("Error, missing value in '" ++ @typeName(T) ++ "'");
    }
}

/// Application of `Dissolve`
///
/// For more information see:
///     - [Alias(T)](#mangle.flags.Alias)
///     - [Dissolve(T)](#mangle.flags.Dissolve)
///
/// For a runtime version, see [erode](#mangle.flags.erode)
pub inline fn Erode(comptime T: type) type {
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
