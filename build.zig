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
    const installLib = b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .lib } });
    b.getInstallStep().dependOn(&installLib.step);

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
