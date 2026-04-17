# build.zig

**Source:** `build.zig` (project root)

## Overview

Zig build configuration for ClankerGate. Builds the `clankergate` executable and installs the default config file alongside it.

## Public API

```zig
pub fn build(b: *std.Build) void;
```

## Build Options

- `-Dversion=<string>` - Override version string (default: reads from VERSION file)

## Key Responsibilities

- Build `clankergate` executable from `src/main.zig`
- Read version from VERSION file (or `-Dversion` option)
- Pass version to executable via `build_options` module
- Install `clankergate.json` config to `zig-out/bin/`
- Provide `run` step for executing the binary
- Provide `test` step for running unit tests

## Build Steps

```bash
zig build                           # Build with version from VERSION file
zig build -Dversion=1.0.0           # Build with specific version
zig build run                        # Build and run
zig build test                       # Run unit tests
```

## Output

- `zig-out/bin/clankergate` - Main executable
- `zig-out/bin/clankergate.json` - Default config file