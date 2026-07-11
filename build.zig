const std = @import("std");
const rlz = @import("raylib_zig");

const exe_name = @tagName(@import("./build.zig.zon").name);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_web = target.query.os_tag == .emscripten;

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

    // Include extra files.
    const install_step = b.getInstallStep();
    const install_dir: std.Build.InstallDir = if (is_web) .{ .custom = "web" } else .bin;
    const install_resources = b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = install_dir,
        .install_subdir = "assets",
    });
    install_step.dependOn(&install_resources.step);

    const run_step = b.step("run", "Run the app");

    if (is_web) {
        const emsdk = rlz.emsdk;
        const wasm = b.addLibrary(.{
            .name = exe_name,
            .root_module = exe_mod,
        });

        const emcc_flags = emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize });
        const emcc_settings = emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });

        const emcc_step = emsdk.emccStep(b, raylib_c, wasm, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .install_dir = install_dir,
        });
        b.getInstallStep().dependOn(emcc_step);

        const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm.name});
        const emrun_step = emsdk.emrunStep(
            b,
            b.getInstallPath(install_dir, html_filename),
            &.{},
        );

        emrun_step.dependOn(emcc_step);
        run_step.dependOn(emrun_step);
    } else {
        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = exe_mod,
        });
        b.installArtifact(exe);

        // Let you directly run the app after building.
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(install_step);
        if (b.args) |args| run_cmd.addArgs(args);
        run_step.dependOn(&run_cmd.step);

        // Set up tests.
        const exe_unit_tests = b.addTest(.{
            .root_module = exe_mod,
        });
        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
