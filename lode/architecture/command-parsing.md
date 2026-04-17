# Command Parsing

## Overview

ClankerGate parses command lines to extract the command path and parameter count. Parsing is target-specific, using configuration from the selected target.

## Command Structure

```
[target] [passive-flags] <command> [command-flags] [args]
```

## Passive Flags (Skipped)

Flags matching `passive` patterns are skipped during parsing. Flags matching `passiveWithArg` patterns also skip their next argument.

**Example git config:**
```json
{
  "passive": ["-*", "--*"],
  "passiveWithArg": ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"]
}
```

| Flag | Takes Next Arg | Example |
|------|----------------|---------|
| `-C <path>` | Yes | `git -C /repo status` |
| `-c <name>=<value>` | Yes | `git -c user.name=X commit` |
| `--git-dir=<path>` | If no `=` | `git --git-dir .git status` |
| `--work-tree=<path>` | If no `=` | `git --work-tree src status` |

**Parsing order:** `passiveWithArg` is checked before `passive` (flags with args take precedence).

## Passthrough Commands

Commands matching `passthrough` patterns bypass the whitelist entirely:

```json
{
  "passthrough": ["--version", "--help", "-v", "-h"]
}
```

When a passthrough command is detected, `nonFlagArgs` is empty and execution proceeds directly.

## Command Path Extraction

1. Check for passthrough commands first
2. Skip all passive flags and their values
3. Collect all remaining non-flag args into array
4. Find longest matching command path in config

**Examples:**

| Input | Non-flag Args | Possible Matches |
|-------|---------------|------------------|
| `git status` | `["status"]` | `"status"` |
| `git remote add origin url` | `["remote", "add", "origin", "url"]` | `"remote add"`, `"remote"` |
| `git worktree add ../tree main` | `["worktree", "add", "../tree", "main"]` | `"worktree add"`, `"worktree"` |

## Parameter Counting

paramCount = non-flag args after the matched command path.

For `["remote", "add", "origin", "url"]` matching `"remote add"`:
- Command path uses 2 args
- paramCount = 4 - 2 = 2