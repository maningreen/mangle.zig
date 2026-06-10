//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;

pub const types = @import("ecsTypes");
pub const TypesEnum = meta.DeclEnum(types);

pub const SystemArrayType = std.ArrayList;

pub fn GenerateDataType(comptime dataTypes: []const type) type {
    comptime {
        var names: [][]const u8 = undefined;
        for (dataTypes, 0..) |T, i| {
            assertIsSystem(T);
            names[i] = @typeName(T);
        }

        @Struct(
            .auto,
            null,
            names,
            dataTypes.types,
            .{ .default_value_ptr = &.{} } ** dataTypes.len,
        );
    }
}

pub fn assertIsSystem(comptime T: type) void {
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
            assertIsSystem(T);
            return @hasDecl(T, "systemOptions");
        }
    }
};

/// given a system type `T` searches for a decl of name ${SystemOptions.declName}
/// if found returns that
/// otherwise returns default
pub fn getSystemOpts(comptime T: type) SystemOptions {
    comptime {
        assertIsSystem(T);
        return if (SystemOptions.SystemHasOptions(T)) @field(T, SystemOptions.declName) else .{};
    }
}

pub fn getSystemChildType(comptime T: type) type {
    comptime {
        assertIsSystem(T);
        return @field(T, getSystemOpts(T).childTypeName);
    }
}

pub fn getSystemType(comptime t: TypesEnum) type {
    comptime {
        return @field(types, @tagName(t));
    }
}

pub fn getSystemSliceType(comptime t: TypesEnum) type {
    comptime {
        const System = getSystemType(t);
        const opts = getSystemOpts(System);
        return []const @field(System, opts.childTypeName);
    }
}

pub const ProcessError = error{ProcessError};
