# Lode Map

## Project Overview
- [summary.md](summary.md) - Project overview
- [terminology.md](terminology.md) - Domain terminology
- [practices.md](practices.md) - Patterns and practices

## Architecture
- [architecture/command-parsing.md](architecture/command-parsing.md) - How commands are parsed
- [architecture/matching-engine.md](architecture/matching-engine.md) - How rules are matched (uses ParamCount tagged union)

## Source Files
- [build.zig](../build.zig) - Zig build configuration (project root, outputs `clankergate` binary)
- [src/main.zig](../src/main.zig) - Main implementation (see mint/src/main.zig.mint)
- [.github/workflows/build.yml](../.github/workflows/build.yml) - CI: builds 6 targets, publishes GitHub Release on `v*` tags