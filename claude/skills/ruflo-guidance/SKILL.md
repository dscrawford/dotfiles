---
name: ruflo-guidance
description: Ruflo guidance control plane — compile CLAUDE.md into policy bundles, retrieve task-relevant shards, enforce gates, optimize structure. Use when managing CLAUDE.md policies or enforcement rules.
argument-hint: "[subcommand] e.g. 'compile', 'retrieve -t \"Fix auth bug\"', 'gates -c \"rm -rf /\"', 'optimize', 'ab-test'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo guidance — CLAUDE.md Policy Engine

Compile, retrieve, enforce, and optimize CLAUDE.md guidance rules.

## Commands

### compile — Build Policy Bundle
Compiles CLAUDE.md into constitution + shards + manifest:
```bash
timeout 30 ruflo guidance compile 2>&1
```

### retrieve — Task-Relevant Shards
Get guidance relevant to a specific task:
```bash
timeout 30 ruflo guidance retrieve -t "Fix auth bug" 2>&1
timeout 30 ruflo guidance retrieve -t "Add new API endpoint" 2>&1
```

### gates — Enforcement Gate Check
Evaluate whether a command passes enforcement gates:
```bash
timeout 10 ruflo guidance gates -c "rm -rf /" 2>&1
timeout 10 ruflo guidance gates -c "git push --force" 2>&1
```

### status — Control Plane Status
```bash
timeout 10 ruflo guidance status 2>&1
```

### optimize — Analyze & Improve CLAUDE.md
```bash
timeout 30 ruflo guidance optimize 2>&1
```

### ab-test — Compare CLAUDE.md Versions
```bash
timeout 60 ruflo guidance ab-test 2>&1
```
