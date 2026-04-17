ClankerGate is a multi-target command gate that uses `argv[0]` to determine which target to gate. Users create symlinks (or copies on Windows) named after gated tools (e.g., `git → clankergate`) and prepend the directory to PATH only during agent invocation. All behavior is driven by JSON configuration; commands are denied by default and only explicitly allowed commands pass through.

When invoked as `clankergate` directly, it enters CLI mode with subcommands: `version`, `help`, `list [config-path]`, `healthcheck [fix] [config-path]`. Config resolution tries `CLANKERGATE_CONFIG` first (falling back to the default `clankergate.json` alongside the binary if the target is not found or the env var is unset).

Built in Zig 0.16.