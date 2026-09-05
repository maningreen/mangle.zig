const std = @import("std");
const meta = std.meta;
pub const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;
pub const flags = @import("flags.zig");
pub const Compose = flags.Compose;
pub const Leaf = flags.Leaf;
pub const Own = flags.Own;
pub const Alias = flags.Alias;
pub const system = @import("system.zig");
pub const Array = std.ArrayList;

test {
    std.testing.refAllDecls(@This());
}

inline fn processWrapper(
    comptime Sys: type,
    comptime T: type,
    arg: *T,
    regInfo: anytype,
) !void {

    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a struct!"),
    };

    inline for (info.fields) |field| {
        switch (@typeInfo(field.type)) {
            .@"struct" => {
                switch (flags.fieldFlag(field.type)) {
                    .owned => {
                        comptime if (@typeInfo(field.type) != .@"struct") continue;

                        try processWrapper(
                            Sys,
                            field.type,
                            &@field(arg, field.name),
                            regInfo,
                        );
                    },
                    .leaf, .dissolve => continue,
                    else => unreachable,
                }
            },
            else => continue,
        }
    }

    if (!@field(Sys, system.fields.signature.name).qualifies(T)) return;

    const Eroded = flags.Erode(T);
    comptime {
        std.debug.assert(util.layoutEql(T, Eroded));
    }

    const Named = @field(Sys, system.fields.signature.name).NamedType(Eroded);
    try @field(Sys, system.fields.function.name)(Named, @as(*Named, @ptrCast(@alignCast(arg))), regInfo);
}

/// `types` should be all the types the registry will utilize,
/// `types` *will not* be infered by systems.
pub fn Registry(comptime types: []const type, comptime requestedSystems: []const type, comptime ExtraInfo: ?type) type {
    // we do a lot of comptime recursion (which is an issue to optimize)
    // so we just set it to an 'arbitrary' big number
    comptime {
        // create structure of arrays
        var valueTypes: [types.len]type = undefined;
        var retyped: [types.len]type = undefined;
        var dropItem: [types.len]type = undefined;
        for (types, 0..) |T, i| {
            retyped[i] = flags.Path(flags.Flatten(T));
            valueTypes[i] = Array(retyped[i]);
            dropItem[i] = Array(*retyped[i]);
        }

        for (requestedSystems) |System|
            std.debug.assert(system.qualifies(System));

        const DataType = @Tuple(&valueTypes);
        const AppendType = DataType;
        const DropType = @Tuple(&dropItem);

        return struct {
            /// the raw data of all the types, a tuple of @This().array
            /// recommended to not access manually
            data: DataType,
            info: RegistryInformation,
            appendQueue: AppendType,
            dropQueue: DropType,

            pub fn init(io: std.Io, gpa: std.mem.Allocator, extra: if (ExtraInfo) |_| ExtraInfo else void) @This() {
                var data: DataType = undefined;
                var dropVal: DropType = undefined;
                var appendVal: AppendType = undefined;
                inline for (arrayTypes, 0..) |T, i| {
                    data[i] = T.empty;
                    dropVal[i] = .empty;
                    appendVal[i] = .empty;
                }

                if (@import("builtin").mode == .Debug)
                    inline for (types) |T| {
                        std.debug.print("Type '{}' qualifies for system(s): ", .{T});
                        inline for (systems) |Sys| {
                            if (Sys.requirements.qualifies(T)) {
                                std.debug.print("'{}', ", .{Sys});
                            }
                        }
                        std.debug.print("\n", .{});
                    };

                return .{
                    .data = data,
                    .appendQueue = appendVal,
                    .dropQueue = dropVal,
                    .info = .{ .gpa = gpa, .io = io, .delta = 0.0, .extra = extra },
                };
            }

            /// asserts `value` is a top-level field, and a pointer
            inline fn itemDeinit(self: *RegistryT, value: anytype) void {
                const T: type = @TypeOf(value);
                const info = switch (@typeInfo(T)) {
                    .pointer => |i| i,
                    else => @compileError("Error: Type '" ++ @typeName(value) ++ "' is not a pointer!"),
                };
                const DeinitType: type = fn (comptime T: type, value: anytype, info: anytype) void;
                const i: comptime_int = comptime for (RegistryT.allTypes, 0..) |U, i| {
                    if (U == info.child) break i;
                } else @compileError("Error: Type '" ++ @typeName(T) ++ "' is not in the registry!");
                if(comptime @hasDecl(originalTypes[i], "deinit")) {
                    if (comptime (@TypeOf(@field(originalTypes[i], "deinit")) == DeinitType))
                        originalTypes[i].deinit(info.child, value, self.info);
                } else return;
            }

            pub fn deinit(self: *RegistryT) void {
                inline for (0..types.len) |i| {
                    for (self.data[i].items) |*value|
                        self.itemDeinit(value);
                    self.data[i].deinit(self.info.gpa);
                }
            }

            /// Processes all items, and drops and appends after.
            pub fn process(self: *@This(), delta: f32) !void {
                self.info.delta = delta;
                inline for (allTypes) |T| {
                    const arr = self.getArrayFromType(T);
                    inline for (systems) |Sys|
                        for (arr.items) |*value|
                            try processWrapper(
                                Sys,
                                T,
                                value,
                                &self.info,
                            );
                }
                self.drop();
                try self.append();
            }

            fn getArrayFromType(self: *@This(), comptime T: type) *Array(T) {
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J)
                        break i;
                } else @compileError("Error, type '" ++ @typeName(T) ++ "' is not in the Registry!");
                return &self.data[i];
            }

            /// Given the registry and a value of a type in the registry, adds the value
            /// Returns a pointer to the type new value
            ///
            ///> **NOTE**:
            ///> - Pointer is owned by `self`
            ///> - Pointer may be invalidated between calls of `process`
            ///
            ///> **WARNING**:
            ///> - Returned pointer is not guaranteed to be the same type as `value`
            ///> - May cause runtime overhead if `@TypeOf(value) != flags.Flatten(@TypeOf(value))`
            pub fn addValue(self: *@This(), value: anytype) std.mem.Allocator.Error!void {
                const TPrime = @TypeOf(value);
                inline for (allTypes, 0..) |U, i|
                    // already processed
                    if (TPrime == U)
                        return self.data[i].append(self.info.gpa, value);

                const T = flags.Path(flags.Flatten(TPrime));
                const i = comptime for (allTypes, 0..) |J, i| {
                    if (T == J) break i;
                } else @compileError("Error, type \"" ++ @typeName(T) ++ "\" is not in the Registry!");

                const flattened = flags.flatten(value);

                try self.data[i].append(self.info.gpa, flags.path(&flattened).*);
            }

            /// information provided to every system as the final argument.
            pub const RegistryInformation = struct {
                gpa: std.mem.Allocator,
                io: std.Io,
                delta: f32,
                extra: (ExtraInfo orelse void),

                pub fn appendDeferred(self: *RegistryInformation, value: anytype) std.mem.Allocator.Error!void {
                    const registry: *RegistryT = @fieldParentPtr("info", self);

                    const TPrime = flags.Path(flags.Flatten(@TypeOf(value)));
                    const flattened = flags.flatten(value);
                    inline for (@typeInfo(AppendType).@"struct".fields) |field| {
                        if (Array(TPrime) == field.type) {
                            break try @field(registry.appendQueue, field.name).append(self.gpa, flags.path(&flattened).*);
                        }
                    } else @compileError("Error: Type '" ++ @typeName(@TypeOf(value)) ++ "' is not in the registry!");
                }

                /// Given the registry information and a pointer to a type in the registry, queues it to removal.
                /// If `value` is not owned by registry, undefined behavior.
                pub fn dropDeferred(self: *RegistryInformation, value: anytype) std.mem.Allocator.Error!void {
                    const info = switch (@typeInfo(@TypeOf(value))) {
                        .pointer => |p| p,
                        else => @compileError("Error: type '" ++ @typeName(value) ++ "' is not a pointer!"),
                    };
                    const T = flags.OriginalType(info.child);
                    const registry: *RegistryT = @fieldParentPtr("info", self);
                    const i = comptime blk: {
                        const path = flags.getPath(info.child);
                        if (path.len > 0) {
                            var split = std.mem.splitScalar(u8, path, flags.pathing.pathDelimiter);
                            const uName = split.first();
                            for (RegistryT.allTypes, 0..) |U, i| {
                                if (util.strEql(@typeName(U), uName))
                                    break :blk i
                                else
                                    @compileLog(@typeName(U) ++ " != " ++ uName);
                            } else @compileError("Error: type '" ++ @typeName(@TypeOf(value)) ++ "' is not anywhere in the registry");
                        } else {
                            for (RegistryT.allTypes, 0..) |U, i| {
                                if (flags.OriginalType(U) == T)
                                    break :blk i;
                            } else @compileError("Error: type '" ++ @typeName(@TypeOf(value)) ++ "' is not anywhere in the registry");
                        }
                    };
                    try registry.dropQueue[i].append(self.gpa, @ptrCast(value));
                }
            };

            /// Loops through the dropQueue and removes the items in the registry with a double pass
            /// invalidates pointers
            fn drop(self: *RegistryT) void {
                const dropInfo = @typeInfo(DropType).@"struct";
                inline for (dropInfo.fields) |field| {
                    for (@field(self.dropQueue, field.name).items) |i|
                        self.itemDeinit(i);
                    for (@field(self.dropQueue, field.name).items) |i| {
                        const originPtr = @field(self.data, field.name).items;
                        const index: i65 = @as(i65, @intFromPtr(i)) - @as(i65, @intFromPtr(originPtr.ptr));
                        if (comptime (@import("builtin").mode == .Debug))
                            if (index < 0 or index > originPtr.len)
                                std.debug.panic(
                                    "Error: {} pointer has index of {d} in an array of length {d}! Please check ownership!",
                                    .{
                                        @TypeOf(i),
                                        index,
                                        originPtr.len,
                                    },
                                );
                        _ = @field(self.data, field.name).swapRemove(@as(usize, @intCast(index)));
                    }
                    @field(self.dropQueue, field.name).clearRetainingCapacity();
                }
            }

            /// Loops through the append queue and adds all items to their respective arrays
            fn append(self: *RegistryT) !void {
                inline for (&self.appendQueue) |*list| {
                    for (list.items) |item|
                        try self.addValue(item);
                    list.clearRetainingCapacity();
                }
            }

            const RegistryT = @This();
            pub const systems: []const type = requestedSystems;
            pub const arrayTypes = valueTypes;
            pub const allTypes = retyped;
            pub const originalTypes: []const type = types;
        };
    }
}
