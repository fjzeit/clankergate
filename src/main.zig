const std = @import("std");
const build_options = @import("build_options");

const EXIT_DENIED = 126;

/// Explicit error set for ClankerGate operations
const ClankerGateError = error{
    /// CLANKERGATE_CONFIG environment variable not set
    ConfigNotSet,
    /// Config file not found
    ConfigNotFound,
    /// Invalid JSON in config file
    InvalidConfig,
    /// Unknown target (argv[0] doesn't match any target in config)
    UnknownTarget,
    /// Target missing executable field
    MissingExecutable,
    /// Memory allocation failed
    OutOfMemory,
};

const Mode = enum {
    config,
    passthrough,
    readonly,
    block,
    default, // Ignore this config entry, use default config
};

/// Tagged union for parameter count matching
const ParamCount = union(enum) {
    /// Match any number of parameters
    any,
    /// Match exact number of parameters
    exact: usize,

    fn fromString(str: []const u8) ?ParamCount {
        if (std.mem.eql(u8, str, "*")) {
            return .any;
        }
        const count = std.fmt.parseInt(usize, str, 10) catch return null;
        return .{ .exact = count };
    }
};

const Rule = struct {
    command: []const u8,
    paramCount: ParamCount,
};

/// Per-target configuration
const TargetConfig = struct {
    /// Path to the real executable to invoke
    executable: []const u8,
    /// Operating mode
    mode: Mode = .config,
    /// Flags to skip during parsing (glob patterns)
    passive: ?[]const []const u8 = null,
    /// Flags that take a next argument (skip flag + value)
    passiveWithArg: ?[]const []const u8 = null,
    /// Always-allowed commands (bypass whitelist)
    passthrough: ?[]const []const u8 = null,
    /// Whitelist rules for config mode
    allowed: ?[]const Rule = null,
};

/// Root configuration with targets map
const RootConfig = struct {
    targets: std.StringHashMap(TargetConfig),
};

/// Check if a string matches a glob pattern
/// Pattern ending in '*' matches if string starts with prefix
/// Pattern without '*' requires exact match
fn matchesGlob(str: []const u8, pattern: []const u8) bool {
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, str, prefix);
    }
    return std.mem.eql(u8, str, pattern);
}

const CommandLine = struct {
    nonFlagArgs: []const []const u8,
    originalArgs: []const []const u8,

    /// Parse command line, skipping passive flags based on config
    fn parse(allocator: std.mem.Allocator, args: []const []const u8, target: *const TargetConfig) !CommandLine {
        // Check for passthrough commands first
        if (target.passthrough) |passthrough| {
            for (args) |arg| {
                for (passthrough) |pt| {
                    if (std.mem.eql(u8, arg, pt)) {
                        // Return empty nonFlagArgs to signal passthrough
                        return .{ .nonFlagArgs = &.{}, .originalArgs = args };
                    }
                }
            }
        }

        // Collect passive patterns from config
        const passivePatterns = target.passive orelse &.{};
        const passiveWithArgPatterns = target.passiveWithArg orelse &.{};

        // Skip global flags
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (!std.mem.startsWith(u8, args[i], "-")) {
                break;
            }

            // Check if this flag takes a next argument (takes precedence over passive)
            var takesArg = false;
            for (passiveWithArgPatterns) |pattern| {
                if (matchesGlob(args[i], pattern)) {
                    takesArg = true;
                    break;
                }
            }

            if (takesArg) {
                // Skip this flag and its argument
                i += 1;
                continue;
            }

            // Check if this flag matches any passive pattern
            var isPassive = false;
            for (passivePatterns) |pattern| {
                if (matchesGlob(args[i], pattern)) {
                    isPassive = true;
                    break;
                }
            }

            // Non-passive flag stops parsing
            if (!isPassive) {
                break;
            }
        }

        // Collect non-flag args
        var nonFlagList: std.ArrayList([]const u8) = .empty;
        while (i < args.len) : (i += 1) {
            if (!std.mem.startsWith(u8, args[i], "-")) {
                try nonFlagList.append(allocator, args[i]);
            }
        }

        return .{ .nonFlagArgs = try nonFlagList.toOwnedSlice(allocator), .originalArgs = args };
    }
};

/// Check if command is allowed by config rules.
/// Returns error on allocation failure, false if denied, true if allowed.
fn isCommandAllowed(allocator: std.mem.Allocator, nonFlagArgs: []const []const u8, config: *const TargetConfig) !bool {
    if (nonFlagArgs.len == 0) {
        return false;
    }

    const rules = config.allowed orelse return false;

    // Try longest match first
    var len: usize = nonFlagArgs.len;
    while (len > 0) : (len -= 1) {
        const candidatePath = std.mem.join(allocator, " ", nonFlagArgs[0..len]) catch |err| {
            return err;
        };
        defer allocator.free(candidatePath);

        for (rules) |rule| {
            if (std.mem.eql(u8, rule.command, candidatePath)) {
                const paramCount = nonFlagArgs.len - len;
                return switch (rule.paramCount) {
                    .any => true,
                    .exact => |count| paramCount == count,
                };
            }
        }
    }

    return false;
}

/// Extract target name from argv[0]
/// Returns basename with extension stripped (e.g., "git" from "/usr/bin/git" or "git.exe")
fn extractTargetName(argv0: []const u8) []const u8 {
    // Get basename
    const basename = std.fs.path.basename(argv0);

    // Strip extension on Windows
    if (std.mem.lastIndexOf(u8, basename, ".")) |dot_pos| {
        return basename[0..dot_pos];
    }
    return basename;
}

/// Load config from file (supports both absolute and relative paths)
fn loadConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) !RootConfig {
    // Try to open the config file
    const file = if (std.fs.path.isAbsolute(configPath))
        std.Io.Dir.openFileAbsolute(io, configPath, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Config file not found: {s}\n", .{configPath});
                return error.ConfigNotFound;
            }
            std.debug.print("Failed to open config file: {s}\n", .{configPath});
            return error.InvalidConfig;
        }
    else
        std.Io.Dir.openFile(.cwd(), io, configPath, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Config file not found: {s}\n", .{configPath});
                return error.ConfigNotFound;
            }
            std.debug.print("Failed to open config file: {s}\n", .{configPath});
            return error.InvalidConfig;
        };
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const contents = reader.interface.allocRemaining(allocator, .unlimited) catch return error.OutOfMemory;
    defer allocator.free(contents);

    // Parse as generic JSON value
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        std.debug.print("Invalid config JSON: {s}\n", .{configPath});
        return error.InvalidConfig;
    };
    defer parsed.deinit();

    const root = parsed.value.object.get("targets") orelse {
        std.debug.print("Config missing 'targets' field\n", .{});
        return error.InvalidConfig;
    };

    // Build targets map
    var targets = std.StringHashMap(TargetConfig).init(allocator);
    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        const targetName = entry.key_ptr.*;
        const targetValue = entry.value_ptr.*;

        // Parse executable (required)
        const executable_val = targetValue.object.get("executable") orelse {
            std.debug.print("Target '{s}' missing 'executable' field\n", .{targetName});
            return error.InvalidConfig;
        };
        const executable = executable_val.string;

        // Parse mode (optional, default: config)
        const mode: Mode = if (targetValue.object.get("mode")) |mode_val|
            std.meta.stringToEnum(Mode, mode_val.string) orelse {
                std.debug.print("Invalid mode '{s}' in target '{s}'\n", .{ mode_val.string, targetName });
                return error.InvalidConfig;
            }
        else
            .config;

        // Parse passive (optional)
        const passive = if (targetValue.object.get("passive")) |passive_val|
            try parseStringArray(allocator, passive_val.array.items)
        else
            null;

        // Parse passiveWithArg (optional)
        const passiveWithArg = if (targetValue.object.get("passiveWithArg")) |pwa_val|
            try parseStringArray(allocator, pwa_val.array.items)
        else
            null;

        // Parse passthrough (optional)
        const passthrough = if (targetValue.object.get("passthrough")) |pt_val|
            try parseStringArray(allocator, pt_val.array.items)
        else
            null;

        // Parse allowed (optional)
        var rulesList: std.ArrayList(Rule) = .empty;
        if (targetValue.object.get("allowed")) |allowed_val| {
            for (allowed_val.array.items) |rule_val| {
                const command = rule_val.object.get("command").?.string;
                const paramCountStr = rule_val.object.get("paramCount").?.string;
                const paramCount = ParamCount.fromString(paramCountStr) orelse {
                    std.debug.print("Invalid paramCount '{s}' for rule in target '{s}'\n", .{ paramCountStr, targetName });
                    return error.InvalidConfig;
                };
                try rulesList.append(allocator, .{
                    .command = try allocator.dupe(u8, command),
                    .paramCount = paramCount,
                });
            }
        }

        const targetConfig = TargetConfig{
            .executable = try allocator.dupe(u8, executable),
            .mode = mode,
            .passive = passive,
            .passiveWithArg = passiveWithArg,
            .passthrough = passthrough,
            .allowed = if (rulesList.items.len > 0) try rulesList.toOwnedSlice(allocator) else null,
        };

        try targets.put(try allocator.dupe(u8, targetName), targetConfig);
    }

    return .{ .targets = targets };
}

/// Parse array of JSON strings into []const []const u8
fn parseStringArray(allocator: std.mem.Allocator, items: []const std.json.Value) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, items.len);
    for (items, 0..) |item, i| {
        result[i] = try allocator.dupe(u8, item.string);
    }
    return result;
}

fn executeCommand(allocator: std.mem.Allocator, io: std.Io, executable: []const u8, args: []const []const u8) !u8 {
    // Build argv: executable followed by args
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, executable);
    try argv.appendSlice(allocator, args);

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
        .expand_arg0 = .no_expand,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try child.wait(io);

    return switch (term) {
        .exited => |code| code,
        .signal => EXIT_DENIED,
        .stopped => EXIT_DENIED,
        .unknown => EXIT_DENIED,
    };
}

fn executeCommandOrDeny(allocator: std.mem.Allocator, io: std.Io, executable: []const u8, args: []const []const u8, command: []const u8) u8 {
    return executeCommand(allocator, io, executable, args) catch {
        printDeniedMessage(command);
        return EXIT_DENIED;
    };
}

pub fn main(init: std.process.Init) !u8 {
    // Use arena allocator - all allocations freed on scope exit
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    // Get args iterator early to find argv[0]
    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iter.deinit();

    // Get argv[0] for target selection and default config path
    const argv0 = args_iter.next() orelse {
        std.debug.print("No argv[0] available\n", .{});
        return EXIT_DENIED;
    };
    const targetName = extractTargetName(argv0);

    // Build default config path (clankergate.json alongside executable)
    const exe_dir = std.fs.path.dirname(argv0) orelse ".";
    const defaultConfigPath = std.fs.path.join(allocator, &.{ exe_dir, "clankergate.json" }) catch {
        std.debug.print("Failed to build default config path\n", .{});
        return EXIT_DENIED;
    };

    // If invoked as "clankergate", enter CLI mode
    if (std.mem.eql(u8, targetName, "clankergate")) {
        return runCli(allocator, io, init.environ_map.*, &args_iter, defaultConfigPath);
    }

    // Try to find target in config, with fallback to default
    const target_ptr = blk: {
        // First: try CLANKERGATE_CONFIG if set
        if (init.environ_map.get("CLANKERGATE_CONFIG")) |configPath| {
            if (loadConfig(allocator, io, configPath)) |rootConfig| {
                if (rootConfig.targets.getPtr(targetName)) |t| {
                    // If mode is "default", ignore this entry and fall back to default config
                    if (t.mode == .default) {
                        // Fall through to default config
                    } else {
                        break :blk t;
                    }
                }
                // Target not in CLANKERGATE_CONFIG (or mode=default), fall through to default
            } else |_| {
                // CLANKERGATE_CONFIG failed to load, fall through to default
            }
        }

        // Second: try default config
        if (loadConfig(allocator, io, defaultConfigPath)) |rootConfig| {
            if (rootConfig.targets.getPtr(targetName)) |t| {
                break :blk t;
            }
            // Target not in default config either
            var targetsList: std.ArrayList([]const u8) = .empty;
            var iter = rootConfig.targets.iterator();
            while (iter.next()) |entry| {
                try targetsList.append(allocator, entry.key_ptr.*);
            }
            const targetsStr = try std.mem.join(allocator, ", ", targetsList.items);
            std.debug.print("Unknown target '{s}'. Available: {s}\n", .{ targetName, targetsStr });
            return EXIT_DENIED;
        } else |_| {
            std.debug.print("Config file not found: {s}\n", .{defaultConfigPath});
            return EXIT_DENIED;
        }

        // Should not reach here
        std.debug.print("No config available for target '{s}'\n", .{targetName});
        return EXIT_DENIED;
    };

    // Collect remaining args
    var cmdArgsList: std.ArrayList([]const u8) = .empty;
    while (args_iter.next()) |arg| {
        try cmdArgsList.append(allocator, arg);
    }
    const cmdArgs = cmdArgsList.items;

    // Passthrough mode: skip all checks
    if (target_ptr.mode == .passthrough) {
        return executeCommandOrDeny(allocator, io, target_ptr.executable, cmdArgs, "(passthrough mode)");
    }

    // Block mode: deny everything
    if (target_ptr.mode == .block) {
        printDeniedMessage("(block mode)");
        return EXIT_DENIED;
    }

    // Parse command line with target-specific config
    const commandLine = try CommandLine.parse(allocator, cmdArgs, target_ptr);

    // Check for passthrough command (empty nonFlagArgs signals this)
    if (commandLine.nonFlagArgs.len == 0) {
        return executeCommandOrDeny(allocator, io, target_ptr.executable, cmdArgs, "(passthrough command)");
    }

    // Config mode: check whitelist
    const is_allowed = isCommandAllowed(allocator, commandLine.nonFlagArgs, target_ptr) catch false;
    if (!is_allowed) {
        const command = if (commandLine.nonFlagArgs.len > 0)
            std.mem.join(allocator, " ", commandLine.nonFlagArgs) catch "(no command)"
        else
            "(no command)";
        printDeniedMessage(command);
        return EXIT_DENIED;
    }

    const command = std.mem.join(allocator, " ", commandLine.nonFlagArgs) catch "(allowed command)";
    return executeCommandOrDeny(allocator, io, target_ptr.executable, cmdArgs, command);
}

fn printDeniedMessage(command: []const u8) void {
    const stderr_writer = &std.debug.lockStderr(&.{}).file_writer.interface;
    defer std.debug.unlockStderr();

    writeDeniedMessage(stderr_writer, command) catch {};
}

fn writeDeniedMessage(writer: *std.Io.Writer, command: []const u8) !void {
    try writer.writeAll(
        \\POLICY BLOCK: This operation is not permitted by the user's AI policy.
        \\Do not retry, investigate, or attempt workarounds.
        \\Inform the user what you attempted and wait for their instruction.
        \\The policy may change — do not assume future operations will also be blocked.
        \\
    );
    _ = command;
}

// ============================================================================
// CLI Mode
// ============================================================================

fn runCli(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, args_iter: *std.process.Args.Iterator, defaultConfigPath: []const u8) u8 {
    // Collect remaining args
    var cmdArgsList: std.ArrayList([]const u8) = .empty;
    while (args_iter.next()) |arg| {
        cmdArgsList.append(allocator, arg) catch {
            std.debug.print("Failed to allocate memory\n", .{});
            return EXIT_DENIED;
        };
    }
    const cmdArgs = cmdArgsList.items;

    if (cmdArgs.len == 0) {
        printHelp();
        return 0;
    }

    const subcommand = cmdArgs[0];

    if (std.mem.eql(u8, subcommand, "help")) {
        printHelp();
        return 0;
    }

    if (std.mem.eql(u8, subcommand, "version")) {
        std.debug.print("{s}\n", .{build_options.version});
        return 0;
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        const configPath = if (cmdArgs.len > 1) cmdArgs[1] else defaultConfigPath;
        return runList(allocator, io, configPath);
    }

    if (std.mem.eql(u8, subcommand, "healthcheck")) {
        // healthcheck [fix] [config-path]
        var fix = false;
        var configPath: ?[]const u8 = null;
        
        for (cmdArgs[1..]) |arg| {
            if (std.mem.eql(u8, arg, "fix")) {
                fix = true;
            } else {
                configPath = arg;
            }
        }
        
        return runHealthcheck(allocator, io, configPath orelse defaultConfigPath, fix, environ_map);
    }

    std.debug.print("Unknown command: {s}\n\n", .{subcommand});
    printHelp();
    return EXIT_DENIED;
}

fn printHelp() void {
    std.debug.print(
        \\ClankerGate v{s} - A command gate for AI coding agents
        \\Copyright (c) fjzeit - https://github.com/fjzeit/clankergate
        \\
        \\Usage:
        \\  clankergate version                   Show version
        \\  clankergate help                      Show this help
        \\  clankergate list [config-path]        List targets and their configuration
        \\  clankergate healthcheck [config-path]  Verify executables match config
        \\  clankergate healthcheck fix [config-path] Fix executable paths in config
        \\
        \\When invoked as a symlink (e.g., 'git'), ClankerGate gates commands
        \\based on the configuration file.
        \\
        \\Configuration is loaded from:
        \\  1. CLANKERGATE_CONFIG environment variable (if set)
        \\  2. clankergate.json alongside the executable
        \\
    , .{build_options.version});
}

fn runList(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) u8 {
    const rootConfig = loadConfig(allocator, io, configPath) catch {
        std.debug.print("Failed to load config from: {s}\n", .{configPath});
        return EXIT_DENIED;
    };

    std.debug.print("Targets:\n\n", .{});

    var iter = rootConfig.targets.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const config = entry.value_ptr.*;
        std.debug.print("  {s}\n", .{name});
        std.debug.print("    executable: {s}\n", .{config.executable});
        std.debug.print("    mode: {s}\n", .{@tagName(config.mode)});
        if (config.allowed) |rules| {
            std.debug.print("    allowed: {d} command(s)\n", .{rules.len});
        }
        std.debug.print("\n", .{});
    }

    return 0;
}

const HealthIssue = struct {
    name: []const u8,
    expected: []const u8,
    actual: ?[]const u8,
};

fn runHealthcheck(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, fix: bool, environ_map: std.process.Environ.Map) u8 {
    const rootConfig = loadConfig(allocator, io, configPath) catch {
        std.debug.print("Failed to load config from: {s}\n", .{configPath});
        return EXIT_DENIED;
    };

    var hasIssues = false;
    var issues: std.ArrayList(HealthIssue) = .empty;

    std.debug.print("Checking {s}\n\n", .{configPath});

    var iter = rootConfig.targets.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const config = entry.value_ptr.*;

        // Find the actual executable on PATH
        const actualPath = findOnPath(allocator, io, environ_map, name) orelse blk: {
            // If not found on PATH, check if the configured path exists
            const stat_result = std.Io.Dir.statFile(.cwd(), io, config.executable, .{}) catch break :blk null;
            _ = stat_result;
            break :blk allocator.dupe(u8, config.executable) catch null;
        };

        if (actualPath) |actual| {
            defer allocator.free(actual);
            if (std.mem.eql(u8, config.executable, actual)) {
                std.debug.print("  {s}: OK ({s})\n", .{ name, actual });
            } else {
                std.debug.print("  {s}: MISMATCH (config: {s}, actual: {s})\n", .{ name, config.executable, actual });
                hasIssues = true;
                const actualDupe = allocator.dupe(u8, actual) catch null;
                issues.append(allocator, .{ .name = name, .expected = actualDupe orelse "", .actual = actualDupe }) catch {};
            }
        } else {
            std.debug.print("  {s}: NOT FOUND (config: {s})\n", .{ name, config.executable });
            hasIssues = true;
            issues.append(allocator, .{ .name = name, .expected = config.executable, .actual = null }) catch {};
        }
    }

    if (fix and hasIssues) {
        std.debug.print("\nFixing {s}...\n", .{configPath});
        const result = fixConfig(allocator, io, configPath, issues.items);
        if (result != 0) return result;
        
        // Re-run healthcheck to show the outcome
        std.debug.print("\n", .{});
        return runHealthcheck(allocator, io, configPath, false, environ_map);
    }

    if (hasIssues) {
        std.debug.print("\nRun 'clankergate healthcheck fix' to update\n", .{});
        return EXIT_DENIED;
    }

    return 0;
}

fn fixConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, issues: []const HealthIssue) u8 {
    // Read the config file
    const file = std.Io.Dir.cwd().openFile(io, configPath, .{ .mode = .read_only }) catch |err| {
        std.debug.print("Failed to open config: {s}\n", .{@errorName(err)});
        return EXIT_DENIED;
    };
    defer file.close(io);

    var buffer: [32768]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const contents = reader.interface.allocRemaining(allocator, .unlimited) catch {
        std.debug.print("Failed to read config\n", .{});
        return EXIT_DENIED;
    };
    defer allocator.free(contents);

    // Parse as JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch {
        std.debug.print("Failed to parse config JSON\n", .{});
        return EXIT_DENIED;
    };
    defer parsed.deinit();

    // Update the executable paths
    var targets = parsed.value.object.getPtr("targets") orelse {
        std.debug.print("Config missing 'targets' field\n", .{});
        return EXIT_DENIED;
    };

    for (issues) |issue| {
        if (issue.actual) |actual| {
            const target = targets.object.getPtr(issue.name) orelse continue;
            const exec_ptr = target.object.getPtr("executable") orelse continue;
            
            // Update the executable path
            exec_ptr.* = .{ .string = actual };
            std.debug.print("  {s}: updated to {s}\n", .{ issue.name, actual });
        }
    }

    // Write the updated config back with custom formatting
    const write_file = std.Io.Dir.cwd().createFile(io, configPath, .{ .truncate = true }) catch |err| {
        std.debug.print("Failed to write config: {s}\n", .{@errorName(err)});
        return EXIT_DENIED;
    };
    defer write_file.close(io);

    var write_buffer: [32768]u8 = undefined;
    var writer = write_file.writer(io, &write_buffer);
    
    writeConfigJson(&writer.interface, parsed.value) catch {
        std.debug.print("Failed to serialize config\n", .{});
        return EXIT_DENIED;
    };
    
    writer.interface.flush() catch {
        std.debug.print("Failed to write config\n", .{});
        return EXIT_DENIED;
    };

    return 0;
}

/// Custom JSON formatter that keeps arrays and allowed objects compact
fn writeConfigJson(writer: *std.Io.Writer, value: std.json.Value) !void {
    try writeJsonValue(writer, value, 0);
    try writer.writeByte('\n');
}

fn writeJsonValue(writer: *std.Io.Writer, value: std.json.Value, indent: usize) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |s| try writer.writeAll(s),
        .string => |s| {
            try writer.writeByte('"');
            try writeEscapedString(writer, s);
            try writer.writeByte('"');
        },
        .array => |arr| {
            if (arr.items.len == 0) {
                try writer.writeAll("[]");
                return;
            }
            // Check if this is an array of simple values (strings, numbers, bools)
            var all_simple = true;
            for (arr.items) |item| {
                switch (item) {
                    .string, .integer, .float, .bool, .number_string => {},
                    .object => all_simple = false,
                    else => all_simple = false,
                }
            }
            
            if (all_simple) {
                // Write compact: ["a", "b", "c"]
                try writer.writeAll("[");
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writeJsonValue(writer, item, 0);
                }
                try writer.writeAll("]");
            } else {
                // Check if this is the "allowed" array (array of objects with command/paramCount)
                var is_allowed_array = true;
                for (arr.items) |item| {
                    switch (item) {
                        .object => |obj| {
                            // Check if it has typical allowed fields
                            if (obj.get("command") == null and obj.get("paramCount") == null) {
                                is_allowed_array = false;
                            }
                        },
                        else => is_allowed_array = false,
                    }
                }
                
                if (is_allowed_array and arr.items.len > 0) {
                    // Write each allowed object on its own line
                    try writer.writeAll("[\n");
                    for (arr.items, 0..) |item, i| {
                        try writeIndent(writer, indent + 2);
                        try writeJsonValue(writer, item, indent + 2);
                        if (i < arr.items.len - 1) try writer.writeAll(",");
                        try writer.writeByte('\n');
                    }
                    try writeIndent(writer, indent);
                    try writer.writeAll("]");
                } else {
                    // Default: expand
                    try writer.writeAll("[\n");
                    for (arr.items, 0..) |item, i| {
                        try writeIndent(writer, indent + 2);
                        try writeJsonValue(writer, item, indent + 2);
                        if (i < arr.items.len - 1) try writer.writeAll(",");
                        try writer.writeByte('\n');
                    }
                    try writeIndent(writer, indent);
                    try writer.writeAll("]");
                }
            }
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try writer.writeAll("{}");
                return;
            }
            
            // Check if this is an "allowed" object (has command and paramCount)
            if (obj.get("command") != null and obj.get("paramCount") != null) {
                // Write compact on one line: {"command": "status", "paramCount": "*"}
                try writer.writeAll("{");
                var first = true;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.writeByte('"');
                    try writeEscapedString(writer, entry.key_ptr.*);
                    try writer.writeAll("\": ");
                    try writeJsonValue(writer, entry.value_ptr.*, 0);
                }
                try writer.writeAll("}");
            } else {
                // Normal object with indentation
                try writer.writeAll("{\n");
                var iter = obj.iterator();
                var i: usize = 0;
                while (iter.next()) |entry| {
                    try writeIndent(writer, indent + 2);
                    try writer.writeByte('"');
                    try writeEscapedString(writer, entry.key_ptr.*);
                    try writer.writeAll("\": ");
                    try writeJsonValue(writer, entry.value_ptr.*, indent + 2);
                    if (i < obj.count() - 1) try writer.writeAll(",");
                    try writer.writeByte('\n');
                    i += 1;
                }
                try writeIndent(writer, indent);
                try writer.writeAll("}");
            }
        },
    }
}

fn writeIndent(writer: *std.Io.Writer, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 2) {
        try writer.writeAll("  ");
    }
}

fn writeEscapedString(writer: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{d:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Find an executable on PATH (returns first executable match)
fn findOnPath(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, name: []const u8) ?[]const u8 {
    // Get PATH from environment
    const path_env = environ_map.get("PATH") orelse return null;
    const path_sep = if (@import("builtin").os.tag == .windows) ";" else ":";

    var iter = std.mem.splitSequence(u8, path_env, path_sep);
    while (iter.next()) |path_entry| {
        const full_path = std.fs.path.join(allocator, &.{ path_entry, name }) catch continue;
        
        // Check if file exists using stat
        const exists = blk: {
            const stat_result = std.Io.Dir.statFile(.cwd(), io, full_path, .{}) catch {
                allocator.free(full_path);
                break :blk false;
            };
            _ = stat_result;
            break :blk true;
        };
        
        if (exists) {
            return full_path;
        }
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "matchesGlob - exact match" {
    try std.testing.expect(matchesGlob("status", "status"));
    try std.testing.expect(!matchesGlob("status", "statu"));
    try std.testing.expect(!matchesGlob("status", "statusx"));
}

test "matchesGlob - prefix match" {
    try std.testing.expect(matchesGlob("--version", "--*"));
    try std.testing.expect(matchesGlob("-v", "-*"));
    try std.testing.expect(!matchesGlob("version", "--*"));
}

test "extractTargetName - basename only" {
    try std.testing.expectEqualSlices(u8, "git", extractTargetName("git"));
    try std.testing.expectEqualSlices(u8, "git", extractTargetName("/usr/bin/git"));
    try std.testing.expectEqualSlices(u8, "git", extractTargetName("/usr/local/bin/git"));
}

test "extractTargetName - Windows extension" {
    try std.testing.expectEqualSlices(u8, "git", extractTargetName("git.exe"));
    // Note: On Unix, std.fs.path.basename doesn't handle Windows path separators
    // The Windows path test would work correctly on Windows
}

test "CommandLine.parse - simple command with config" {
    const passive = [_][]const u8{ "-*", "--*" };
    const passiveWithArg = [_][]const u8{ "-C", "-c" };
    const target = TargetConfig{
        .executable = "/usr/bin/git",
        .mode = .config,
        .passive = @constCast(&passive),
        .passiveWithArg = @constCast(&passiveWithArg),
    };
    const args = [_][]const u8{"status"};
    const cmd = try CommandLine.parse(std.testing.allocator, &args, &target);
    defer std.testing.allocator.free(cmd.nonFlagArgs);
    try std.testing.expectEqualSlices([]const u8, &[_][]const u8{"status"}, cmd.nonFlagArgs);
}

test "CommandLine.parse - global flag -C with config" {
    const passive = [_][]const u8{ "-*", "--*" };
    const passiveWithArg = [_][]const u8{ "-C", "-c" };
    const target = TargetConfig{
        .executable = "/usr/bin/git",
        .mode = .config,
        .passive = @constCast(&passive),
        .passiveWithArg = @constCast(&passiveWithArg),
    };
    const args = [_][]const u8{ "-C", "/repo", "status" };
    const cmd = try CommandLine.parse(std.testing.allocator, &args, &target);
    defer std.testing.allocator.free(cmd.nonFlagArgs);
    try std.testing.expectEqualSlices([]const u8, &[_][]const u8{"status"}, cmd.nonFlagArgs);
}

test "CommandLine.parse - passthrough command" {
    const passthrough = [_][]const u8{ "--version", "--help" };
    const target = TargetConfig{
        .executable = "/usr/bin/git",
        .mode = .config,
        .passthrough = @constCast(&passthrough),
    };
    const args = [_][]const u8{ "--version" };
    const cmd = try CommandLine.parse(std.testing.allocator, &args, &target);
    // Empty nonFlagArgs signals passthrough
    try std.testing.expectEqual(@as(usize, 0), cmd.nonFlagArgs.len);
}

test "isCommandAllowed - exact match" {
    const rules = [_]Rule{.{ .command = "status", .paramCount = .any }};
    const target = TargetConfig{ .executable = "/usr/bin/git", .allowed = @constCast(&rules) };
    const args = [_][]const u8{"status"};
    try std.testing.expect(try isCommandAllowed(std.testing.allocator, &args, &target));
}

test "isCommandAllowed - no match" {
    const rules = [_]Rule{.{ .command = "status", .paramCount = .any }};
    const target = TargetConfig{ .executable = "/usr/bin/git", .allowed = @constCast(&rules) };
    const args = [_][]const u8{"push"};
    try std.testing.expect(!try isCommandAllowed(std.testing.allocator, &args, &target));
}

test "isCommandAllowed - paramCount match" {
    const rules = [_]Rule{.{ .command = "branch", .paramCount = .{ .exact = 0 } }};
    const target = TargetConfig{ .executable = "/usr/bin/git", .allowed = @constCast(&rules) };
    const args = [_][]const u8{"branch"};
    try std.testing.expect(try isCommandAllowed(std.testing.allocator, &args, &target));
}

test "isCommandAllowed - paramCount mismatch" {
    const rules = [_]Rule{.{ .command = "branch", .paramCount = .{ .exact = 0 } }};
    const target = TargetConfig{ .executable = "/usr/bin/git", .allowed = @constCast(&rules) };
    const args = [_][]const u8{ "branch", "feature" };
    try std.testing.expect(!try isCommandAllowed(std.testing.allocator, &args, &target));
}

test "isCommandAllowed - subcommand match" {
    const rules = [_]Rule{
        .{ .command = "remote", .paramCount = .{ .exact = 0 } },
        .{ .command = "remote show", .paramCount = .any },
    };
    const target = TargetConfig{ .executable = "/usr/bin/git", .allowed = @constCast(&rules) };
    const args = [_][]const u8{ "remote", "show", "origin" };
    try std.testing.expect(try isCommandAllowed(std.testing.allocator, &args, &target));
}

test "writeDeniedMessage - policy block text" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeDeniedMessage(&output.writer, "status");

    try std.testing.expectEqualStrings(
        \\POLICY BLOCK: This operation is not permitted by the user's AI policy.
        \\Do not retry, investigate, or attempt workarounds.
        \\Inform the user what you attempted and wait for their instruction.
        \\The policy may change - do not assume future operations will also be blocked.
        \\
    , output.writer.buffered());
}
