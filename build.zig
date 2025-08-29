const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    
    // Link with secp256k1
    const target_info = target.result;
    switch (target_info.os.tag) {
        .macos => {
            exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        },
        .linux => {
            exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
            exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        },
        .windows => {
            // Add Windows-specific paths if needed
            exe.addIncludePath(.{ .cwd_relative = "C:/secp256k1/include" });
            exe.addLibraryPath(.{ .cwd_relative = "C:/secp256k1/lib" });
        },
        else => {},
    }
    exe.linkSystemLibrary("secp256k1");
    exe.linkLibC();

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

    // Link with secp256k1
    switch (target_info.os.tag) {
        .macos => {
            test_exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            test_exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        },
        .linux => {
            test_exe.addIncludePath(.{ .cwd_relative = "/usr/include" });
            test_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        },
        .windows => {
            test_exe.addIncludePath(.{ .cwd_relative = "C:/secp256k1/include" });
            test_exe.addLibraryPath(.{ .cwd_relative = "C:/secp256k1/lib" });
        },
        else => {},
    }
    test_exe.linkSystemLibrary("secp256k1");
    test_exe.linkLibC();

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

    switch (target_info.os.tag) {
        .macos => {
            exe_unit_tests.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            exe_unit_tests.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        },
        .linux => {
            exe_unit_tests.addIncludePath(.{ .cwd_relative = "/usr/include" });
            exe_unit_tests.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        },
        .windows => {
            exe_unit_tests.addIncludePath(.{ .cwd_relative = "C:/secp256k1/include" });
            exe_unit_tests.addLibraryPath(.{ .cwd_relative = "C:/secp256k1/lib" });
        },
        else => {},
    }
    exe_unit_tests.linkSystemLibrary("secp256k1");
    exe_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
