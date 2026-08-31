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

    const examples: []const []const u8 = &.{
        "helloWorld",
    };

    const exampleBuildStep = b.step("examples", "builds all examples");
    const runExampleFmt = "run-{s}";
    const runExampleDescFmt = "runs the {s} example";

    inline for (examples) |example| {
        const exe = addExample(b, example, .{
            .optimize = optimize,
            .target = target,
            .mangle = lib,
        });
        const installExe = b.addInstallArtifact(exe, .{});
        exampleBuildStep.dependOn(&installExe.step);
        const runStep = b.step(
            std.fmt.comptimePrint(runExampleFmt, .{example}),
            std.fmt.comptimePrint(runExampleDescFmt, .{example}),
        );
        const runExe = b.addRunArtifact(exe);
        runStep.dependOn(&runExe.step);
    }

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

fn addExample(
    b: *std.Build,
    exampleName: []const u8,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        mangle: *std.Build.Step.Compile,
    },
) *std.Build.Step.Compile {
    const exampleDirectory = "examples/";
    const exampleMain = "main.zig";

    const path = b.pathJoin(&.{ exampleDirectory, exampleName, exampleMain });
    const main = b.path(path);
    const module = b.createModule(.{
        .optimize = options.optimize,
        .target = options.target,
        .root_source_file = main,
        .imports = &.{},
    });

    module.linkLibrary(options.mangle);

    return b.addExecutable(.{
        .name = exampleName,
        .root_module = module,
    });
}
