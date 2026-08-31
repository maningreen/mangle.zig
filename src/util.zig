const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

const paddingFmt = "__explicit_padding_{d}__";

/// Given a type, say `std.mem.Allocator`
/// return the basename of the type, in this case `Allocator`
/// > **WARNING**:
/// > May be ambiguous for nonunique names, when being unique matters, such as indexing use `@typeName()`
pub fn getBaseName(comptime T: type) [:0]const u8 {
    comptime {
        const full_name = @typeName(T);
        // Find the last index of '.'
        if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |index|
            return full_name[index + 1 ..];
        return full_name;
    }
}

/// Count represents the amount of fields
///
///> **NOTE**:
///> - Intended for use at comptime
///> [See also, deStruct](#mangle.util.deStruct)
pub fn DeStructInfo(count: comptime_int) type {
    return struct {
        pub const size = count;

        fieldAttributes: [count]std.builtin.Type.StructField.Attributes,
        fieldNames: [count][]const u8,
        fieldTypes: [count]type,

        /// Returns a new type of size `DeStructInfo(count).size + add`
        ///> **WARNING**:
        ///> - New items are `= undefined`
        pub fn expand(self: @This(), add: comptime_int) DeStructInfo(@This().size + add) {
            if (add < 0) @compileError("Error: add is < 0, cannot shrink!");
            var ret: DeStructInfo(@This().size + add) = undefined;
            for (@typeInfo(@This()).@"struct".fields) |field| {
                for (@field(self, field.name), 0..) |val, i|
                    @field(ret, field.name)[i] = val;
            }
            return ret;
        }

        /// Constructs a struct with `@Struct` according to fields
        /// [See also ConstructExtra](#mangle.util.DeStructInfo.ConstructExtra)
        pub inline fn Construct(comptime self: @This()) type {
            return @Struct(.auto, null, &self.fieldNames, &self.fieldTypes, &self.fieldAttributes);
        }

        /// Constructs a struct with `@Struct` according to fields
        /// allows for extra options passed in
        /// [See also ](#mangle.Util.DeStructInfo.Construct)
        pub inline fn ConstructExtra(comptime self: @This(), layout: std.builtin.Type.ContainerLayout, backing: ?type) type {
            return @Struct(layout, backing, &self.fieldNames, &self.fieldTypes, &self.fieldAttributes);
        }
    };
}

pub inline fn deStruct(comptime T: type) DeStructInfo(@typeInfo(T).@"struct".fields.len) {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a structure!"),
        };
        var ret: DeStructInfo(info.fields.len) = undefined;
        for (info.fields, 0..) |field, i| {
            ret.fieldAttributes[i].@"align" = field.alignment;
            ret.fieldAttributes[i].@"comptime" = field.is_comptime;
            ret.fieldAttributes[i].default_value_ptr = field.default_value_ptr;
            ret.fieldTypes[i] = field.type;
            ret.fieldNames[i] = field.name;
        }
        return ret;
    }
}

/// Sorts DeStructInfo by memory offset, and includes padding.
/// When constructing, it's recommended to use [ConstructExtra(.@"extern")](#mangle.util.DeStructInfo.ConstructExtra)
///
///> **NOTE**:
///> - See also [deStruct](#mangle.util.deStruct)
pub inline fn deStructLayout(comptime T: type) DeStructInfo(@typeInfo(T).@"struct".fields.len) {
    comptime {
        const info = switch (@typeInfo(T)) {
            .@"struct" => |i| i,
            else => @compileError("Error: type '" ++ @typeName(T) ++ "' is not a structure!"),
        };
        var fields: [info.fields.len]std.builtin.Type.StructField = undefined;
        for (0..info.fields.len) |i|
            fields[i] = info.fields[i];

        std.mem.sortUnstable(std.builtin.Type.StructField, fields, void{}, struct {
            fn lessThan(_: void, a: std.builtin.Type.StructField, b: @TypeOf(a)) bool {
                return @offsetOf(T, a.name) < @offsetOf(T, b.name);
            }
        });

        // represents bytes traversed
        var structI: comptime_int = 0;
        var paddingCount: comptime_int = 0;
        for (fields) |field| {
            if (@offsetOf(T, field.name) != structI)
                paddingCount += 1;
            structI = @offsetOf(T, field.name) + @sizeOf(@FieldType(T, field.name));
        }
        // trailing padding
        if (structI != @sizeOf(T)) paddingCount += 1;

        var ret: DeStructInfo(fields.len + paddingCount) = undefined;

        structI = 0;
        paddingCount = 0;
        var i: comptime_int = 0;
        for (info) |field| {
            if (structI != @offsetOf(T, field.name)) {
                const paddingSize = @offsetOf(T, field.name) - structI;
                structI += paddingSize;
                std.debug.assert(paddingSize > 0);
                ret.fieldAttributes[i].@"align" = 1;
                ret.fieldAttributes[i].@"comptime" = false;
                ret.fieldAttributes[i].default_value_ptr = null;
                ret.fieldTypes[i] = [paddingSize]u8;
                ret.fieldNames[i] = std.fmt.comptimePrint(paddingFmt, .{paddingCount});
                paddingCount += 1;
            }
            ret.fieldAttributes[i].@"align" = field.alignment;
            ret.fieldAttributes[i].@"comptime" = field.is_comptime;
            ret.fieldAttributes[i].default_value_ptr = field.default_value_ptr;
            ret.fieldTypes[i] = field.type;
            ret.fieldNames[i] = field.name;
            structI += @sizeOf(@FieldType(T, field.name));
            i += 1;
        }
        if (structI != @sizeOf(T)) {
            const paddingSize = @sizeOf(T) - structI;
            std.debug.assert(paddingSize > 0);
            ret.fieldAttributes[i].@"align" = 1;
            ret.fieldAttributes[i].@"comptime" = false;
            ret.fieldAttributes[i].default_value_ptr = null;
            ret.fieldTypes[i] = [paddingSize]u8;
            ret.fieldNames[i] = std.fmt.comptimePrint(paddingFmt, .{paddingCount});

            paddingCount += 1;
        }

        return ret;
    }
}

pub inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

///goes through the fields and applies the `==` operator
///
///> **WARNING**:
///> - does not (yet) cover pointers and substructure fields
pub inline fn structEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    std.debug.assert(@typeInfo(T) == .@"struct");
    const tInfo = comptime @typeInfo(T).@"struct";

    var eql: bool = true;
    inline for (tInfo.fields) |field|
        eql = eql and @field(a, field.name) == @field(b, field.name);
    return eql;
}

/// Given a structure and fields, decomposes the structure boundaries between them, raising sub-fields
///
///> **NOTE**:
///> - Does not account for name conflicts (sorry)
///
///> **TODO**
///> - fix: name conflicts
///
///> **COMPILE ERRORS**
///> - targets[n] is not to a sub-structure field
pub inline fn Decompose(comptime T: type, targets: []const std.meta.FieldEnum(T)) type {
    comptime {
        const sortedInfo = deStructLayout(T);
        const targetIndeces: [targets.len]comptime_int = undefined;
        var endFieldsCount = @TypeOf(sortedInfo).count;
        for (targetIndeces, targets) |*i, target| {
            i.* = std.meta.fieldIndex(T, @tagName(target));
            const U = @FieldType(T, @tagName(target));
            endFieldsCount += @TypeOf(deStructLayout(U)).count;
        }

        var endInfo: DeStructInfo(endFieldsCount) = undefined;
        var i = 0;
        outer: for (sortedInfo.fieldAttributes, sortedInfo.fieldNames, sortedInfo.fieldTypes) |fromAttr, fromName, FromType| {
            if (strEql(fromName, @tagName(targets))) {
                const destructedFrom = deStructLayout(FromType);
                for (
                    destructedFrom.fieldAttributes,
                    destructedFrom.fieldNames,
                    destructedFrom.fieldTypes,
                ) |subAttr, subName, SubType| {
                    endInfo.fieldAttributes[i] = subAttr;
                    endInfo.fieldNames[i] = subName;
                    endInfo.fieldTypes[i] = SubType;
                    i += 1;
                }
                continue :outer;
            }
            i += 1;
            endInfo.fieldAttributes[i] = fromAttr;
            endInfo.fieldNames[i] = fromName;
            endInfo.fieldTypes[i] = FromType;
        }
        return endInfo.ConstructExtra(.@"extern", null);
    }
}

/// Given a pointer to a value, returns a pointer back casted as the decomposed value
///
///> **NOTE**:
///> - value *must* be a pointer type.
///> - no runtime overhead
///> - See also [Decompose](#mangle.util.Decompose)
///> - See also [mask](#mangle.util.mask)
pub inline fn decompose(
    value: anytype,
    comptime targets: []const std.meta.FieldEnum(@TypeOf(value)),
) PtrReinterpret(@TypeOf(value), Decompose(@TypeOf(value), targets)) {
    return @ptrCast(value);
}

/// Given a type T and fields, masks the requested fields into padding
///
///> **NOTE**:
///> - Memory equivalence is guarunteed
///> - No name conflicts will happen
///> - See also, [mask](#mangle.util.mask) for a runtime version
pub inline fn Mask(comptime T: type, targets: []const std.meta.FieldEnum(T)) type {
    comptime {
        var info = deStructLayout(T);

        var i = 0;
        var paddingI = 0;
        outer: for (info.fieldAttributes, info.fieldNames, info.fieldTypes) |fromAttr, fromName, FromType| {
            if (strEql(fromName, @tagName(targets))) {
                info.fieldAttributes[i] = .{ .@"align" = 1, .is_comptime = false, .default_value_ptr = null };
                info.fieldNames[i] = std.fmt.comptimePrint(paddingFmt, paddingI);
                info.fieldTypes[i] = [@sizeOf(FromType)]u8;
                paddingI += 1;
                i += 1;
                continue :outer;
            }
            i += 1;
            info.fieldAttributes[i] = fromAttr;
            info.fieldNames[i] = fromName;
            info.fieldTypes[i] = FromType;
        }
        return info.ConstructExtra(.@"extern", null);
    }
}

/// Given a pointer to a value, returns a pointer back casted as the masked value
///
///> **NOTE**:
///> - Value *must* be a pointer type.
///> - No runtime overhead
///> - See also [decompose](#mangle.util.decompose)
///> - See also [Mask](#mangle.util.Mask)
pub inline fn mask(
    value: anytype,
    comptime targets: []const std.meta.FieldEnum(@TypeOf(value)),
) PtrReinterpret(@TypeOf(value), Mask(@TypeOf(value), targets)) {
    return @ptrCast(value);
}

/// Given a string, returns an enum literal
pub inline fn strToEnum(comptime str: []const u8) @EnumLiteral() {
    comptime {
        const T = @Enum(u1, .nonexhaustive, &.{str}, &.{0});
        return @as(@EnumLiteral(), @field(T, str));
    }
}

/// Given an In pointer, is reinterpreted into an Element type,
///> **NOTE**:
///> - Asserts sizes and alignments are the same, otherwise a compile error will be emitted
pub inline fn PtrReinterpret(comptime In: type, comptime Element: type) type {
    comptime {
        const inInfo = switch (@typeInfo(In)) {
            .pointer => |i| i,
            else => @compileError("Error: type '" ++ @typeName(In) ++ "' is not a pointer!"),
        };
        if (inInfo.alignment != @alignOf(Element)) @compileError("Error: alignment of '" ++ @typeName(In) ++ "' and '" ++ @typeName(Element) ++ "' differ, cannot cast!");
        if (@sizeOf(inInfo.child) != @sizeOf(Element)) @compileError("Error: size of '" ++ @typeName(In) ++ "' and '" ++ @typeName(Element) ++ "' differ, cannot cast!");
        return @Pointer(
            inInfo.size,
            .{
                .@"addrspace" = inInfo.address_space,
                .@"align" = inInfo.alignment,
                .@"allowzero" = inInfo.is_allowzero,
                .@"const" = inInfo.is_const,
                .@"volatile" = inInfo.is_volatile,
            },
            Element,
            null,
        );
    }
}
