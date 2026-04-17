# Matching Engine

## Overview

The matching engine determines if a command is allowed based on the target config rules.

## Rule Structure

```json
{
  "command": "remote add",
  "paramCount": "*"
}
```

- `command` - The command path to match (required)
- `paramCount` - Parameter constraint: `"*"`, `"0"`, `"1"`, etc. (required)

In code, `paramCount` is represented as a tagged union:

```zig
const ParamCount = union(enum) {
    any,              // "*" in JSON
    exact: usize,     // "0", "1", etc. in JSON
};
```

## Matching Algorithm

**Longest prefix match:**

```
1. Collect all non-flag args into array
2. For length from args.Length down to 1:
   a. Build candidate path from args[0..length]
   b. Search config for matching command
   c. If found:
      - paramCount = args.Length - length
      - If rule.paramCount is .any: ALLOW
      - If rule.paramCount.exact == paramCount: ALLOW
      - Else: DENY
3. No matching rule found: DENY
```

This allows unlimited command depth - the config author decides granularity.

## Examples

### Config
```json
{
  "targets": {
    "git": {
      "allowed": [
        {"command": "status", "paramCount": "*"},
        {"command": "branch", "paramCount": "0"},
        {"command": "remote", "paramCount": "0"},
        {"command": "remote show", "paramCount": "*"}
      ]
    }
  }
}
```

### Test Cases

| Command | Non-flag Args | Matched Rule | ParamCount | Result |
|---------|---------------|--------------|------------|--------|
| `git status` | `["status"]` | `"status"` | 0 | ALLOW |
| `git status -s` | `["status"]` | `"status"` | 0 | ALLOW |
| `git branch` | `["branch"]` | `"branch"` | 0 | ALLOW |
| `git branch feature` | `["branch", "feature"]` | `"branch"` | 1 | DENY |
| `git remote` | `["remote"]` | `"remote"` | 0 | ALLOW |
| `git remote -v` | `["remote"]` | `"remote"` | 0 | ALLOW |
| `git remote add origin url` | `["remote", "add", "origin", "url"]` | `"remote"` | 3 | DENY |
| `git remote show origin` | `["remote", "show", "origin"]` | `"remote show"` | 1 | ALLOW |
| `git push` | `["push"]` | none | - | DENY |

## Implementation

```zig
fn isCommandAllowed(allocator: std.mem.Allocator, nonFlagArgs: []const []const u8, config: *const TargetConfig) !bool {
    if (nonFlagArgs.len == 0) return false;
    
    const rules = config.allowed orelse return false;
    
    // Try longest match first
    var len: usize = nonFlagArgs.len;
    while (len > 0) : (len -= 1) {
        const candidatePath = std.mem.join(allocator, " ", nonFlagArgs[0..len]) catch |err| {
            return err;
        };
        defer allocator.free(candidatePath);
        
        for (rules) |rule| {
            if (std.mem.eql(u8, rule.command, candidatePath)) {
                const paramCount = nonFlagArgs.len - len;
                return switch (rule.paramCount) {
                    .any => true,
                    .exact => |count| paramCount == count,
                };
            }
        }
    }
    return false;
}
```

## Key Design Decisions

1. **Tagged union for paramCount**: Instead of string comparison, uses `ParamCount` union with `.any` and `.exact` variants
2. **Error propagation**: Returns `!bool` instead of `bool` to properly handle allocation failures
3. **Allocator parameter**: Takes explicit allocator for memory management
4. **Standalone function**: Not wrapped in a struct since it's stateless

## Edge Cases

- **Empty command** (just `git`): DENY (no command to match)
- **Unknown command**: DENY (no rule matches)
- **Case sensitivity**: Commands are case-sensitive (git is case-sensitive)
- **Missing config file**: Error with clear message