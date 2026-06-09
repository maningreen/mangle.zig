const std = @import("std");

pub fn build(b: *std.Build) void {
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
