# ClankerGate Terminology

- **Target** - A command to gate (e.g., `git`, `rm`). Selected via `argv[0]` (symlink basename).
- **Command Path** - The command and optional subcommand (e.g., `"status"`, `"remote add"`)
- **ParamCount** - Tagged union for parameter matching: `.any` (wildcard) or `.exact(N)` (exact count)
- **Passive Flags** - Flags to skip during parsing (glob patterns, e.g., `-*`, `--*`)
- **PassiveWithArg** - Flags that take a next argument (e.g., `-C`, `-c`, `--git-dir`)
- **Passthrough Commands** - Always-allowed commands that bypass whitelist (e.g., `--version`, `--help`)
- **Rule** - A whitelist entry with `command` and `paramCount` properties
- **Mode** - Config setting that controls gating behavior: `config`, `passthrough`, `readonly`, `block`, or `default`
- **default mode** - Special mode that ignores the config entry and falls back to the default config
- **CLANKERGATE_CONFIG** - Environment variable pointing to a JSON config file (optional; falls back to `clankergate.json` alongside executable if target not found)
- **ClankerGateError** - Explicit error set for ClankerGate operations (ConfigNotFound, InvalidConfig, UnknownTarget, etc.)
- **RootConfig** - Top-level config struct containing a `targets` map
- **TargetConfig** - Per-target config with `executable`, `mode`, `passive`, `passiveWithArg`, `passthrough`, `allowed`