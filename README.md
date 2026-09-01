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

## Structure

The overall usage of the mangle library is with systems, types, and the registry.

Create a registry as so
```zig
const Registry = mangle.Registry(&.{ MyType }, &.{ MySystem });
var registry = Registry.init(io, gpa);
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

### Creating a system

In mangle, a system is a type with two declarations:
    - requirements (`mangle.system.signature`)
    - process (`fn (comptime T: type, []T, mangle.RegistryInfo) system.Error!void`)
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

pub fn process(comptime T: type, args: []T, info: system.RegistryInfo) system.Error!void {
    for (args) |item| {
        std.debug.print("{s}", .{ item.string });
    }
}
```

`.type` is used in qualification, and `.name` is used to set the field name in `process`.<br>
Note how in `process` we access a field named `string` in item. The name of the field is guaranteed to be `.name`<br>

This is how a system is defined, any other declarations are ignored.<br>

Learn more about [type-system qualification here](#typesystemqualification)

### Creating a type

In mangle, a type is a structure with any amount of fields.<br>
When a type is provided to a system, the identity will be warped, or 'mangled' out of it.<br>
This means all declarations are removed from the type.<br>

Example:
```zig
pub const MyType = struct {
    myData: []const u8,
};
```

There are also 3 different functions to define the relationship a structure and a sub-structure, affecting how systems qualify it, called [flags](#flags)
    - `Leaf(T)`
    - `Compose(T)`
    - `Own(T)`
We go more in depth on them in [here](#Flags)
A type 'qualifies' for a system if every type in `requirements` is provided as a field in the type.<br>
If it doesn't match, it won't be processed by the system.

### Flags

A flag is the term for the following functions:
    - [`Leaf(T)`](#leaft)
    - [`Compose(T)`](#composet)
    - [`Own(T)`](#ownt)
Each one defines the relationship of a type and sub-structure, altering how a systems qualify them.<br>
Each flag (except [Own](#ownt)) is qualified with a hidden 'flag' field with size 0.

#### Own(T)

`Own(T)` is the default behavior, calling it creates no semantic effect, except clarifies useage.

Example:
```zig
const A = struct {
    sub: Own(B),
};

const B = struct {
    bField: u32,
}
```
This means an instance of `A` owns an instance of `B`, but `sub` can be processed by a system independently through a process called [`projecting`](#projecting)

#### Compose(T)

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

#### Leaf(T)

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

### Type-System Qualification

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

const T = struct {
    item: u32,
}
```
All of these are semantically different:
    - `Own(T)` will be processed independently
    - `Leaf(T)` will be processed with the top-level only
    - `Compose(T)` extracts sub's fields into the top-level

The following system matches with: `A.sub` (independently), `C`, and `T`
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
Meaning, the system's `process` function will get called on [`Project(A, .sub)`](#projection), `C`, and `T`

### Semantics of Flags

#### Projection

In this context, `Project(T, .field)` means to project the sub-structure `.field` onto the memory of `T`. This has similar effects to [flattening](#flatten), but importantly discards all other fields from `T`<br>
In memory, this is what happens with the following example (disregarding footprint optimizations).
```zig
const T = struct {
    field_a: []const u8,
    u_field: U,
    other_field: i64
};
const U = struct {
    field: u32,
}
```

Calling `Project(T, .u_field)` produces roughly following
```zig
extern struct {
    _1: [16]u8 // anonymized []const u8,
    field: u32,
    _2: [8]u8, // anonymized []other_field
}
```
It's guaranteed that field will be in the same memory location as it is in `U` and `T` <br>
Due to `Project()` being a more advanced function, it's not available in the direct `mangle` namespace, but rather in `mangle.utils` for advanced users

#### Flatten

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

## Debug Info

When `@import("builtin").mode == .Debug`, simple type information will be provided about types and the systems they qualify for.<br>
When building for other optimizations, this is omited during comptime.<br>
If there's a missing qualification or a qualification you don't want, please report an issue. <br>

## Documentation

Documentation is hosted on Github pages, [here](https://maningreen.github.io/mangle.zig). Generated via `zig build docs`
