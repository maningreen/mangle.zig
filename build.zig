const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mainModule = b.addModule("mangle", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("./src/mangle.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "mangle",
        .root_module = mainModule,
    });
    _ = b.addInstallArtifact(lib, .{});

    const tests = b.addTest(.{
        .root_module = mainModule,
    });
    const runTests = b.addRunArtifact(tests);
    const testStep = b.step("test", "Runs tests");
    testStep.dependOn(&runTests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
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
