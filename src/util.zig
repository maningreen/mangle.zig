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
        pub inline fn Construct(comptime self: @This()) type {
            return @Struct(.auto, null, &self.fieldNames, &self.fieldTypes, &self.fieldAttributes);
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
