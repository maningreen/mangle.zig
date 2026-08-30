const std = @import("std");
const Type = std.builtin.Type;

/// Given a type, say `std.mem.Allocator`
/// return the basename of the type, in this case `Allocator`
/// > [!WARNING]
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

/// # DeStructInfo
///
/// Count represents the amount of fields
///
///> [!NOTE]
///> Intended for use at comptime
///> [See also, deStruct](#deStruct)
pub fn DeStructInfo(count: comptime_int) type {
    return struct {
        pub const size = count;

        fieldAttributes: [count]Type.StructField.Attributes,
        fieldNames: [count][]const u8,
        fieldTypes: [count]type,

        /// # expand
        ///
        /// Returns a new type of size `DeStructInfo(count).size + add`
        ///> [!WARNING]
        ///> New items are `= undefined`
        pub fn expand(self: @This(), add: comptime_int) DeStructInfo(@This().size + add) {
            if (add < 0) @compileError("Error: add is < 0, cannot shrink!");
            var ret: DeStructInfo(@This().size + add) = undefined;
            for (@typeInfo(@This()).@"struct".fields) |field| {
                for (@field(self, field.name), 0..) |val, i|
                    @field(ret, field.name)[i] = val;
            }
            return ret;
        }

        ///# Construct
        ///
        /// Constructs a struct with `@Struct` according to fields
        /// [See also ConstructExtra](#ConstructExtra)
        pub inline fn Construct(comptime self: @This()) type {
            return @Struct(.auto, null, &self.fieldNames, &self.fieldTypes, &self.fieldAttributes);
        }

        ///# ConstructExtra
        ///
        /// Constructs a struct with `@Struct` according to fields
        /// allows for extra options passed in
        /// [See also ](#Construct)
        pub inline fn ConstructExtra(comptime self: @This(), layout: std.builtin.Type.ContainerLayout, backing: ?type) type {
            return @Struct(layout, backing, &self.fieldNames, &self.fieldTypes, &self.fieldAttributes);
        }
    };
}

pub fn deStruct(comptime T: type) DeStructInfo(@typeInfo(T).@"struct".fields.len) {
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

pub inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

///# structEql
///
///goes through the fields and applies the `==` operator
///
///> [!WARNING]
///> does not (yet) cover pointers and substructure fields
pub inline fn structEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    std.debug.assert(@typeInfo(T) == .@"struct");
    const tInfo = comptime @typeInfo(T).@"struct";

    var eql: bool = true;
    inline for (tInfo.fields) |field|
        eql = eql and @field(a, field.name) == @field(b, field.name);
    return eql;
}

///# ProjectionType
///
/// Given a structure type and a substructure field, creates a memory equivalent mask structure to access child fields.
/// Example:
/// ```zig
/// const A = struct {
///     sub: struct { i: i32 },
///     otherField: u32,
/// };
/// const cast: *ProjectionType(A, .b) = @ptrCast(&myA);
/// const accessedI = cast.i; // not myA.b.i
/// // cannot access cast.otherField
/// ```
/// Note how you're accessing the substructure field from top level.
///
///> [!NOTE]
///> `ProjectionType(T, .field) != @fieldType(T, "field") and ProjectionType(T, .field) != T`
///> To cast T -> ProjectionType(T) use [Project](#Project)
///> Non-substructure fields are interpreted as garbage data, but not changed.
///> Intended for internal use.
pub fn ProjectionType(
    T: type,
    comptime target: std.meta.FieldEnum(T),
) type {
    comptime {
        const paddingFormat = "_{d}";
        const U = @FieldType(T, @tagName(target));

        std.debug.assert(@typeInfo(T) == .@"struct");
        std.debug.assert(@typeInfo(U) == .@"struct");

        const info = @typeInfo(U).@"struct";
        var fields: [info.fields.len]std.builtin.Type.StructField = undefined;
        for (0..info.fields.len) |i| {
            fields[i] = info.fields[i];
        }

        std.mem.sort(std.builtin.Type.StructField, &fields, void{}, (struct {
            fn lessThan(_: void, a: std.builtin.Type.StructField, b: std.builtin.Type.StructField) bool {
                return @offsetOf(U, a.name) < @offsetOf(U, b.name);
            }
        }).lessThan);

        const baseOffset = @offsetOf(T, @tagName(target));
        var byteOffset: comptime_int = 0;
        var paddingCount: comptime_int = 0;
        for (fields) |field| {
            const globalOffset = baseOffset + @offsetOf(U, field.name);
            if (globalOffset != byteOffset) {
                paddingCount += 1;
                byteOffset = globalOffset;
            }
            byteOffset += @sizeOf(field.type);
        }
        // account for trailing padding
        if (byteOffset != @sizeOf(T)) {
            paddingCount += 1;
            byteOffset = @sizeOf(T);
        }

        var deconInfo: DeStructInfo(paddingCount + @typeInfo(U).@"struct".fields.len) = undefined;
        byteOffset = 0;
        paddingCount = 0;
        var i = 0;
        for (fields) |field| {
            const globalOffset = baseOffset + @offsetOf(U, field.name);
            if (globalOffset != byteOffset) {
                paddingCount += 1;
                const paddingSize = globalOffset - byteOffset;
                byteOffset = globalOffset;
                std.debug.assert(paddingSize >= 0);
                paddingCount += 1;
                byteOffset = globalOffset;
                deconInfo.fieldAttributes[i] = .{ .@"align" = 1 };
                deconInfo.fieldNames[i] = std.fmt.comptimePrint(paddingFormat, .{paddingCount});
                deconInfo.fieldTypes[i] = [paddingSize]u8;
                i += 1;
            }
            byteOffset += @sizeOf(field.type);
            deconInfo.fieldAttributes[i].@"align" = field.alignment;
            deconInfo.fieldAttributes[i].@"comptime" = field.is_comptime;
            deconInfo.fieldAttributes[i].default_value_ptr = field.default_value_ptr;
            deconInfo.fieldTypes[i] = field.type;
            deconInfo.fieldNames[i] = field.name;
            i += 1;
        }
        // account for trailing padding
        if (byteOffset != @sizeOf(T)) {
            paddingCount += 1;
            deconInfo.fieldAttributes[i] = .{};
            deconInfo.fieldNames[i] = std.fmt.comptimePrint(paddingFormat, .{paddingCount});
            deconInfo.fieldTypes[i] = [@sizeOf(T) - @offsetOf(T, @tagName(target)) - @sizeOf(U)]u8;
            i += 1;
        }

        return deconInfo.ConstructExtra(.@"extern", null);
    }
}

///# project
///
/// Given a structure and field tag, masks all other fields to access the substructure's fields with dot syntax from top level
/// Example:
/// ```zig
/// const A = struct {
///     sub: struct { i: i32 },
///     otherField: u32,
/// };
/// const cast: *ProjectionType(A, .b) = project(myA, .b);
/// const accessedI = cast.i; // not myA.b.i
/// // cannot access cast.otherField
/// ```
///
///> [!NOTE]
///> To generate the type, see [ProjectionType](#ProjectionType)
///> Pointer is owned by caller, and is to `*value`
///> No runtime overhead
///> Works on any pointer type
pub inline fn project(
    value: anytype,
    comptime target: std.meta.FieldEnum(@typeInfo(@TypeOf(value)).pointer.child),
) ProjectPointerType(@TypeOf(value), target) {
    @setEvalBranchQuota(34000 * 2);
    comptime {
        const info = @typeInfo(@TypeOf(value));
        std.debug.assert(info == .pointer);
        std.debug.assert(@typeInfo(info.pointer.child) == .@"struct");
    }
    const Projected = ProjectPointerType(@TypeOf(value), target);
    return @as(Projected, @ptrCast(value));
}

pub inline fn ProjectPointerType(
    comptime T: type,
    comptime target: std.meta.FieldEnum(@typeInfo(T).pointer.child),
) type {
    return @Pointer(
        @typeInfo(T).pointer.size,
        .{
            .@"align" = @typeInfo(T).pointer.alignment,
            .@"addrspace" = @typeInfo(T).pointer.address_space,
            .@"allowzero" = @typeInfo(T).pointer.is_allowzero,
            .@"const" = @typeInfo(T).pointer.is_allowzero,
            .@"volatile" = @typeInfo(T).pointer.is_volatile,
        },
        ProjectionType(@typeInfo(T).pointer.child, target),
        null,
    );
}

pub inline fn strToTagComptime(comptime str: []const u8, comptime E: type) ?E {
    for (std.enums.values(E)) |value| {
        if (strEql(str, @tagName(value))) return value;
    } else return null;
}
