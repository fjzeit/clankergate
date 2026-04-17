# ClankerGate

**Source:** `src/main.zig`
**Build:** `build.zig` (project root)
**Tests:** `src/main.zig` (inline tests)

## Overview

ClankerGate is a multi-target command gate that uses `argv[0]` to determine which target to gate. All behavior is driven by JSON configuration. Commands are denied by default; only explicitly allowed commands pass through.

Built in Zig 0.16.

## Public API

```
// Main entry point - invoked via symlinked binary name
pub fn main(init: std.process.Init) !u8;

// Core types
const Mode = enum { config, passthrough, readonly, block, default };
const ParamCount = union(enum) { any, exact: usize };
const Rule = struct { command: []const u8, paramCount: ParamCount };
const TargetConfig = struct {
    executable: []const u8,
    mode: Mode,
    passive: ?[]const []const u8,
    passiveWithArg: ?[]const []const u8,
    passthrough: ?[]const []const u8,
    allowed: ?[]const Rule,
};
const RootConfig = struct { targets: std.StringHashMap(TargetConfig) };

// Key functions
fn matchesGlob(str: []const u8, pattern: []const u8) bool;
fn extractTargetName(argv0: []const u8) []const u8;
fn loadConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) !RootConfig;
fn isCommandAllowed(allocator: std.mem.Allocator, nonFlagArgs: []const []const u8, config: *const TargetConfig) !bool;
fn findOnPath(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, name: []const u8) ?[]const u8;
fn writeConfigJson(writer: *std.Io.Writer, value: std.json.Value) !void;

// CLI functions (when invoked as "clankergate")
fn runCli(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, args_iter: *std.process.Args.Iterator, defaultConfigPath: []const u8) u8;
fn runList(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) u8;
fn runHealthcheck(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, fix: bool, environ_map: std.process.Environ.Map) u8;
fn fixConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, issues: []const HealthIssue) u8;
fn fixConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, issues: []const HealthIssue) u8;
```

## Key Responsibilities

- Extract target name from `argv[0]` (basename, extension stripped)
- Load JSON config from `CLANKERGATE_CONFIG` environment variable
- Parse command line, skipping passive flags based on target config
- Match commands against whitelist rules (longest match first)
- Execute allowed commands via the configured executable path

## Important Behaviors

- `matchesGlob()`: Pattern ending in `*` matches prefix; exact match otherwise
- `extractTargetName()`: Strips directory path and `.exe` extension (Windows)
- `CommandLine.parse()`: Checks `passiveWithArg` before `passive` (flags with args take precedence)
- `isCommandAllowed()`: Uses longest-match strategy for subcommand rules
- Empty `nonFlagArgs` signals a passthrough command was found

## Key Concepts

- **Target**: A command to gate (e.g., `git`, `rm`). Selected via `argv[0]`.
- **Mode**: `config` (whitelist), `passthrough` (allow all), `readonly` (future), `block` (deny all)
- **Passive flags**: Flags to skip during parsing (e.g., `-*`, `--*`)
- **PassiveWithArg**: Flags that take a next argument (e.g., `-C`, `-c`)
- **Passthrough commands**: Always-allowed commands that bypass whitelist (e.g., `--version`)
- **ParamCount**: `*` for any, or exact number of additional parameters

## Dependencies

- `std.json` for config parsing
- `std.process` for argument handling and subprocess execution
- `std.fs.path` for path manipulation

## Usage Example

```
# Create symlink: git -> clankergate
ln -s clankergate git

# Set config path
export CLANKERGATE_CONFIG=/path/to/clankergate.json

# Invoke via symlink
./git status   # Allowed (in whitelist)
./git push     # Blocked (not in whitelist)

# CLI commands
clankergate version                   # Show version (e.g., "0.0.1")
clankergate list                       # List targets in default config
clankergate list /path/to/config.json # List targets in specific config
clankergate healthcheck                # Check default config
clankergate healthcheck fix /tmp/test.json  # Fix specific config
```

## Architecture

```mermaid
flowchart TD
    A[argv0] --> B[extractTargetName]
    B --> C[Lookup target in config]
    C --> D{Mode?}
    D -->|passthrough| E[Execute directly]
    D -->|block| F[Deny]
    D -->|config| G[Parse command line]
    G --> H{Passthrough command?}
    H -->|yes| E
    H -->|no| I[Check whitelist]
    I --> J{Allowed?}
    J -->|yes| E
    J -->|no| F
```

## Config Schema

```json
{
  "targets": {
    "git": {
      "executable": "/usr/bin/git",
      "mode": "config",
      "passive": ["-*", "--*"],
      "passiveWithArg": ["-C", "-c", "--git-dir", "--work-tree"],
      "passthrough": ["--version", "--help"],
      "allowed": [
        {"command": "status", "paramCount": "*"},
        {"command": "branch", "paramCount": "0"}
      ]
    }
  }
}
```

## Gotchas

- Config resolution: `CLANKERGATE_CONFIG` target → default config target → error
- `passiveWithArg` patterns are checked before `passive` patterns
- Target name is extracted from symlink basename, not the actual binary
- Exit code 126 for denied commands (standard for command not executable)