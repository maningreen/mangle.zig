const std = @import("std");

const systemFile: []const u8 = "systems.zig";
const typeFile: []const u8 = "types.zig";

const Library = union(enum) {
    dependency: struct {
        name: []const u8,
        /// if not provided, defaults to `name` only
        modules: ?[]const ModuleInfo = null,
        /// if not provided, does not link
        artifact: ?[]const u8 = null,
    },
    systemLibrary: []const u8,

    const ModuleInfo = struct {
        name: []const u8,
        importAs: ?[]const u8 = null,
    };
};

const dependencies: []const Library = &.{
    .{ .systemLibrary = "X11" },
    .{ .systemLibrary = "Xcursor" },
    .{ .systemLibrary = "Xi" },
    .{ .systemLibrary = "Xinerama" },
    .{ .systemLibrary = "Xrandr" },
    .{ .systemLibrary = "glfw" },
    .{ .dependency = .{
        .name = "raylib",
    } },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bakeTypes = b.step("bake", "generates ecsTypes.zig and systems.zig which holds all of information for the system");
    _, const generatedPathSys = generateEcsFile(b, systemFile, "systems");
    _, const generatedPathTypes = generateEcsFile(b, typeFile, "types");
    const updated = b.addUpdateSourceFiles();
    updated.addCopyFileToSource(generatedPathSys, "./src/" ++ systemFile);
    updated.addCopyFileToSource(generatedPathTypes, "./src/" ++ typeFile);
    bakeTypes.dependOn(&updated.step);

    const mainModule = b.addModule("main", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("./src/main.zig"),
    });
    const exe = b.addExecutable(.{ .name = "fishtFighting", .root_module = mainModule, .linkage = .dynamic });
    const install = b.addInstallArtifact(exe, .{});
    _ = install;

    const run = b.step("run", "runs the executable");
    const runExe = b.addRunArtifact(exe);
    run.dependOn(&runExe.step);

    for (dependencies) |lib| {
        switch (lib) {
            .dependency => |depInfo| {
                const dep = b.dependency(depInfo.name, .{
                    .optimize = optimize,
                    .target = target,
                });
                for (depInfo.modules orelse &.{Library.ModuleInfo{ .name = depInfo.name }}) |module|
                    exe.root_module.addImport(module.importAs orelse module.name, dep.module(module.name));
                if (depInfo.artifact) |artifact| {
                    exe.root_module.linkLibrary(dep.artifact(artifact));
                }
            },
            .systemLibrary => |sys| {
                exe.root_module.linkSystemLibrary(sys, .{ .use_pkg_config = .no });
            },
        }
    }
}

/// walks through a directory tree, compiles files names into a list (full path local to root)
pub fn compileFilesInDirectory(
    io: std.Io,
    dirName: []const u8,
    gpa: std.mem.Allocator,
) ![][]u8 {
    const dir = try std.Io.Dir.openDir(std.Io.Dir.cwd(), io, dirName, .{ .iterate = true });

    var count: u64 = 0;
    {
        var it = dir.iterate();
        while (try it.next(io)) |_| {
            count += 1;
        }
    }
    var files = try std.ArrayList([]u8).initCapacity(gpa, count);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => continue,
            .file => {
                files.appendAssumeCapacity(try std.mem.concat(gpa, u8, &.{entry.name}));
            },
            else => undefined,
        }
    }
    return files.toOwnedSlice(gpa);
}

/// generates the file with the types, places it in `src`
pub fn generateEcsFile(b: *std.Build, name: []const u8, dir: []const u8) @Tuple(&.{ *std.Build.Step.WriteFile, std.Build.LazyPath }) {
    const files = compileFilesInDirectory(
        b.graph.io,
        std.mem.concat(
            b.allocator,
            u8,
            &.{ "src/", dir },
        ) catch |err| @panic(@errorName(err)),
        b.allocator,
    ) catch |err| @panic(@errorName(err));
    const write = b.addWriteFiles();

    var contents = std.Io.Writer.Allocating.init(b.allocator);
    contents.writer.print(
        \\pub const {s} = [_]type{{
        \\
    , .{dir}) catch |err| @panic(@errorName(err));

    for (files) |file| {
        contents.writer.print(
            \\    @import("{s}/{s}"),
            \\
        , .{ dir, file }) catch |err| @panic(@errorName(err));
    }

    contents.writer.print(
        \\}};
    , .{}) catch |err| @panic(@errorName(err));

    const written = write.add(name, contents.toOwnedSlice() catch |err| @panic(@errorName(err)));

    return .{ write, written };
}
