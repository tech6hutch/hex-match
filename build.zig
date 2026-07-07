const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Configure dependencies.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_c = raylib_dep.artifact("raylib");

    // Configure and output exe.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raylib", .module = raylib_dep.module("raylib") },
        },
    });
    exe_mod.linkLibrary(raylib_c);
    const exe = b.addExecutable(.{
        .name = "mail_bros",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Include extra files.
    const install_step = b.getInstallStep();
    const install_resources = b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .bin,
        .install_subdir = "assets",
    });
    install_step.dependOn(&install_resources.step);

    // Let you directly run the app after building.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(install_step);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Set up tests.
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
