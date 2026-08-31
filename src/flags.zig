const std = @import("std");
const util = @import("util.zig");

test {
    std.testing.refAllDecls(@This());
}

const formats = struct {
    const composed = "__internal_registry_composed_flag__";
    const leaf = "__internal_registry_leaf_flag__";
    const dissolve = "__internal_registry_dissolve_flag__";
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

/// # compose
///
/// Used to tag a type as a composition rather than ownership
///
///> **NOTE**:
///> -  [See also `Leaf`](#mangle.flags.Leaf)
///> -  TODO: allow 'unwrapping'
///> -  `Compose(T)` Will always contain the same memory layout as `T`
///
///> **WARNING**:
///> -  `Compose(T) != T` will always be true
///> -  Declarations are lost, on Compose(T)
///> -  Methods are lost on Compose(T)
pub inline fn Compose(comptime T: type) type {
    comptime {
        if (fieldFlag(T) != .owned)
            @compileError("Error type '" ++ @typeName(T) ++ " 'Already has metadata flag!")
        else
            return ApplyMetadata(T, formats.composed);
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
        return T;
    }
}

/// Given a type T
/// flattens the fields of any substructure fields tagged as `flag` into their parent, in which case `Reduce(T) != T`
/// Otherwise does nothing, in which case `Reduce(T) == T`
///
///> **WARNING**:
///> -  `Reduce(T) != T` is dependent on whether or not it contains a composed field!
///> -  **Declarations are not guaranteed**
///> -  **Methods are not guaranteed**
///
///> **NOTE**:
///> - `Reduce(T) == Flatten(T)` will always be true
///> -  Guarantees a memory equivilent struct when Reduceed
///> - [See also, `flags.Flags.compose`](#mangle.flags.Flags.compose)
///> - [See also, `flags.Reduce`](#mangle.flags.flatten) for a value cast
///
///> **TODO**:
///> - Make name conflicts discarded in preference for higher level ones, and compileError otherwise
pub fn Reduce(comptime T: type, comptime flag: Flags) type {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a struct!"),
        };
        var composedFieldCount: comptime_int = info.fields.len;
        for (info.fields) |value| {
            switch (fieldFlag(value)) {
                .compose => {
                    // - 1 to account for flag
                    composedFieldCount = @typeInfo(Reduce(value.type, flag)).@"struct".fields.len - 1;
                },
                else => continue,
            }
        }
        const dissolveFields: [composedFieldCount]std.meta.FieldEnum(T) = undefined;
        var i = 0;
        for (info.fields) |value| {
            switch (fieldFlag(value)) {
                .compose => {
                    dissolveFields[i] = util.strToEnum(value.name);
                    i += 1;
                },
                else => continue,
            }
        }
        return util.Decompose(T, dissolveFields);
    }
}

/// Given a type T
/// flattens the fields of any substructure fields tagged as [compose](#mangle.flags.Flags.compose) into their parent, in which case `Reduce(T) != T`
/// Otherwise does nothing, in which case `Reduce(T) == T`
///
///> **WARNING**:
///> -  `Reduce(T) != T` is dependent on whether or not it contains a composed field!
///> -  **Declarations are not guaranteed**
///> -  **Methods are not guaranteed**
///
///> **NOTE**:
///> - `Reduce(T) == Flatten(T)` will always be true
///> -  Guarantees a memory equivilent struct when Reduceed
///> - [See also, `flags.Flags.compose`](#mangle.flags.Flags.compose)
///> - [See also, `flags.Reduce`](#mangle.flags.flatten) for a value cast
///
///> **TODO**:
///> - Make name conflicts discarded in preference for higher level ones, and compileError otherwise
pub inline fn Flatten(comptime T: type) void {
    return Reduce(T, .composed);
}

pub fn isFlattened(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            for (info.fields) |field| {
                if (isFlagFormat(field) or !isFlattened(T)) return false;
            } else return true;
        },
        else => true,
    }
}

/// Given a runtime structure instance, returns a casted, flattened version
///
/// Value must be a valid pointer type
///
///> **NOTE**:
///> - [See also, flags.Flatten](#mangle.flags.Flatten) for type generation
///> - Supposed to be equivilent to individually setting fields
///> - Fields with duplicate name and type on different depths are discarded for lower depths
///> - Pointer is owned by caller, and is to `value` as reinterpreted data
pub inline fn flatten(value: anytype) util.PtrReinterpret(@TypeOf(value), Flatten(@TypeOf(value))) {
    comptime {
        std.debug.assert(@typeInfo(@TypeOf(value)) == .pointer);
    }
    return @ptrCast(value);
}

/// Given a type T
/// flattens the fields of any substructure fields tagged as [compose](#mangle.flags.Flags.dissolve) into their parent, in which case `Reduce(T) != T`
/// Otherwise does nothing, in which case `Reduce(T) == T`
///> [See also, flags.Flatten](#mangle.flags.Flatten) for type generation
///> - supposed to be equivilent to individually setting fields
///> **WARNING**:
///> -  `Reduce(T) != T` is dependent on whether or not it contains a composed field!
///> -  **Declarations are not guaranteed**
///> -  **Methods are not guaranteed**
///
///> **NOTE**:
///> - `Reduce(T) == Flatten(T)` will always be true
///> -  Guarantees a memory equivilent struct when Reduceed
///> - [See also, `flags.Flags.compose`](#mangle.flags.Flags.compose)
///> - [See also, `flags.Reduce`](#mangle.flags.flatten) for a value cast
///
///> **TODO**:
///> - Make name conflicts discarded in preference for higher level ones, and compileError otherwise
pub inline fn Dissolve(comptime T: type) void {
    return Reduce(T, .composed);
}

pub fn isDissolved(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            for (info.fields) |field| {
                if (isFlagFormat(field) or !isFlattened(T)) return false;
            } else return true;
        },
        else => true,
    }
}

/// Given a runtime structure instance, returns a casted, flattened version
///
/// Value must be a valid pointer type
///
///> **NOTE**:
///> - [See also, flags.Dissolve](#mangle.flags.Dissolve) for type generation
///> - Supposed to be equivilent to individually setting fields
///> - Fields with duplicate name and type on different depths are discarded for lower depths
///> - Pointer is owned by caller, and is to `value` as reinterpreted data
pub inline fn dissolve(value: anytype) util.PtrReinterpret(@TypeOf(value), Dissolve(@TypeOf(value))) {
    comptime {
        std.debug.assert(@typeInfo(@TypeOf(value)) == .pointer);
    }
    return @ptrCast(value);
}

/// # isFlag
///
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

/// #fieldFlag
///
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
        for (&.{ .leaf, .composed }) |flag| {
            const flagMeta = @field(formats, @tagName(flag));
            for (info.fields) |field|
                if (std.mem.eql(u8, flagMeta, field.name)) return flag;
        } else return .owned;
    }
}
