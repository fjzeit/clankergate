# ClankerGate

ClankerGate is a command gate for AI coding agents. It sits between your agent and system tools like `git`, intercepting calls and enforcing an allowlist of permitted operations. Commands not on the list are blocked with a clear policy message - no retries, no workarounds.

**Default behaviour:** read-only `git` (status, log, diff, show, branch list, etc.). Everything else is denied.

> **Alpha:** ClankerGate is early-stage software. Testing, feedback, and contributions are welcome and encouraged.

---

## Quick Start - Linux / macOS

### 1. Install

Download the latest release from [Releases](https://github.com/fjzeit/clankergate/releases) and extract it:

```bash
tar -xzf clankergate-0.0.1-linux-x86_64.tar.gz -C ~/.local/bin/
```

This creates:
```
~/.local/bin/clankergate-0.0.1/
  clankergate        ← the binary
  git                ← symlink → clankergate
  clankergate.json   ← default config
```

### 2. Fix Executable Paths

The bundled `clankergate.json` references `/usr/bin/git`. Run `healthcheck fix` once to update it for your machine:

```bash
~/.local/bin/clankergate-0.0.1/clankergate healthcheck fix
```

### 3. Launch Your Agent with ClankerGate Active

Prepend the release directory to PATH **only for the agent process**. Do not add it to your shell profile.

```bash
# GitHub Copilot CLI
PATH=~/.local/bin/clankergate-0.0.1:$PATH copilot

# Claude Code
PATH=~/.local/bin/clankergate-0.0.1:$PATH claude

# etc.
```

The `git` symlink now intercepts all `git` calls from the agent. When the agent process exits, PATH is restored - your normal `git` is unaffected.

**Allowed by default:**
- ✅ `git status`, `git log`, `git diff`, `git show`
- ✅ `git branch` (list only), `git tag` (list only), `git remote` (list only)
- ✅ `git blame`, `git reflog`, `git remote show <name>`
- ❌ `git push`, `git commit`, `git reset`, `git checkout`, and all other write operations

---

## Quick Start - Windows

### 1. Install

Download the latest Windows release from [Releases](https://github.com/fjzeit/clankergate/releases) and unzip it:

```
%LOCALAPPDATA%\clankergate-0.0.1\
  clankergate.exe    ← the binary
  git.exe            ← copy of clankergate.exe
  clankergate.json   ← default config
```

> **Why `git.exe` is a copy, not a symlink:** Windows symlinks require administrator privileges or Developer Mode. Instead, the release ships `git.exe` as a plain copy of `clankergate.exe`. Both binaries are identical - ClankerGate reads `argv[0]` at runtime to determine which tool is being gated, so the filename is what matters, not whether it's a symlink.

To gate additional tools, copy `clankergate.exe` and rename the copy (e.g., `npm.exe`), then add a matching target to your config.

### 2. Fix Executable Paths

The bundled `clankergate.json` references a Unix path (`/usr/bin/git`). Update it for your machine - open a terminal in the install directory and run:

```cmd
clankergate healthcheck fix
```

This rewrites `clankergate.json` with the correct path to `git.exe` as resolved from your PATH (e.g., `C:\Program Files\Git\bin\git.exe`).

### 3. Launch Your Agent with ClankerGate Active

Prepend the release directory to PATH **only for the agent process**. Do not add it permanently to your system PATH.

```cmd
:: GitHub Copilot CLI
cmd /C "set PATH=%LOCALAPPDATA%\clankergate-0.0.1;%PATH% && copilot"

:: Claude Code
cmd /C "set PATH=%LOCALAPPDATA%\clankergate-0.0.1;%PATH% && claude"

:: etc.
```

Or in PowerShell:

```powershell
$env:PATH = "$env:LOCALAPPDATA\clankergate-0.0.1;$env:PATH"; copilot
```

`git.exe` in the release directory now intercepts all `git` calls from the agent. Your system `git` remains untouched once the session ends.

**Allowed by default:**
- ✅ `git status`, `git log`, `git diff`, `git show`
- ✅ `git branch` (list only), `git tag` (list only), `git remote` (list only)
- ✅ `git blame`, `git reflog`, `git remote show <name>`
- ❌ `git push`, `git commit`, `git reset`, `git checkout`, and all other write operations

---

## Blocking Behaviour

When a command is denied, the agent receives exit code `126` and this message on stderr:

```
POLICY BLOCK: This operation is not permitted by the user's AI policy.
Do not retry, investigate, or attempt workarounds.
Inform the user what you attempted and wait for their instruction.
```

---

## CLI Reference

When invoked directly as `clankergate` (not via a symlink):

```bash
clankergate help               # Show help
clankergate list               # List configured targets and their rules
clankergate healthcheck        # Verify executable paths in config match PATH
clankergate healthcheck fix    # Update config with correct executable paths
clankergate version            # Show version
```

### `healthcheck`

The config stores the absolute path to each real executable. If you move the release directory or install on a new machine, those paths may be wrong. `healthcheck` detects mismatches:

```bash
$ clankergate healthcheck
Checking executables...

  git: MISMATCH
    config:  /usr/bin/git
    on PATH: /home/user/.nix-profile/bin/git

Run 'clankergate healthcheck fix' to update config
```

`healthcheck fix` rewrites the config with the correct paths automatically.

---

## Configuration

### Default Config (`clankergate.json`)

Shipped with every release. Provides read-only git access:

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
        {"command": "status",      "paramCount": "*"},
        {"command": "log",         "paramCount": "*"},
        {"command": "diff",        "paramCount": "*"},
        {"command": "show",        "paramCount": "*"},
        {"command": "branch",      "paramCount": "0"},
        {"command": "tag",         "paramCount": "0"},
        {"command": "remote",      "paramCount": "0"},
        {"command": "remote show", "paramCount": "*"},
        {"command": "blame",       "paramCount": "*"},
        {"command": "reflog",      "paramCount": "*"}
      ]
    }
  }
}
```

### Custom Config

Point `CLANKERGATE_CONFIG` at your own config file to extend or replace the defaults:

```bash
export CLANKERGATE_CONFIG=/path/to/my-config.json
PATH=~/.local/bin/clankergate-0.0.1:$PATH claude
```

**Example - allow commits but block pushes:**

```json
{
  "targets": {
    "git": {
      "executable": "/usr/bin/git",
      "mode": "config",
      "passive": ["-*", "--*"],
      "passiveWithArg": ["-C", "-c", "--git-dir", "--work-tree"],
      "passthrough": ["--version", "--help", "-v", "-h"],
      "allowed": [
        {"command": "status", "paramCount": "*"},
        {"command": "log",    "paramCount": "*"},
        {"command": "diff",   "paramCount": "*"},
        {"command": "add",    "paramCount": "*"},
        {"command": "commit", "paramCount": "*"}
      ]
    }
  }
}
```

**Example - gate a second tool (`rm`):**

```json
{
  "targets": {
    "git": { ... },
    "rm": {
      "executable": "/bin/rm",
      "mode": "block"
    }
  }
}
```

Then add a `rm` symlink in the release directory:

```bash
ln -s clankergate ~/.local/bin/clankergate-0.0.1/rm
```

### Config Resolution

For each target invoked, ClankerGate resolves config in this order:

| Condition | Result |
|-----------|--------|
| `CLANKERGATE_CONFIG` has target with `mode != "default"` | Use that config |
| `CLANKERGATE_CONFIG` has target with `mode: "default"` | Fall back to default config |
| `CLANKERGATE_CONFIG` does not have the target | Fall back to default config |
| `CLANKERGATE_CONFIG` not set | Use default config |

---

## Config Reference

### Target Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `executable` | string | Yes | Absolute path to the real binary |
| `mode` | string | No | `"config"` (default), `"passthrough"`, `"block"`, `"default"` |
| `passive` | []string | No | Glob patterns for flags to skip during parsing |
| `passiveWithArg` | []string | No | Flags that consume their next argument (also skipped) |
| `passthrough` | []string | No | Commands that always pass through, bypassing the allowlist |
| `allowed` | []Rule | No | Allowlist rules (used when `mode` is `"config"`) |

### Modes

| Mode | Behaviour |
|------|-----------|
| `"config"` | Evaluate `allowed` rules; deny anything not matched |
| `"passthrough"` | Allow all commands unconditionally |
| `"block"` | Deny all commands unconditionally |
| `"default"` | Ignore this entry and use the default config instead |

### Rule Fields

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | Command path to match (e.g. `"status"`, `"remote add"`) |
| `paramCount` | string | `"*"` (any), `"0"`, `"1"`, `"2"`, … (exact count) |

### Matching

Rules use **longest-prefix matching** on non-flag arguments. Flags matching `passive` patterns are stripped before matching; flags matching `passiveWithArg` patterns consume their next argument too.

```
git -C /repo remote show origin
      │
      ▼ strip passive flags: ["-C", "/repo"]
      non-flag args: ["remote", "show", "origin"]
      │
      ▼ try "remote show origin" → no rule
      ▼ try "remote show"        → matches! paramCount = 1 ("origin") → ALLOW
```

| Rule | Command | Result |
|------|---------|--------|
| `{"command": "branch", "paramCount": "0"}` | `git branch` | ✅ Allow |
| `{"command": "branch", "paramCount": "0"}` | `git branch feature` | ❌ Deny (1 param) |
| `{"command": "branch", "paramCount": "*"}` | `git branch feature` | ✅ Allow |
| `{"command": "remote show", "paramCount": "*"}` | `git remote show origin` | ✅ Allow |
| _(no rule)_ | `git push` | ❌ Deny |

### Glob Patterns

Used in `passive` and `passthrough`:

| Pattern | Matches |
|---------|---------|
| `"-*"` | Any flag starting with `-` (including `--version`, `--help`) |
| `"--*"` | Any long flag starting with `--` |
| `"--version"` | `--version` exactly |

> **Note:** `"-*"` matches long flags too. List `passiveWithArg` entries before `passive` - more specific patterns should come first.

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CLANKERGATE_CONFIG` | No | Path to a JSON config file. Defaults to `clankergate.json` in the same directory as the `clankergate` binary. |

## Exit Codes

| Code | Meaning |
|------|---------|
| `126` | Command denied by policy |
| other | Exit code forwarded from the real executable |

---

## How It Works

ClankerGate uses `argv[0]` to identify which tool is being invoked - the same trick used by [BusyBox](https://busybox.net/). You create a symlink named `git` (or any other tool) pointing to the `clankergate` binary. When your agent calls `git`, the symlink is resolved, ClankerGate intercepts the call, checks the command against its config, and either passes it through to the real binary or blocks it.

```
agent calls: git push origin main
                    │
        ┌───────────▼────────────┐
        │      clankergate       │  ← argv[0] = "git"
        │   checks config rules  │
        └───────────┬────────────┘
                    │
          ┌─────────┴──────────────────────┐
          │                                │
        ALLOW                            BLOCK
          │                                │
/usr/bin/git push origin main    exit 126 + policy message
```

The release directory **must not** be on your permanent `PATH`. It is prepended only when launching an agent session, so interception is scoped to that session alone.

---

## Building from Source

Requires [Zig](https://ziglang.org/) 0.16.

```bash
git clone https://github.com/fjzeit/clankergate
cd clankergate
zig build -Doptimize=ReleaseSmall
# Output: zig-out/bin/clankergate  +  zig-out/bin/clankergate.json
```

Create symlinks for tools you want to gate:

```bash
cd zig-out/bin
ln -s clankergate git
ln -s clankergate rm
```

Run tests:

```bash
zig build test
```

---

## Contributing

Contributions are welcome. Please open an issue before submitting a large change so the approach can be agreed upfront.

- Keep changes minimal and focused
- All new behaviour requires a test
- Update `clankergate.json` if config schema changes
- CI runs on Linux x64/arm64, macOS x64/arm64, and Windows x64/arm64

Follow [@fjzeit on X.com](https://x.com/fjzeit) for updates, or reach out directly.

---

## License

MIT
