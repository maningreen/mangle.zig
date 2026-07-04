//* This file manages the comptime components of the game engine
//* see `runtime` for runtime effects

const std = @import("std");
const meta = std.meta;
const util = @import("util.zig");
const StructField = std.builtin.Type.StructField;
const StructAttrs = std.builtin.Type.StructField.Attributes;

pub const System = struct {
    Types: Signature,
    /// it's ensured `anytype` will be a tuple of slices ordered by `Types`
    process: fn (anytype, RegistryInformation) ProcessError!void,
};

pub const RegistryInformation = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
};

/// Returns a struct, with an array of the necessary data for the type
pub fn Archetype(sig: Signature) type {
    return struct {
        const Self = @This();

        pub const Signature = sig;
        pub const DataType = sig.GetType();

        /// an array list of all the data,
        /// - data is optional, if it's missing at the top level
        ///   then it's assumed it's uninitialized.
        /// - data is differentiated by the type, and nothing else
        ///   if the data has multiple items of the same type,
        ///   it's recommended making type aliases instead
        /// example of recommendation
        /// ```
        /// DataType = .{ i32, i32 }
        /// ```
        /// Do
        /// ```
        /// DataType = .{ Health, Damage }
        /// ```
        data: std.ArrayList(?DataType),

        pub inline fn qualifies(_: Self, item: anytype) bool {
            return comptime sig.qualifies(item);
        }

        /// returns a pointer to the newly allocated *unset* data
        /// Tuple form.
        pub fn allocItem(self: *Self, gpa: std.mem.Allocator) !*DataType {
            return self.data.addOne(gpa);
        }

        /// appends an item to the list
        pub fn appendItem(self: *Self, gpa: std.mem.Allocator, item: DataType) !void {
            try self.data.append(gpa, item);
        }

        /// no deallocation.
        pub fn swapPop(self: *Self, index: usize) void {
            self.data.swapRemove(index);
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.data.deinit(gpa);
        }
    };
}

pub const Signature = struct {
    items: []const type,

    /// returns a tuple
    /// order is dependent on the items
    pub inline fn GetType(self: Signature) type {
        comptime return @Tuple(self.items);
    }

    /// returns whether or not a structure (if not structure returns whether or not is contained)
    /// qualifies for the signature
    pub fn qualifies(comptime self: Signature, item: anytype) bool {
        comptime {
            const T = @TypeOf(item);
            if (@typeInfo(T) == .@"struct")
                for (@typeInfo(T).@"struct".fields) |j| {
                    if (!std.mem.containsAtLeastScalar2(type, self.items, j.type, 1))
                        return false;
                } else return true;

            if (!std.mem.containsAtLeastScalar2(type, self.items, T, 1))
                return false;
        }
    }
};

/// `types` should be all the types the engine will attach,
/// `types` are also infered from the `systems`
pub fn Registry(comptime types: []const type, comptime systems: []const System) type {
    comptime {
        // step one: infer types from systems
        const allSystemTypes = getSystemTypes(systems);

        // step two: concat all of them into one list
        const allTypes = comptimeConcatNoRepeats(type, types, allSystemTypes);
        _ = allTypes;

        return struct {};
    }
}

inline fn getSystemTypes(comptime systems: []const System) []const type {
    comptime {
        if (systems.len == 0) {
            return &.{};
        } else {
            return systems[0].Types.items ++ getSystemTypes(systems[1..]);
        }
    }
}

/// Super innefficient.
/// TODO: fix that
fn comptimeConcatNoRepeats(comptime T: type, comptime a: []const T, comptime b: []const T) []T {
    comptime {
        var array: []T = &.{};
        outer: for (a ++ b) |item| {
            for (array) |i| {
                if (item == i)
                    // item already appears
                    continue :outer
                else {
                    array = array ++ &.{item};
                }
            }
        }
        return array;
    }
}

pub const Entity = struct {
    /// the current archetype for which this entity qualifies
    record: *anyopaque,

    /// the signature of the archetype
    sig: Signature,

    /// the name of the entity
    name: []const u8,

    /// the index in the archetype which the data lies
    index: usize,
};

pub const ProcessError = error{ProcessError} || std.mem.Allocator.Error;
