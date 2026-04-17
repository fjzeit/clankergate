# ClankerGate Refactor Plan

## Overview

Transform GitGate into ClankerGate: a multi-target command gate that uses argv[0] to determine which target to gate, with all behavior driven by configuration.

## Goals

1. Rename binary from `git` to `clankergate`
2. Support multiple targets via config (git, rm, etc.)
3. Move all hardcoded "passive" flags/patterns to config
4. Use argv[0] to select target config
5. Ship default config file alongside executable

## Config Schema

```json
{
  "targets": {
    "git": {
      "executable": "/usr/bin/git",
      "mode": "config",
      "passive": ["-*", "--*"],
      "passiveWithArg": ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"],
      "passthrough": ["--version", "--help", "-v", "-h"],
      "allowed": [
        {"command": "status", "paramCount": "*"},
        {"command": "log", "paramCount": "*"},
        {"command": "diff", "paramCount": "*"},
        {"command": "show", "paramCount": "*"},
        {"command": "branch", "paramCount": "0"},
        {"command": "tag", "paramCount": "0"},
        {"command": "remote", "paramCount": "0"},
        {"command": "remote show", "paramCount": "*"},
        {"command": "blame", "paramCount": "*"},
        {"command": "reflog", "paramCount": "*"}
      ]
    }
  }
}
```

### Field Definitions

| Field | Type | Purpose |
|-------|------|---------|
| `executable` | string | Path to the real binary to invoke |
| `mode` | enum | `config`, `passthrough`, `readonly`, `block` |
| `passive` | []string | Flags to skip during parsing (glob patterns) |
| `passiveWithArg` | []string | Flags that take a next argument (skip flag + value) |
| `passthrough` | []string | Always-allowed commands (bypass whitelist) |
| `allowed` | []Rule | Whitelist rules for `config` mode |

### Glob Matching

Simple prefix matching:
- Pattern ending in `*` → matches if argument starts with prefix
- No `*` → exact match required

## Implementation Tasks

### Phase 1: Config Schema

- [x] Define new `TargetConfig` struct with all fields
- [x] Define `RootConfig` struct with `targets` map
- [x] Update JSON parsing to handle nested structure
- [x] Add glob matching function (`matchesGlob`)

### Phase 2: Target Selection

- [x] Extract target name from argv[0] (basename, strip extension)
- [x] Look up target in config
- [x] Return clear error if target not found
- [x] Return clear error if config missing

### Phase 3: Passive Flag Handling

- [x] Replace hardcoded `takesNextArg` with config-driven `passiveWithArg`
- [x] Replace hardcoded flag skipping with config-driven `passive` patterns
- [x] Move `--version`/`--help` logic to `passthrough` config

### Phase 4: Environment Variables

- [x] Replace `GITGATE_GIT` with config's `executable` field
- [x] Replace `GITGATE_CONFIG` with `CLANKERGATE_CONFIG`
- [x] Remove `GITGATE_GIT` support entirely

### Phase 5: Default Config

- [x] Create `clankergate.json` with git read-only defaults
- [x] Update build.zig to copy config to output directory
- [ ] Document config location in README

### Phase 6: Build & Binary

- [x] Rename binary from `git` to `clankergate`
- [x] Update build.zig executable name
- [x] Remove any git-specific naming
- [x] CI: Linux x64 and arm64 build, package as tar.gz
- [x] CI: macOS x64 and arm64 build, package as tar.gz
- [x] CI: Windows x64 and arm64 build, package as zip
- [x] CI: Include clankergate, clankergate.json, git symlink/copy, README.md

### Phase 7: Tests

- [x] Update existing tests for new config structure
- [x] Add tests for glob matching
- [x] Add tests for target selection
- [x] Add tests for passive flag patterns
- [x] Add tests for passthrough commands

### Phase 8: Documentation

- [x] Update lode/summary.md
- [x] Update lode/terminology.md
- [x] Update lode/architecture/*.md
- [x] Update README.md
- [x] Create mint for main.zig

## Error Messages

Clear, actionable errors:

| Condition | Error Message |
|-----------|---------------|
| Config file not found | `Config file not found: <path>` |
| Invalid JSON | `Invalid config JSON: <path>` |
| Unknown target | `Unknown target '<name>'. Available: <list>` |
| Target missing executable | `Target '<name>' missing 'executable' field` |

## Breaking Changes

1. `GITGATE_GIT` → removed (use config `executable`)
2. `GITGATE_CONFIG` → `CLANKERGATE_CONFIG`
3. Config schema completely different
4. Binary name changes from `git` to `clankergate`
5. No hardcoded DEFAULT_RULES - all from config

## Files to Modify

| File | Changes |
|------|---------|
| `src/main.zig` | All implementation changes |
| `src/build.zig` | Binary name, copy default config |
| `README.md` | New docs |
| `lode/*.md` | Architecture updates |
| `mint/src/main.zig.mint` | Create after changes |

## Files to Create

| File | Purpose |
|------|---------|
| `clankergate.json` | Default config (git read-only) |

## Review Checklist

After implementation:
- [x] `zig build` succeeds
- [x] `zig build test` passes
- [x] Manual test (Unix): symlink `git → clankergate`, then `CLANKERGATE_CONFIG=clankergate.json ./git status`
- [ ] Manual test (Windows): copy `clankergate.exe` to `git.exe`, then test invocation
- [x] Manual test: invoke `clankergate` directly shows "Unknown target 'clankergate'" error
- [x] Error messages are clear
- [x] Lode updated
- [x] Mint created