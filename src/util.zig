//! General, self-contained utilities.uti

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

/// Count represents the amount of fields
///
///> **NOTE**:
///> - Intended for use at comptime
///> [See also, deStruct](#mangle.util.deStruct)
pub fn DeStructInfo(count: comptime_int) type {
    return struct {
        pub const size = count;

        fieldAttributes: [count]std.lang.Type.Struct.FieldAttributes,
        fieldNames: [count][]const u8,
        fieldTypes: [count]type,

        /// Returns a new type of size `DeStructInfo(count).size + add`
        ///> **WARNING**:
        ///> - New items are `= undefined`
        pub fn expand(self: @This(), add: comptime_int) DeStructInfo(@This().size + add) {
            if (add < 0) @compileError("Error: add is < 0, cannot shrink!");
            var ret: DeStructInfo(@This().size + add) = undefined;
            for (@typeInfo(@This()).@"struct".field_names) |name| {
                for (@field(self, name), 0..) |val, i|
                    @field(ret, name)[i] = val;
            }
            return ret;
        }

        /// Constructs a struct with `@Struct` according to fields
        /// [See also ConstructExtra](#mangle.util.DeStructInfo.ConstructExtra)
        pub fn Construct(comptime self: @This()) type {
            return self.ConstructExtra(.auto, null);
        }

        /// Constructs a struct with `@Struct` according to fields
        /// allows for extra options passed in
        /// [See also ](#mangle.Util.DeStructInfo.Construct)
        pub fn ConstructExtra(comptime self: @This(), layout: std.builtin.Type.ContainerLayout, backing: ?type) type {
            var defaultCount: comptime_int = 0;
            for (self.fieldAttributes) |attr| {
                if (attr.default_value_ptr) |_| defaultCount += 1;
            }

            const DefaultContainer = @Tuple(&@as([self.fieldAttributes.len]type, @splat(?*const anyopaque)));
            comptime var default: DefaultContainer = undefined;
            var i = 0;
            for (
                self.fieldAttributes,
            ) |attr| {
                if (attr.default_value_ptr) |ptr| {
                    default[i] = ptr;
                    i += 1;
                }
            }
            const T = struct {
                const value: DefaultContainer = default;
            };
            i = 0;
            var newAttrs: [self.fieldAttributes.len]std.lang.Type.Struct.FieldAttributes = undefined;
            for (self.fieldAttributes, 0..) |attr, j| {
                newAttrs[j] = attr;
                if (attr.default_value_ptr) |_| {
                    newAttrs[j].default_value_ptr = T.value[i];
                    i += 1;
                }
            }

            const Result = @Struct(layout, backing, &self.fieldNames, &self.fieldTypes, &newAttrs);
            return Result;
        }
    };
}

pub fn deStruct(comptime T: type) DeStructInfo(@typeInfo(T).@"struct".field_names.len) {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a structure!"),
        };
        var ret: DeStructInfo(info.field_names.len) = undefined;
        for (info.field_names, info.field_types, info.field_attrs, 0..) |name, Type, attr, i| {
            ret.fieldAttributes[i] = attr;
            ret.fieldTypes[i] = Type;
            ret.fieldNames[i] = name;
        }
        return ret;
    }
}

pub fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// goes through the fields and applies the `==` operator
///
///> **WARNING**:
///> - does not (yet) cover pointers and substructure fields
pub fn structEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    std.debug.assert(@typeInfo(T) == .@"struct");
    const tInfo = comptime @typeInfo(T).@"struct";

    var eql: bool = true;
    inline for (tInfo.field_names) |field|
        eql = eql and @field(a, field) == @field(b, field.name);
    return eql;
}

/// Given a structure and fields, decomposes the structure boundaries between them, raising sub-fields
///
///> **NOTE**:
///> - Does not account for name conflicts (sorry)
///> - Does not create a memory equivalent.
///
///> **TODO**
///> - [ ] fix: name conflicts
///
///> **COMPILE ERRORS**
///> - targets[n] is not to a sub-structure field
pub fn Decompose(comptime T: type, targets: []const std.meta.FieldEnum(T)) type {
    comptime {
        if (targets.len == 0) return T;
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a struct!"),
        };

        var newFieldCount: comptime_int = @typeInfo(T).@"struct".field_names.len;
        for (targets) |target| {
            switch (@typeInfo(@FieldType(T, @tagName(target)))) {
                .@"struct" => |i| newFieldCount += i.field_names.len - 1,
                else => @compileError("Error: field '" ++ @tagName(target) ++ "' on type '" ++ @typeName(T) ++ "' is not a struct!"),
            }
        }

        var reconstructed: DeStructInfo(newFieldCount) = undefined;
        var i = 0;
        for (info.field_names, info.field_types, info.field_attrs) |fieldName, FieldType, fieldAttr| {
            for (targets) |target| {
                if (!strEql(@tagName(target), fieldName))
                    continue;
                const fieldInfo = @typeInfo(FieldType).@"struct";
                for (fieldInfo.field_names, fieldInfo.field_types, fieldInfo.field_attrs) |subFieldName, SubField, subFieldAttr| {
                    reconstructed.fieldTypes[i] = SubField;
                    reconstructed.fieldNames[i] = fieldName ++ "_" ++ subFieldName;
                    reconstructed.fieldAttributes[i] = subFieldAttr;
                    i += 1;
                }
                break;
            } else {
                reconstructed.fieldTypes[i] = FieldType;
                reconstructed.fieldNames[i] = fieldName;
                reconstructed.fieldAttributes[i] = fieldAttr;
                i += 1;
            }
        }

        return reconstructed.Construct();
    }
}

/// Given a value, returns a casted version to the decomposed value
///
///> **NOTE**:
///> - runtime overhead
///> - See also [Decompose](#mangle.util.Decompose)
pub fn decompose(
    value: anytype,
    comptime targets: []const std.meta.FieldEnum(@TypeOf(value)),
) Decompose(@TypeOf(value), targets) {
    const T = @TypeOf(value);
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a struct!"),
    };
    const Fields = std.meta.FieldEnum(T);

    var ret: Decompose(T, targets) = undefined;

    inline for (info.fields) |field| {
        const contains = comptime std.mem.containsAtLeast(Fields, targets, 1, &.{std.meta.stringToEnum(Fields, field.name).?});
        if (contains) {
            const U = field.type;

            const uInfo = switch (@typeInfo(U)) {
                .@"struct" => |i| i,
                else => @compileError("Error: field '" ++ field.name ++ "' is not a struct!"),
            };

            for (uInfo.fields) |subfield| {
                const subName = std.fmt.comptimePrint("{s}_{s}", .{ field.name, subfield.name });
                if (@hasField(T, subName))
                    @field(ret, subName) = @field(@field(value, field.name), subfield.name)
                else
                    @field(ret, subfield.name) = @field(@field(value, field.name), subfield.name);
            }
        }
    }
    return ret;
}

/// Given a string, returns an enum literal
pub fn strToEnum(comptime T: type, comptime str: []const u8) T {
    comptime {
        for (std.enums.values(T)) |tag| {
            if (strEql(@tagName(tag), str))
                return tag;
        } else @compileError("Tag '" ++ str ++ "' does not exist in enums '" ++ @typeName(T) ++ "'");
    }
}

/// Given an In pointer, is reinterpreted into an Element type,
///> **NOTE**:
///> - Asserts sizes and alignments are the same, otherwise a compile error will be emitted
pub fn PtrReinterpret(comptime In: type, comptime Element: type) type {
    comptime {
        const inInfo = switch (@typeInfo(In)) {
            .pointer => |i| i,
            else => @compileError("Error: type '" ++ @typeName(In) ++ "' is not a pointer!"),
        };
        if (@alignOf(inInfo.child) != @alignOf(Element)) @compileError("Error: alignment of '" ++ @typeName(In) ++ "' and '" ++ @typeName(Element) ++ "' differ, cannot cast!");
        if (@sizeOf(inInfo.child) != @sizeOf(Element)) @compileError("Error: size of '" ++ @typeName(In) ++ "' and '" ++ @typeName(Element) ++ "' differ, cannot cast!");
        return @Pointer(
            inInfo.size,
            inInfo.attrs,
            Element,
            null,
        );
    }
}

/// Given type T and U, checks if the memory layout's the same.
///
/// **WARNING**:
///>    - Don't depend on this... It just checks size and alignment.
pub fn layoutEql(comptime T: type, comptime U: type) bool {
    comptime {
        // const sortedT = deStructLayout(T);
        // const sortedU = deStructLayout(U);

        return @sizeOf(T) == @sizeOf(U) and @alignOf(T) == @alignOf(U);

        // for (sortedT.fieldNames, sortedU.fieldNames) |nameT, nameU| {
        // @compileLog(std.fmt.comptimePrint("field '{s}' offset A {}, offset B {}", .{ @offsetOf(T, nameT), @offsetOf(U, nameU) }));
        // if (@offsetOf(T, nameT) != @offsetOf(U, nameU) or @FieldType(T, nameT) != @FieldType(U, nameU))
        // return false;
        // } else return true;
    }
}
