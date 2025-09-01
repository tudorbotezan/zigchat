const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Windows-specific options for secp256k1
    const secp256k1_include = b.option([]const u8, "secp256k1_include", "Path to secp256k1 include directory");
    const secp256k1_lib = b.option([]const u8, "secp256k1_lib", "Path to secp256k1 lib directory");

    // Add ws module from lib/ws
    const ws_module = b.addModule("ws", .{
        .root_source_file = b.path("lib/ws/src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "zigchat",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("ws", ws_module);
    
    // Link with C libraries
    exe.linkLibC();
    
    // Windows-specific library paths
    if (secp256k1_include) |inc| {
        exe.addIncludePath(.{ .cwd_relative = inc });
    }
    if (secp256k1_lib) |lib| {
        exe.addLibraryPath(.{ .cwd_relative = lib });
    }
    
    // On Windows, we need to link additional libraries for secp256k1
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("secp256k1");
        exe.linkSystemLibrary("secp256k1_precomputed");
    } else {
        exe.linkSystemLibrary("secp256k1");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test executable for NIP-01 signatures
    const test_exe = b.addExecutable(.{
        .name = "test_nip01",
        .root_source_file = b.path("src/test_nip01.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with C libraries
    test_exe.linkLibC();
    
    // Windows-specific library paths
    if (secp256k1_include) |inc| {
        test_exe.addIncludePath(.{ .cwd_relative = inc });
    }
    if (secp256k1_lib) |lib| {
        test_exe.addLibraryPath(.{ .cwd_relative = lib });
    }
    
    // On Windows, we need to link additional libraries for secp256k1
    if (target.result.os.tag == .windows) {
        test_exe.linkSystemLibrary("secp256k1");
        test_exe.linkSystemLibrary("secp256k1_precomputed");
    } else {
        test_exe.linkSystemLibrary("secp256k1");
    }

    b.installArtifact(test_exe);

    const test_run_cmd = b.addRunArtifact(test_exe);
    test_run_cmd.step.dependOn(b.getInstallStep());

    const test_nip01_step = b.step("test-nip01", "Test NIP-01 signature generation");
    test_nip01_step.dependOn(&test_run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.linkLibC();
    
    // Windows-specific library paths
    if (secp256k1_include) |inc| {
        exe_unit_tests.addIncludePath(.{ .cwd_relative = inc });
    }
    if (secp256k1_lib) |lib| {
        exe_unit_tests.addLibraryPath(.{ .cwd_relative = lib });
    }
    
    // On Windows, we need to link additional libraries for secp256k1
    if (target.result.os.tag == .windows) {
        exe_unit_tests.linkSystemLibrary("secp256k1");
        exe_unit_tests.linkSystemLibrary("secp256k1_precomputed");
    } else {
        exe_unit_tests.linkSystemLibrary("secp256k1");
    }

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
