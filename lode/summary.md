ClankerGate is a multi-target command gate that uses `argv[0]` to determine which target to gate. Users create symlinks (e.g., `git → clankergate`) and place them on PATH ahead of real executables. All behavior is driven by JSON configuration loaded from `CLANKERGATE_CONFIG`. Commands are denied by default; only explicitly allowed commands pass through.

Built in Zig 0.16.