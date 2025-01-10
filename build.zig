const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "equilibrium",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false,
    });

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zap", zap.module("zap"));
    exe.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{
        .name = "equilibrium",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);
}
