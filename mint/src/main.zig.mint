# ClankerGate

**Source:** `src/main.zig`
**Tests:** `src/main.zig` (inline tests)

## Overview

ClankerGate is a multi-target command gate that uses `argv[0]` to determine which target to gate. All behavior is driven by JSON configuration. Commands are denied by default; only explicitly allowed commands pass through. When invoked as `clankergate` directly it enters CLI management mode.

Built in Zig 0.16.

## Public API

```zig
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
const HealthIssue = struct { name: []const u8, expected: []const u8, actual: ?[]const u8 };

// Core functions
fn matchesGlob(str: []const u8, pattern: []const u8) bool;
fn extractTargetName(argv0: []const u8) []const u8;
fn loadConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) !RootConfig;
fn isCommandAllowed(allocator: std.mem.Allocator, nonFlagArgs: []const []const u8, config: *const TargetConfig) !bool;
fn executeCommand(allocator: std.mem.Allocator, io: std.Io, executable: []const u8, args: []const []const u8) !u8;
fn findOnPath(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, name: []const u8) ?[]const u8;
fn parseStringArray(allocator: std.mem.Allocator, items: []const std.json.Value) ![]const []const u8;
fn printDeniedMessage(command: []const u8) void;

// CLI mode functions (when invoked as "clankergate")
fn runCli(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map, args_iter: *std.process.Args.Iterator, defaultConfigPath: []const u8) u8;
fn runList(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8) u8;
fn runHealthcheck(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, fix: bool, environ_map: std.process.Environ.Map) u8;
fn fixConfig(allocator: std.mem.Allocator, io: std.Io, configPath: []const u8, issues: []const HealthIssue) u8;

// JSON formatting helpers
fn writeConfigJson(writer: *std.Io.Writer, value: std.json.Value) !void;
fn writeJsonValue(writer: *std.Io.Writer, value: std.json.Value, indent: usize) !void;
fn writeIndent(writer: *std.Io.Writer, indent: usize) !void;
fn writeEscapedString(writer: *std.Io.Writer, s: []const u8) !void;
```

## Key Responsibilities

- Extract target name from `argv[0]` (basename, extension stripped)
- Load JSON config with two-step fallback: `CLANKERGATE_CONFIG` → `clankergate.json` alongside binary
- Parse command line, skipping passive flags based on target config
- Match commands against whitelist rules (longest match first)
- Execute allowed commands via the configured executable path
- Provide CLI management mode (`list`, `healthcheck`, `healthcheck fix`) when invoked as `clankergate`

## Important Behaviors

- `matchesGlob()`: Pattern ending in `*` matches prefix; exact match otherwise
- `extractTargetName()`: Strips directory path and `.exe` extension (Windows)
- `CommandLine.parse()`: Checks `passiveWithArg` before `passive`; passthrough detection scans all args
- `isCommandAllowed()`: Longest-match strategy - tries longest prefix first, works down
- `loadConfig()`: Config resolution - if `CLANKERGATE_CONFIG` is set but target has `mode=default`, falls through to default config
- `runHealthcheck()`: Compares configured `executable` paths against actual locations found on PATH; `fix` flag rewrites config in place
- `printDeniedMessage()`: Emits a POLICY BLOCK message instructing the agent not to retry; `command` param reserved for future use
- Exit code 126 for all denied/blocked commands

## Key Concepts

- **Target**: A command to gate (e.g., `git`). Selected via `argv[0]` basename.
- **Mode**: `config` (whitelist), `passthrough` (allow all), `block` (deny all), `default` (fall through to default config)
- **Passive flags**: Flags to skip during parsing (e.g., `-*`, `--*`)
- **PassiveWithArg**: Flags that consume a next argument (e.g., `-C`, `-c`)
- **Passthrough commands**: Always-allowed commands bypassing whitelist (e.g., `--version`)
- **ParamCount**: `*` for any, or exact count of additional positional parameters
- **CLI mode**: Direct invocation as `clankergate`; manages config rather than gating commands

## Dependencies

- `std.json` - config parsing and serialization
- `std.process` - argument handling, environment, subprocess execution
- `std.fs.path` - path manipulation
- `build_options` - compile-time version string injected by `build.zig`

## Usage Example

```bash
# Gate mode (via symlink)
ln -s clankergate git
export PATH=/path/to/clankergate-dir:$PATH
./git status   # Allowed
./git push     # POLICY BLOCK

# CLI mode
clankergate version
clankergate list
clankergate list /path/to/config.json
clankergate healthcheck
clankergate healthcheck fix /tmp/test.json
```

## Architecture

```mermaid
flowchart TD
    A[argv0] --> B[extractTargetName]
    B --> C{targetName == clankergate?}
    C -->|yes| D[runCli]
    C -->|no| E[Load config with fallback]
    E --> F{Mode?}
    F -->|passthrough| G[executeCommand]
    F -->|block| H[printDeniedMessage / exit 126]
    F -->|config| I[CommandLine.parse]
    I --> J{Passthrough command?}
    J -->|yes| G
    J -->|no| K[isCommandAllowed]
    K -->|allowed| G
    K -->|denied| H
```

```mermaid
flowchart LR
    E1[CLANKERGATE_CONFIG set?] -->|yes| E2[Load custom config]
    E2 --> E3{Target found and mode != default?}
    E3 -->|yes| E4[Use custom target]
    E3 -->|no| E5[Load default config]
    E1 -->|no| E5
    E5 --> E6{Target found?}
    E6 -->|yes| E7[Use default target]
    E6 -->|no| H[Error / exit 126]
```

## Gotchas

- `passiveWithArg` patterns are checked before `passive` - ordering matters in config
- Target name is extracted from the symlink basename, not the real binary path
- The healthcheck `fix` subcommand rewrites the config file in place using a custom JSON formatter that keeps `allowed` arrays compact
- `findOnPath` skips entries where `stat` fails - a missing executable returns `null`, not an error