//! The mangle library is a processing engine structured around metadata tags, structure recomposition, comptime processing, and field matching.
//!
//! It contains the following namespaces, divided conceptually:
//!     - [flags](#mangle.flags), behavior & relationship flags, brought up a namespace for ergonomic's sake
//!     - [util](#mangle.util), underlying utilities
//!     - [system](#mangle.system) systems and qualifications
//!
//! It's hosted [here](https://github.com/maningreen/mangle.zig), with documentation [here](https://maningreen.github.io/mangle.zig)

const std = @import("std");
const meta = std.meta;
pub const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.lang.Type.Struct.FieldAttributes;
pub const flags = @import("flags.zig");
pub const Compose = flags.Compose;
pub const Leaf = flags.Leaf;
pub const Own = flags.Own;
pub const Alias = flags.Alias;
pub const alias = flags.alias;
pub const system = @import("system.zig");
pub const Array = std.ArrayList;

test {
    std.testing.refAllDecls(@This());
}

fn applySystem(
    comptime Sys: type,
    comptime T: type,
    comptime function: @EnumLiteral(),
    comptime inlined: bool,
    value: *T,
    extraArgs: anytype,
) !void {
    const info = switch (@typeInfo(T)) {
        .@"struct" => |i| i,
        else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a struct!"),
    };

    inline for (info.field_names, info.field_types) |name, U| {
        switch (@typeInfo(U)) {
            .@"struct" => {
                switch (comptime flags.fieldFlag(U)) {
                    .owned => {
                        switch (@typeInfo(U)) {
                            .@"struct" => {
                                try applySystem(
                                    Sys,
                                    U,
                                    function,
                                    inlined,
                                    &@field(value, name),
                                    extraArgs,
                                );
                            },
                            else => {},
                        }
                    },
                    .leaf, .dissolve => continue,
                    else => unreachable,
                }
            },
            else => continue,
        }
    }

    if (comptime !@field(Sys, system.fields.signature.name).qualifies(T)) return;

    const Named = @field(Sys, system.fields.signature.name).NamedType(T);
    comptime {
        if (!util.layoutEql(T, Named))
            @compileError(
                \\This is asserted, and if fails, report on github. Also include the type definition for '
            ++ @typeName(flags.OriginalType(T)) ++
                \\' and substructures." You may also want to include the definition for the system '
            ++ @typeName(Sys) ++
                \\'
            );
    }
    return @call(
        if (inlined) .always_inline else .auto,
        @field(Sys, @tagName(function)),
        .{ Named, @as(*Named, @ptrCast(value)) } ++ extraArgs,
    );
}

fn TypeTransform(comptime T: type) type {
    return flags.Flatten(flags.Path(T));
}

fn transform(value: anytype) TypeTransform(@TypeOf(value)) {
    return flags.flatten(flags.path(&value).*);
}

/// `types` should be all the types the registry will utilize at the top level,
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
            if (@typeInfo(T) != .@"struct")
                @compileError("Error: type '" ++ @typeName(T) ++ "' is not a structure!");
            retyped[i] = TypeTransform(T);
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
            /// The information provided to every system
            info: RegistryInformation,
            /// The items to append
            appendQueue: AppendType,
            /// The items to drop
            dropQueue: DropType,

            pub fn init(io: std.Io, gpa: std.mem.Allocator, extra: if (ExtraInfo) |T| T else void) @This() {
                var data: DataType = undefined;
                var dropVal: DropType = undefined;
                var appendVal: AppendType = undefined;
                inline for (arrayTypes, 0..) |T, i| {
                    data[i] = T.empty;
                    dropVal[i] = .empty;
                    appendVal[i] = .empty;
                }

                if (@import("builtin").mode == .debug)
                    logQualify();

                return .{
                    .data = data,
                    .appendQueue = appendVal,
                    .dropQueue = dropVal,
                    .info = .{
                        .gpa = gpa,
                        .io = io,
                        .delta = 0.0,
                        .extra = extra,
                    },
                };
            }

            /// asserts `value` is a top-level field, and a pointer
            fn itemDeinit(self: *RegistryT, value: anytype) void {
                const T: type = @TypeOf(value);
                const info = switch (@typeInfo(T)) {
                    .pointer => |i| i,
                    else => @compileError("Error: Type '" ++ @typeName(T) ++ "' is not a pointer!"),
                };
                const DeinitType: type = fn (comptime T: type, value: anytype, info: anytype) void;
                const i: comptime_int = comptime for (RegistryT.allTypes, 0..) |U, i| {
                    if (U == info.child) break i;
                } else @compileError("Error: Type '" ++ @typeName(T) ++ "' is not in the registry!");
                if (comptime @hasDecl(originalTypes[i], "deinit")) {
                    if (comptime (@TypeOf(@field(originalTypes[i], "deinit")) == DeinitType))
                        originalTypes[i].deinit(info.child, value, self.info);
                } else return;
            }

            pub fn deinit(self: *RegistryT) void {
                inline for (0..types.len) |i| {
                    for (self.data[i].items) |*value|
                        self.itemDeinit(value);
                    self.data[i].deinit(self.info.gpa);
                    self.appendQueue[i].deinit(self.info.gpa);
                    self.dropQueue[i].deinit(self.info.gpa);
                }
            }

            /// Processes all items, and drops and appends after.
            pub fn process(self: *@This(), delta: f32) !void {
                self.info.delta = delta;
                inline for (allTypes) |T| {
                    const arr = self.getArrayFromType(T);
                    inline for (systems) |Sys|
                        if (comptime system.hasProcess(Sys))
                            for (arr.items) |*value|
                                try applySystem(
                                    Sys,
                                    T,
                                    .process,
                                    false,
                                    value,
                                    .{&self.info},
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
            /// If the inputted value is a union, will do a switch, adding the active field into it.
            /// Asserts every field of the union is either a top-level value, or `void`, in which case it's ignored
            ///
            /// Works for `?T`, as well, ignoring if `value == null`
            ///
            ///> **NOTE**:
            ///> - Pointer is owned by `self`
            ///> - Pointer may be invalidated between calls of `process`
            ///
            ///> **WARNING**:
            ///> - Returned pointer is not guaranteed to be the same type as `value`
            ///> - May cause runtime overhead if `@TypeOf(value) != flags.Flatten(@TypeOf(value))`
            pub fn addValue(self: *@This(), value: anytype) std.mem.Allocator.Error!void {
                switch (comptime @typeInfo(@TypeOf(value))) {
                    .@"struct" => {
                        const TPrime = @TypeOf(value);
                        inline for (allTypes, 0..) |U, i|
                            // already processed
                            if (TPrime == U)
                                return self.data[i].append(self.info.gpa, value);

                        const T = TypeTransform(TPrime);
                        const i = comptime for (allTypes, 0..) |J, i| {
                            if (T == J) break i;
                        } else @compileError("Error, type \"" ++ @typeName(@TypeOf(value)) ++ "\" is not in the Registry!");

                        const flattened = flags.flatten(flags.path(&value).*);

                        try self.data[i].append(self.info.gpa, flattened);
                    },
                    .@"union" => try switch (value) {
                        inline else => |unwrapped| self.addValue(unwrapped),
                    },
                    .optional => if (value) |v| {
                        self.addValue(v);
                    },
                    else => @compileError("Error, type \"" ++ @typeName(@TypeOf(value)) ++ " is not an optional, union, or struct!"),
                }
            }

            /// adds a top-level value to the registry after `process` is called
            ///
            ///> **NOTE**:
            ///>    - see also [appendDeferred](#mangle.Registry.RegistryInformation.appendDeferred)
            ///>    - see also [addValue](#mangle.Registry.addValue)
            pub fn appendDeferred(self: *RegistryT, value: anytype) std.mem.Allocator.Error!void {
                switch (@typeInfo(@TypeOf(value))) {
                    .@"union" => try switch (value) {
                        inline else => |unwrapped| self.addValue(unwrapped),
                    },
                    .optional => try if (value) |v| self.appendDeferred(v),
                    else => {},
                }
                const TPrime = TypeTransform(@TypeOf(value));
                inline for (@typeInfo(AppendType).@"struct".field_names, @typeInfo(AppendType).@"struct".field_types) |name, U| {
                    if (Array(TPrime) == U)
                        break try @field(self.appendQueue, name)
                            .append(self.info.gpa, transform(value));
                } else @compileError("Error: Type '" ++ @typeName(@TypeOf(value)) ++ "' is not in the registry!");
            }

            /// Removes a value in the registry. dropping is propagated upwards if value isn't top-level.
            ///
            ///> **NOTE**:
            ///>    - see also [appendDeferred](#mangle.Registry.RegistryInformation.dropDeferred)
            ///>    - `value` **must** be a pointer to a value
            pub fn dropDeferred(self: *RegistryT, value: anytype) std.mem.Allocator!void {
                const info = switch (@typeInfo(@TypeOf(value))) {
                    .pointer => |p| p,
                    else => @compileError("Error: type '" ++ @typeName(value) ++ "' is not a pointer!"),
                };
                const T = flags.OriginalType(info.child);
                const i = comptime blk: {
                    const path = flags.getPath(info.child);
                    if (path.len > 0) {
                        var split = std.mem.splitScalar(u8, path, flags.pathing.pathDelimiter);
                        const uName = split.first();
                        for (RegistryT.allTypes, 0..) |U, i| {
                            if (util.strEql(@typeName(U), uName))
                                break :blk i;
                        } else @compileError("Error: type '" ++ @typeName(T) ++ "' is not anywhere in the registry");
                    } else {
                        for (RegistryT.allTypes, 0..) |U, i| {
                            if (flags.OriginalType(U) == T)
                                break :blk i;
                        } else @compileError("Error: type '" ++ @typeName(T) ++ "' is not anywhere in the registry");
                    }
                };
                try self.dropQueue[i].append(self.gpa, @ptrCast(value));
            }

            /// information provided to every system as the final argument.
            pub const RegistryInformation = struct {
                gpa: std.mem.Allocator,
                io: std.Io,
                delta: f32,
                extra: (ExtraInfo orelse void),

                /// Adds top-level item to the registry after `process` is called.
                /// Intended for calling from systems
                ///
                ///> **NOTE**:
                ///>    - see also [appendDeferred](#mangle.Registry.appendDeferred)
                ///>    - see also [addValue](#mangle.Registry.addValue)
                pub fn appendDeferred(self: *RegistryInformation, value: anytype) std.mem.Allocator.Error!void {
                    const registry: *RegistryT = @fieldParentPtr("info", self);
                    return registry.appendDeferred(value);
                }

                /// Given the registry information and a pointer to a type in the registry, queues it to removal.
                /// If `value` is not owned by registry, undefined behavior.
                pub fn dropDeferred(self: *RegistryInformation, value: anytype) std.mem.Allocator.Error!void {
                    const registry: *RegistryT = @fieldParentPtr("info", self);
                    return registry.dropDeferred(value);
                }

                /// Emits an event to every system.
                ///
                /// **NOTE**:
                ///     - Is an interrupt, other events are processed on call
                ///     - See also, [emit](#mangle.Registry.emit)
                pub fn emit(self: *RegistryInformation, eventData: anytype) !void {
                    return @as(*RegistryT, @fieldParentPtr("info", self)).emit(eventData);
                }
            };

            /// Loops through the dropQueue and removes the items in the registry with a double pass
            /// invalidates pointers
            fn drop(self: *RegistryT) void {
                const dropInfo = @typeInfo(DropType).@"struct";
                inline for (dropInfo.field_names) |name| {
                    for (@field(self.dropQueue, name).items) |i|
                        self.itemDeinit(i);
                    for (@field(self.dropQueue, name).items) |i| {
                        const originPtr = @field(self.data, name).items;
                        const index: i65 = @as(i65, @intFromPtr(i)) - @as(i65, @intFromPtr(originPtr.ptr));
                        if (comptime (@import("builtin").mode == .debug))
                            if (index < 0 or index > originPtr.len)
                                std.debug.panic(
                                    "Error: {} pointer has index of {d} in an array of length {d}! Please check ownership!",
                                    .{
                                        @TypeOf(i),
                                        index,
                                        originPtr.len,
                                    },
                                );
                        _ = @field(self.data, name).swapRemove(@as(usize, @intCast(index)));
                    }
                    @field(self.dropQueue, name).clearAndFree(self.info.gpa);
                }
            }

            /// Loops through the append queue and adds all items to their respective arrays
            fn append(self: *RegistryT) !void {
                inline for (&self.appendQueue) |*list| {
                    for (list.items) |item|
                        try self.addValue(item);
                    list.clearAndFree(self.info.gpa);
                }
            }

            // / Internal function. Loops through all systems and calls `receive` if available
            /// Emits an event to every system.
            ///
            /// **NOTE**:
            ///     - Is an interrupt, if called in `process`, the event will happen
            ///     - See also, [emit](#mangle.Registry.RegistryInformation.emit)
            pub fn emit(self: *RegistryT, event: anytype) !void {
                inline for (allTypes) |T| {
                    const arr = self.getArrayFromType(T);
                    inline for (systems) |Sys|
                        if (comptime system.hasReceive(Sys))
                            for (arr.items) |*value|
                                try applySystem(
                                    Sys,
                                    T,
                                    .receive,
                                    false,
                                    value,
                                    .{ event, &self.info },
                                );
                }
            }

            const RegistryT = @This();
            /// All the systems that were requested. Includes unused systems.
            pub const systems: []const type = requestedSystems;
            /// The internal arrays used.
            pub const arrayTypes = valueTypes;
            /// The internal types used.
            pub const allTypes = retyped;
            /// The original types inputted to the system.
            pub const originalTypes: []const type = types;

            /// Prints the systems top-level types qualify for.
            ///
            /// Runs automatically on `@import("builtin").mode == .Debug`, doesn't otherwise
            pub fn logQualify() void {
                inline for (types) |T| {
                    std.debug.print("Type '{}' qualifies for system(s): ", .{T});
                    inline for (systems) |Sys| {
                        if (Sys.requirements.qualifies(T)) {
                            std.debug.print("'{}', ", .{Sys});
                        }
                    }
                    std.debug.print("\n", .{});
                }
            }
        };
    }
}
