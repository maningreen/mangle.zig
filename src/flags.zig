const std = @import("std");
const util = @import("util.zig");

const formats = struct {
    const composed = "__internal_registry_composed_flag__";
    const leaf = "__internal_registry_leaf_flag__";
};

const voidValue: void = void{};

/// Flags the engine uses internally
pub const Flags = enum {
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
///>[!TODO]
///>  - [ ] allow 'unwrapping'
///>  - [ ] add format checking
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
///> [!NOTE]
///>  [See also `Leaf`](#leaf)
///>  TODO: allow 'unwrapping'
///>  `Compose(T)` Will always contain the same memory layout as `T`
///
///> [!WARNING]
///>  `Compose(T) != T` will always be true
///>  Declarations are lost, on Compose(T)
///>  Methods are lost on Compose(T)
pub inline fn Compose(comptime T: type) type {
    comptime {
        if (fieldFlag(T) != .owned)
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
pub inline fn Leaf(comptime T: type) type {
    comptime {
        if (fieldFlag(T) != .leaf and fieldFlag(T) != .owned)
            @compileError("Error type '" ++ @typeName(T) ++ "'Already has metadata flag!");
        return ApplyMetadata(T, formats.leaf);
    }
}

/// # own
///
/// used to tag a type as ownership (default behavior)
///
///> [!NOTE]
///> can be omitted with no semantic differences
///> Intended for explicit ownership for readability
///> `Own(T) == T`
pub inline fn Own(comptime T: type) type {
    comptime {
        return T;
    }
}

/// # flags.Flatten
///
/// Given a type T
/// flattens the fields of any substructure fields tagged as `flags.Flags.compose` into their parent, in which case `Flatten(T) != T`
/// Otherwise does nothing, in which case `Flatten(T) == T`
///
///> [!WARNING]
///>  `Flatten(T) != T` is dependent on whether or not it contains a composed field!
///>  **Declarations are not guaranteed**
///>  **Methods are not guaranteed**
///>  **Does not guarantee a memory equivilent struct when flattened**
///
///> [!NOTE]
///> `Flatten(T) == Flatten(T)` will always be true
///> [See also, `flags.Flags.compose`](#flags.Flags.compose)
///> [See also, `flags.flatten`](#flags.flatten) for a value cast
pub fn Flatten(comptime T: type) type {
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

        @setEvalBranchQuota(10000);
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

/// # flags.flatten
///
/// Given a runtime structure instance, returns a flattened version
///
///> [!NOTE]
///> [See also, flags.Flatten](#flags.Flatten) for type generation
///> supposed to be equivilent to individually setting fields
///
///> [!WARNING]
///> `@as(Flatten(@TypeOf(value)), @ptrCast(@alignCast(&value)))` is not guaranteed to work
///> as `Flatten(T)` doesn't guarantee a memory equivilent type
pub fn flatten(value: anytype) Flatten(@TypeOf(value)) {
    const T = @TypeOf(value);
    const Flattened = Flatten(T);

    comptime {
        if (T == Flattened) return value;
    }

    const tInfo = comptime util.deStruct(T);
    const flattenedInfo = comptime util.deStruct(Flattened);

    var out: Flattened = undefined;

    inline for (
        flattenedInfo.fieldNames,
        flattenedInfo.fieldTypes,
        flattenedInfo.fieldAttributes,
    ) |targName, TargT, targAttr| {
        inline for (
            tInfo.fieldNames,
            tInfo.fieldTypes,
            tInfo.fieldAttributes,
        ) |fromName, FromT, fromAttr| {
            if (comptime (util.strEql(targName, fromName) and util.structEql(targAttr, fromAttr) and TargT == FromT))
                @field(out, targName) = @field(value, fromName);

            switch (comptime fieldFlag(FromT)) {
                .composed => {
                    const flattenedField = flatten(@field(value, fromName));
                    const U = @TypeOf(flattenedField);
                    const flattenedFieldInfo = comptime util.deStruct(U);
                    inline for (
                        flattenedFieldInfo.fieldNames,
                        flattenedFieldInfo.fieldTypes,
                        flattenedFieldInfo.fieldAttributes,
                    ) |copyName, CopyT, copyAttr| {
                        if (comptime (util.strEql(targName, copyName) and util.structEql(targAttr, copyAttr) and TargT == CopyT))
                            @field(out, targName) = @field(flattenedField, copyName);
                    }
                },
                else => {},
            }
        }
    }

    return out;
}

/// # isFlag
///
/// Returns whether or not str is one of the flag formats
///
///> [!NOTE]
///> [See also flags](#flags)
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
pub fn fieldFlag(T: type) Flags {
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
