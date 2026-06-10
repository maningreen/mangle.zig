const std = @import("std");

pub fn build(b: *std.Build) void {
    const bakeTypes = b.step("bake", "generates ecsTypes.zig which holds all of the ecs types");

    _, const generatedPath = generateSystemsFile(b, "ecsTypes.zig", "systems");
    const updated = b.addUpdateSourceFiles();
    updated.addCopyFileToSource(generatedPath, "./src/ecsTypes.zig");
    bakeTypes.dependOn(&updated.step);

    const mainModule = b.addModule("main", .{
        .optimize = .Debug,
        .target = b.graph.host,
        .root_source_file = b.path("./src/main.zig"),
    });
    const exe = b.addExecutable(.{
        .name = "fishtFighting",
        .root_module = mainModule,
    });
    const install = b.addInstallArtifact(exe, .{});
    _ = install;

    const run = b.step("run", "runs the executable");
    const runExe = b.addRunArtifact(exe);
    run.dependOn(&runExe.step);
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

/// generates the file with the systems, places it in `src`
pub fn generateSystemsFile(b: *std.Build, name: []const u8, dir: []const u8) @Tuple(&.{ *std.Build.Step.WriteFile, std.Build.LazyPath }) {
    const files = compileFilesInDirectory(
        b.graph.io,
        std.mem.concat(
            b.allocator,
            u8,
            &.{"src/", dir},
        ) catch |err| @panic(@errorName(err)),
        b.allocator,
    ) catch |err| @panic(@errorName(err));
    const write = b.addWriteFiles();

    var contents = std.Io.Writer.Allocating.init(b.allocator);
    contents.writer.print(
        \\pub const systems = [_]type{{
        \\
    , .{}) catch |err| @panic(@errorName(err));

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
