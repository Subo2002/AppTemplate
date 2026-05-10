const std = @import("std");

const SysgpuBackend = enum {
    default,
    webgpu,
    d3d12,
    metal,
    vulkan,
    opengl,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "AppTemplate",
        .root_module = exe_mod,
    });

    const sdl = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_ttf = true,
    });
    exe_mod.addImport("sdl", sdl.module("sdl3"));

    b.installArtifact(exe);

    // Run the app when `zig build run` is invoked
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Run tests when `zig build test` is run
    const app_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_app_unit_tests = b.addRunArtifact(app_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_app_unit_tests.step);
}
