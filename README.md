# mangle.zig

mangle.zig is a processing engine structured around metadata tags, structure recomposition, comptime processing, and field matching.

## Getting started

To use mangle.zig set up your zig project, and fetch it with the following command
```
$ zig fetch --save git+https://github.com/maningreen/mangle.zig
```
This should fetch it, then add the following to your `build.zig` and import `mangle_lib` in your executable

```zig
const mangle_dependency = b.dependency("mangle", .{ });
const mangle_artifact = mangle_dependency.artifact("mangle");
my_exe.root_module.linkLibrary(mangle_artifact);
```

After this, you should be able to do `@import("mangle")`

## Overall structure

Terminology:
    - [Registry](#registry)
        - The top-most structure containing all data
        - Orchestrates data and behavior
    - [System](#systems)
        - A structure which defines behavior
        - [Qualification](#type-system-qualification)
    - [Type](#types)
        - Any type in the [Registry](#registry), fundamental data
        - Top-level types are types stored densely.

The main type for the runtime is the `Registry()`, which contains all **top-level** types, and all systems.
The `Registry()` can be used as a medium for [signals](#signals) and [processing](#processing).

### Registry

The registry is generic and the top-most structure containing all data.<br>

#### Instantiation

The `Registry` has two main instantiation functions, the type function and `init`.

`Registry()` is used as follows and has a signature of
    `Registry(comptime types: []const type, comptime systems: []const type, comptime ExtraData: ?type)`
```zig
const Registry = mangle.Registry(my_types, my_systems, ExtraData);
const registry: Registry = Registry.init(gpa, io, .{});
defer registry.deinit();
```
The registry has a substructure called [RegistryInformation](#registryinformation), with fields like `gpa`, `io`, and `extra`, the final of which is of type `ExtraData orelse void`
The instance of [RegistryInformation](#registryinformation) is supplied to every [processing function](#processing) as the final argument.

The registry is where all behavior and data is contained. Behavior, in [systems](#systems), and data in [types](#types)

Any type in `my_types` is considered a **top-level** type, as it's the top-most available value.

#### Usage

In order to use the registry, there's one main function to use: `process`.
Process calls every [system](#systems) [process](#processing). Usage is as follows.

```zig
const delta: f32 = 1;
try registry.process(delta)
```
Delta is intended to be the timestep between calls, but if unused supplying `0` or `1` is okay.

Appending values as initialization is easy with `addValue(self: *Registry, value: anytype) !void`.
```zig
try registry.addValue(my_type);
```
It's asserted `my_type` is a **top-level** type, if not, a compile error is thrown.

#### RegistryInformation

RegistryInformation is the substructure in registry, which is supplied to every [process function](#processing), and has several functions, two main ones.
    - `appendDeferred(self: *RegistryInformation, value: anytype)`
    - `dropDeferred(self: *RegistryInformation, value: anytype)`

Usage of appendDeferred is identical to that of `addValue`; however, it doesn't add the value immediately, but waits until all [system processing](#processing) is done.

Usage of `dropDeferred` is slightly more complex. Given a pointer to any structure *in* the registry (top-level or not), dropping is propagated upwards until a top-level is reached.
Dropping is appended to a queue, until [system processing](#processing) is completed, then items are removed and queues are freed.

## Types

A type is used to define behavior. Flags describe structure and substructure relationships.

> [!TODO]
> - [ ] come up with a better term than 'type'

### Definition

A top-level is a type supplied as the *first* argument to a [`Registry`](#registry).

> [!WARNING]
> A top-level type *must* be a structure, if not, a compile error will be thrown.


Ownership is default behavior.

## Systems

A system is used to define behavior for types.
The namespace for systems is `mangle.system`, for declarations see the [online docs](#docs)

Terminology:
    - [Processing](#processing)
        - [Events](#events)
    - [Signature](#signatures)
        - [Qualification](#type-system-qualification)

### Definition

For a system to qualify as a system it must have the following declarations:
    - requirements: [Signature](#signature)
        - Signatures are how a system creates type specifications
    - process: `fn (comptime T: type, value: *T, registry_information: anytype)`
        - called on `Registry().process`
    - receive: `fn (comptime T: type, value: *T, event: anytype, registry_information: anytype)`
        - called on `Registry().emit`

Having at least one of `process` and `receive` is required, having both is optional.

### Processing

Processing is how behavior is defined, it's simply a function, here's an example

```zig
pub fn process(comptime T: type, value: *T, registry_information: anytype) !void {
    // print all fields
    inline for (@typeInfo(T).@"struct".fields) |field|
        std.debug.print("{any}", .{ @field(value.*, field )});
}
```

#### Events

An event is an interrupt applied to every system.
There is no runtime representation for an event beyond the data provided in the event.

Calling an event is as follows on either a RegistryInformation, or a Registry
    - `emit(data: anytype) !void`
Calling in a process is like this

```zig
const Event = struct {
    value: u32,
};

pub fn process(comptime T: type, value: *T, registry_information: anytype) !void {
    try registry_information.emit(Event{ .value = 42 });
}
```

In order to receive an event is as follows.

```zig
pub fn receive(comptime T: type, value: *T, event: anytype, registry_information: anytype) !void {
    switch(@TypeOf(event)) {
        Event => try manageEvent(T, value, registry_information) 
        else => {},
    }
}
```

`receive` is called inline, so it's recommended to have a switch on the type to another function.

The *only* thing to differentiate an event is with the **type** of the event.

### Signatures

In a traditional ECS engine, systems apply based off of 'Archetypes', in mangle, systems apply based off of Signatures

A system signature could be defined as follows
```zig
pub const requirements: mangle.system.Signature = .{
    .fields = &.{
        .{ .name = "message", .type = []const u8 },
    },
};
```

> [!NOTE]
> Signature API might alter in order to allow more advanced conditions and configurations

#### Type System Qualification

A [Signature](#signatures) defines the fields a type, and what's fed into its [process](#processing).

Given the following signature, and some types, here's a list of what would / would not qualify.<br>
Multiple items in `fields` means multiple unique fields.
```zig
pub const requirements: mangle.system.Signature = .{
    .fields = &.{
        .{ .name = "message", .type = []const u8 },
    },
};

const T = struct {
    message: []const u8,
};

const U = struct {
    string: []const u8,
};

const V = struct {
    subfield: U,
    other_data: u32,
};

const W = struct {
    id: u32,
    string: []const u8,
};

const Foo = struct  {
    number: u32,
}
```
The following types *and fields* qualify:
    - `T`
    - `U`
    - `V.subfield`
        - `V.subfield` will be processed independently
        - The process under which a substructure qualifies can be altered with [Flags](#flags)
    - `W`

`Foo` does *not* qualify because it doesn't contain a specified `[]const u32`

> [!NOTE]
> Multiple fields of the same type will create undefined behavior (to be a compile error)

## Flags

> [!NOTE]
> It's recommended to read about [systems](#systems) before flags

Flags are used to describe relationships between struct parent and struct child. Without them, the following excerpt is ambiguous as `T` a top-level type.
```zig
const T = struct {
    subfield: U
};

const U = struct {
    field: u32,
};
```
The following relationships could all be possible:
    - `subfield` should be [processed](#processing) independently by recursion
    - `subfield` should be composed into `T` and treated as an extension of the type
    - `subfield` should be considered opaque and treated fundamentally
    - `subfield` should be treated like a `u32` alias?
If there're any more relationships I missed, please make an [issue](https://github.com/maningreen/mangle.zig/issues)

There's a **flag** for each of these cases, respectively:
    - [Own(T)](#ownt)
    - [Compose(T)](#composet)
    - [Leaf(T)](#leaft)
    - [Alias(T)](#aliast)

### Own(T)

Ownership is the default behavior for substructures.
Ownership can explicitly be stated with `Own(T)`.
`Own(T)` is identity, and only should be used for clarity.

```zig
const T = struct {
    // Own(U) is optional for ownership behavior, in this case ownership is implicit
    subfield: U,
};

const U = struct {
    id: u32,
};
```

If a system signature specifies `u32`, `T` will not be matched, but `T.subfield` will be recursed into by the system.
A system can recurse an unlimited amount of times.

### Compose(T)

Composition with `Compose(T)` embeds a metadata flag into `T`.
When entered into the registry, any composed substructures will have their subfields brought up a level.
This effects how a system qualifies it.

```zig
const T = struct {
    subfield: Compose(U),
};

const U = struct {
    id: u32,
};
```
This creates (effectively) the following structure when an instance of `T` is inputted into the registry.
```zig
const RegistryT = struct {
    id: u32,
};
```
A system requiring `u32` will match with `T` (unlike ownership).
A system requiring `U` will not match with `T` because the `U` substructure is removed.

> [!Note]
> Creating an instance of `T` cannot explicitly initialize `subfield` as `U`, because `Compose(U) != U`

### Leaf(T)

The term 'leaf' comes from a tree graph of structures.
A leafed field will *not* be recursed into, but can be matched with.

```zig
const T = struct {
    subfield: Leaf(U),
};

const U = struct {
    id: u32,
};
```
A system requiring `u32` will not match with `T.subfield` (unlike ownership).
A system with `U` **will** match with `T.subfield` (like ownership)

> [!Note]
> Creating an instance of `T` cannot explicitly initialize `subfield` as `U`, because `Leaf(U) != U`

### Alias(T)

Alias itself isn't a flag, but uses `Dissolve(T)` internally.
`Dissolve(T)`'s not very useful beyond `Alias(T)` (at least as far as I can tell), but is still exposed.

The reason for `Alias(T)` is because of the following:
```zig
const Position = u32; 
comptime {
    std.debug.assert(Position == u32); // true
}
```

This means that systems cannot differentiate between `Position` and `u32`.
Thus, comes `Alias(T)`, an ergonomic alternative.

Usage is as follows
```zig
const Position = Alias(u32, "position");
const Velocity = Alias(u32, "velocity");

comptime {
    std.debug.assert(Position != u32);
    std.debug.assert(Velocity != u32);
    std.debug.assert(Position != Velocity);
}

const Object = struct {
    position: Position,
    velocity: Velocity,
};

const object_instance = Object{      // Alias is for when the name isn't exposed directly
    .position = alias(Position, 30), // both are valid ways to instantiate an alias
    .velocity = .{ .velocity = 30 }, // the field name is the string inputted
};                                   // overall, using `alias` is recommended
```

A system might set its Signature to require a `Position`, and it won't match for a `u32`, and vice versa.
However, when provided to the system, the types are *unwrapped* and allow direct access as following

```zig
const ApplyVelocity = struct {
    pub const requirements: mangle.system.Signature = .{
        .fields = &.{
            .{ .name = "position", .type = Position },
            .{ .name = "velocity", .type = Velocity },
        },
    };

    pub fn process(comptime T: type, value: *T, _: anytype) {
        comptime {
            std.debug.assert(@FieldType(T, "position") == u32);
            std.debug.assert(@FieldType(T, "velocity") == u32);
        }
        value.position += value.velocity;
    }
};
```

## Docs

Docs are hosted online [here](https://maningreen.github.io/mangle.zig/)
