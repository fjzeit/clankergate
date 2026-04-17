# Build Configuration

**Source:** `src/build.zig`

## Overview
Zig build configuration for GitGate. Builds the `git` executable (named to replace real git on PATH) and provides test runner.

## Public API
```bash
zig build          # Build git executable to zig-out/bin/git
zig build test     # Run unit tests
zig build run --   # Run git executable with args
```

## Key Responsibilities
- Build `git` executable from `src/main.zig`
- Provide test step for unit tests
- Standard Zig build options (target, optimize)

## Build Output
- Executable name: `git` (designed to shadow real git on PATH)
- Output location: `zig-out/bin/git`

## Usage Example
```bash
cd src
zig build
./zig-out/bin/git status  # Runs GitGate
```

## Architecture
```mermaid
flowchart LR
    A[main.zig] --> B[build.zig]
    B --> C[zig-out/bin/git]
    B --> D[test runner]
```