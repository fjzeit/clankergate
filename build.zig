const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Version can be overridden via -Dversion=<version>
    // If not specified, reads from VERSION file
    const version_opt = b.option([]const u8, "version", "Version string");
    const version = version_opt orelse blk: {
        const io = b.graph.io;
        const version_contents = std.Io.Dir.cwd().readFileAlloc(io, "VERSION", b.allocator, .limited(1024)) catch @panic("Failed to read VERSION file");
        // Trim whitespace
        break :blk std.mem.trim(u8, version_contents, " \t\n\r");
    };

    const exe = b.addExecutable(.{
        .name = "clankergate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Pass version as a build option
    const version_options = b.addOptions();
    version_options.addOption([]const u8, "version", version);
    exe.root_module.addOptions("build_options", version_options);

    b.installArtifact(exe);

    // Install default config file alongside executable
    const config_file = b.addInstallFile(b.path("clankergate.json"), "bin/clankergate.json");
    b.getInstallStep().dependOn(&config_file.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}