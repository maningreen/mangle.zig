const std = @import("std");

pub fn build(b: *std.Build) void {
    _, const generatedPath = generateSystemsFile(b, "src/systems/ecsTypes.zig", "src/systems");
    const updated = b.addUpdateSourceFiles();
    updated.addCopyFileToSource(generatedPath, "./src/systems/example.zig");

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

pub fn generateSystemsFile(b: *std.Build, name: []const u8, dir: []const u8) @Tuple(&.{ *std.Build.Step.WriteFile, std.Build.LazyPath }) {
    const files = compileFilesInDirectory(b.graph.io, dir, b.allocator) catch |err| @panic(@errorName(err));
    const write = b.addWriteFiles();

    var contents = std.Io.Writer.Allocating.init(b.allocator);
    contents.writer.print(
        \\pub const systems: []const []const u8 = &.{{
        \\
    , .{}) catch |err| @panic(@errorName(err));

    for (files) |file| {
        contents.writer.print(
            \\@import("{s}"),
            \\
        , .{file}) catch |err| @panic(@errorName(err));
    }

    contents.writer.print(
        \\}};
    , .{}) catch |err| @panic(@errorName(err));

    const written = write.add(name, contents.toOwnedSlice() catch |err| @panic(@errorName(err)));

    return .{ write, written };
}
