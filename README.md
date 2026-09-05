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

## Overall Structure

The overall usage of the mangle library is with systems, types, and the registry.

Create a registry as so
```zig
const Registry = mangle.Registry(&.{ MyType }, &.{ MySystem }, null);
var registry = Registry.init(io, gpa, void{});
defer registry.deinit();
```

Then, in this example you can add a MyType to the registry

```zig
try registry.addValue(myTypeInstance);
```

In order to run the process function in the system, do
```zig
try registry.process(delta);
```
And if you won't be using `delta`, it's fine to provide 0, it's mainly there for graphical applications.

## Creating a registry

`Registry()` takes in three arguments:
    - [types](#creating-a-type)
    - [systems](#creating-a-system)
    - Extra

Extra is a type to add to the `RegistryInfo` substructure in `Registry`.<br>
By default, `RegistryInfo` contains `delta`, `gpa`, and `io`, one can extend this to add any values they want, which are supplied on initialization
It's recommended `Extra` is a structure, for easy expansion and use, even if just `struct {}`<br>
Learn more about Registries [here](#registryt)

## Creating a system

In mangle, a system is a type with two declarations:
    - requirements (`mangle.system.signature`)
    - process (`fn (comptime T: type, T, mangle.RegistryInfo) system.Error!void`)
Any system missing either of these or without the correct type will result in a compile error.

A system.signature defines the 'requirements' a structure in its fields in order to 'qualify' for a systems 'process'.
Example:

```zig
pub const requirements: system.Signature = system.Signature{
    .fields = &.{ 
        .{
            .type = []const u8,
            .name = "string"
        },
    },
};

pub fn process(comptime T: type, item: T, info: system.RegistryInfo) system.Error!void {
    std.debug.print("{s}", .{ item.string });
}
```

`.type` is used in qualification, and `.name` is used to set the field name in `process`.<br>
Note how in `process` we access a field named `string` in item. The name of the field is guaranteed to be `.name`<br>

This is how a system is defined, any other declarations are ignored.<br>

Learn more about [type-system qualification here](#typesystemqualification)

## Creating a type

In mangle, a type is a structure with any amount of fields.<br>
When a type is provided to a system, the identity will be warped, or 'mangled' out of it.<br>
This means all declarations are removed from the type.<br>

Example:
```zig
pub const MyType = struct {
    my_data: []const u8,
};
```

There are also 4 different functions to define the relationship a structure and a sub-structure, affecting how systems qualify it, called [flags](#flags)
    - `Leaf(T)`
    - `Compose(T)`
    - `Own(T)`
    - `Dissolve(T)`
We go more in depth on them in [here](#Flags)
A type 'qualifies' for a system if every type in `requirements` is provided as a field in the type.<br>
If it doesn't match, it won't be processed by the system.

One can also provide a `deinit()` into a type, like the following example

```zig
const std = @import("std");

pub const Type = struct {
    heap_string: []u8,

    pub fn deinit(comptime T: type, value: *T, registry_info: anytype) void {
        std.gpa.free(value.heap_string);
    }
}
```
The reason the typing for `T` is generic is due to the mangling in the types. We cannot assure that the `T` provided to `deinit` is the same `T` `deinit` is declared in.

Note, that [flags](#flags) are applied when `T` is supplied

## Flags

A flag is the term for the following functions:
    - [`Leaf(T)`](#leaft)
    - [`Compose(T)`](#composet)
    - [`Own(T)`](#ownt)
    - [`Dissolve(T)`](#dissolvet)
Each one defines the relationship of a type and sub-structure, altering how a systems qualify them.<br>
Each flag (except [Own](#ownt)) is qualified with a hidden 'flag' field with size 0.

### Own(T)

`Own(T)` is the default behavior, calling it creates no semantic effect, except clarifies useage.

Example:
```zig
const A = struct {
    sub: Own(B), // note, same as `sub: B`
};

const B = struct {
    bField: u32,
}
```
This means an instance of `A` owns an instance of `B`, but `sub` can be processed by a system independently through being supplied to a system.

### Compose(T)

`Compose(T)` is an explicit flag, creating a [flag](#flags) in a sub-structure which is '[flattened](#flatten)' into one effective structure.<br>
Flattening affects the qualification of systems and the struct containing a composed field. By taking sub-structure fields into the local top-level

Example:
```zig
const A = struct {
    sub: Compose(B),
    aField: u32,
};

const B = struct {
    bField: u32
};
```

`Flatten(A)` returns the following struct
```zig
struct {
    bField: u32,
    aField: u32,
}
```
This is how systems see `A`.

### Leaf(T)

`Leaf(T)` is an explicit [flag](#flags). A sub-structure flagged with `Leaf(T)` removes all local processing from the field.<br>
Every non-structure field is a Leaf.

Example:
```zig 
const BType = u32;

const A = struct {
    sub: Leaf(B),
};

const B = struct {
    value: BType,
}

```
This means any system with a requirement `BType` will not be seen `sub`, where `Compose(B)` and `Own(B)` will.<br>
Semantically, a `Leaf(T)` structure is opaque to systems, but can still be matched with. e.g. a system with requirement `B` will match with `Leaf(B)` and can edit the fields of `Leaf(B)`<br>
Importantly, a system matching `B` can edit a `Leaf(B)` directly, but not qualify according to it's fields.

### Dissolve(T)

`Dissolve(T)` mainly serves as a backend for `Alias(T)`.<br>
The main reason this is so is because the following is true:
```zig
const T = u8;
T == u8;
```
Which makes sense, but breaks aliases, as if you have a `Vector2` type aliased to both `Position` and `Velocity`, the signatures have no way of differentiating fields.
Therefore, `Alias(T)` exists.

First, `Dissolve(T)` <br>
`Dissolve(T)` tells the registry 'there is a semantic difference between T and it's field, unwrap on process'<br>
`Disolve(T)` requires `T` to be a struct of *one* field, if the condition is not satisfied, a compile error is emitted.<br>

`Alias(T)` is the practical use case of `Dissolve(T)`, which is to say, for majority of cases `Alias(T)` will suffice. `Alias(T)` also takes in a string, so it's more like `Alias(T, s)`, regardless `s` is important in ensuring `Alias(T)` is unique.<br>
It's recommended, for an alias like `const MyAlias = Alias(u64, "MyAlias")` to set the name as the name of the alias. Do note: `Alias(T, s) == Alias(T, s)` but `Alias(T, alt_str) != Alias(T, str)`
A usage example is provided:
```zig
const Header = Alias([]u8, "Header"); // otherwise the same type
const Body = Alias([]u8, "Body");
const Footer = Alias([]u8, "Footer");

const Message = struct {
    header: Header,
    body: Body,
    footer: Footer,
};

const ReadMessage = struct {
    pub const requirements: system.Signature = system.Signature{
        .fields = &.{ 
            .{
                // will only ever match with Message.body
                .type = Body,
                .name = "body"
            },
    };

    pub fn process(comptime T: type, item: T, info: system.RegistryInfo) system.Error!void {
        std.debug.print("{s}", .{ item.body });
    }
}
```
The operation to apply `Dissolve(T)` is called `Erode(T)`. `Alias(T)` is provided in `mangle`, `Dissolve(T)` in `mangle.flags`

## Type-System Qualification

Specifically, qualification matching depends entirely on the structure, fields and flags of those fields.

```zig
const A = struct {
    sub: Own(T),
};
const B = struct {
    sub: Leaf(T),
};
const C = struct {
    sub: Compose(T),
};

const D = struct {
    sub: Dissolve(T),
};

const T = struct {
    item: u32,
}
```
All of these are semantically different:
    - `Own(T)` will be processed independently
    - `Leaf(T)` will be processed with the top-level only
    - `Compose(T)` extracts sub's fields into the top-level
    - `Dissolve(T)` extracts sub's fields into the top-level, after qualification

The following system matches with: `A.sub`, `C`, `D`, and `T`
```zig
pub const requirements: system.Signature = system.Signature{
    .fields = &.{ 
        .{
            .type = u32,
            .name = _, // not used in qualification.
        },
    },
};
```
Meaning, the system's `process` function will get called on `A.sub`, `C`, and `T`

## Memory Semantics of Flags

### Flatten

Flatten applies to [explicit composition](#composet). It takes a nested structure and flattens it recursively and accordingly.
Flatten is called on *every* structure inputted to the registry, to non-composed structures, it's equivalent to identity.

```zig
const T = struct {
    field_a: []const u8,
    sub: Compose(U),
    other_field: u32,
};

const U = struct {
    u_field: u64,
}
```
Calling `Flatten(T)` produces the following
```zig
struct {
    field_a: []const u8
    u_field: u64,
    other_field: u32,
}
```
A quirk of `Flatten(T)` is it doesn't ensure memory equivalence, therefore there's a runtime `flatten(t)` to cast to a flattened version.

### Erode

Dissolve is very similar to [Flatten](#flatten) in most of it's logic, and semantics, in fact they use the exact same underlying functions.<br>
The largest difference is `Erode(T)` operates on `.dissolve`, whiles `Flatten(T)` on `.compose`

## Pathing

Pathing is implicitly applied to every type, and provides structure for deinitialization, and tree-climbing. It contains no runtime overhead, as it exists as hidden information injected into each type.<br>

### GetPath(T)

`GetPath(T)` returns a format like the following `namespace.TopLevel_SubLevel_SubSublevel`, where '_' is the delimiter.<br>
For a delimiter as a library variable, use `flags.pathing.flag_delimiter`

## Registry(T)

The registry is where the information is stored, and contained in the engine, initialization is mainly compile-time.
Functions:
    - `addValue(value: anytype)`
        - used to explicitly add an item to the registry *intended for use before `process`
    - `process(delta: f32)`
        - used to run `system.process`es

Most functions in RegistryInfo are what systems should interact with
It has the following functions:
    - `appendDeferred(value: anytype)`
        - appends any type in the registry to the registry at the end of process
    - `dropDeferred(value: anytype)`
        - requests a `drop` on any type in the registry. Works on sub-structures, deinitialization is passed up to top level.

## Debug Info

When `@import("builtin").mode == .Debug`, simple type information will be provided about types and the systems they qualify for.<br>
When building for other optimizations, this is omited during comptime.<br>
If there's a missing qualification or a qualification you don't want, please report an issue, or contact me directly. <br>

## Documentation

Documentation is hosted on Github pages, [here](https://maningreen.github.io/mangle.zig). Generated via `zig build docs`
