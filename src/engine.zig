//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;

comptime item: u32 = 30,

pub const systems = blk: {
    const arr = @import("ecsTypes.zig").systems;
    var names: [arr.len][]const u8 = undefined;
    var fieldTypes: [arr.len]type = undefined;
    var fieldAttrs: [arr.len]StructField.Attributes = undefined;
    for (arr, 0..) |v, i| {
        const basename = util.getBaseName(v);
        names[i] = basename;
        fieldTypes[i] = type;
        fieldAttrs[i] = StructField.Attributes{
            .default_value_ptr = &v,
            .@"align" = null,
            .@"comptime" = true,
        };
    }
    break :blk @Struct(
        .auto,
        null,
        &names,
        &fieldTypes,
        &fieldAttrs,
    );
};
pub const SystemsEnum = meta.FieldEnum(systems);

pub const SystemArrayType = std.ArrayList;

pub fn GenerateDataType(comptime dataTypes: []const type) type {
    comptime {
        var names: [dataTypes.len][]const u8 = undefined;
        var arrayTypes: [dataTypes.len]type = undefined;
        var atters: [dataTypes.len]std.builtin.Type.StructField.Attributes = undefined;
        for (dataTypes, 0..) |T, i| {
            names[i] = util.getBaseName(T);
            arrayTypes[i] = SystemArrayType(getSystemChildType(T));
            atters[i] = std.builtin.Type.StructField.Attributes{ .default_value_ptr = &arrayTypes[i].empty };
        }

        return @Struct(.auto, null, &names, &arrayTypes, &atters);
    }
}

pub inline fn assertIsSystem(comptime T: type) void {
    comptime {
        const info = @typeInfo(T);
        if (info != .@"struct")
            @compileError("Error, type `" ++ @typeName(T) ++ "` is not a structure!");

        const opts = getSystemOpts(T);

        const procInfo =
            @field(
                T,
                opts.processFunction,
            );
        const childInfo =
            @field(
                T,
                opts.childTypeName,
            );
        const renderInfo =
            @field(
                T,
                opts.renderFunction,
            );

        std.debug.assert(info == .@"struct" and
            @TypeOf(childInfo) == type and
            @TypeOf(procInfo) == fn (SystemArrayType(childInfo), f64) ProcessError!void and
            @TypeOf(renderInfo) == fn ([]const childInfo) void);
    }
}

/// options for a system.
/// if used, place as a decl in the system struct named `systemOptions`
/// ensure public.
pub const SystemOptions = struct {
    /// the name of the function which takes in the ArrayList and the `delta: f64` paramater
    /// and alters the ArrayList
    /// of type `fn (ArrayList(Child), f64) SystemError!void`
    comptime processFunction: []const u8 = "process",
    /// the name of the function which takes in the Array, does not alter it, and draws
    /// of type `fn ([]const Child) void`
    comptime renderFunction: []const u8 = "render",
    /// Name of the child type constant in the struct
    /// of type `type`
    comptime childTypeName: []const u8 = "Child",

    pub const declName = "systemOptions";

    pub fn SystemHasOptions(comptime T: type) bool {
        comptime {
            return @hasDecl(T, declName);
        }
    }
};

/// given a system type `T` searches for a decl of name ${SystemOptions.declName}
/// if found returns that
/// otherwise returns default
pub fn getSystemOpts(comptime T: type) SystemOptions {
    comptime {
        return if (@hasDecl(T, SystemOptions.declName))
            @field(T, SystemOptions.declName)
        else
            .{};
    }
}

pub fn getSystemChildType(comptime T: type) type {
    comptime {
        return @field(T, getSystemOpts(T).childTypeName);
    }
}

pub fn getSystemType(comptime tag: SystemsEnum) type {
    comptime {
        return @field(systems{}, @tagName(tag));
    }
}

pub fn getSystemSliceType(comptime t: SystemsEnum) type {
    comptime {
        const System = getSystemType(t);
        const opts = getSystemOpts(System);
        return []const @field(System, opts.childTypeName);
    }
}

pub const ProcessError = error{ProcessError};
