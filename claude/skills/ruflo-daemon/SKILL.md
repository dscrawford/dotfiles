---
name: ruflo-daemon
description: Ruflo background daemon — manage background workers (audit, optimize, consolidate, map, etc.). Use when the user needs background agent workers or daemon management.
argument-hint: "[subcommand] e.g. 'start', 'status', 'trigger -w audit', 'enable map audit optimize'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo daemon — Background Workers

Manage the Node.js-based background worker daemon.

## Commands

### start — Launch Daemon
```bash
# Standard start
timeout 30 ruflo daemon start 2>&1

# Headless workers (E2B sandbox)
timeout 30 ruflo daemon start --headless 2>&1
```

### stop — Shut Down
```bash
timeout 10 ruflo daemon stop 2>&1
```

### status — Check Daemon & Workers
```bash
timeout 10 ruflo daemon status 2>&1
```

### trigger — Run a Specific Worker
```bash
timeout 30 ruflo daemon trigger -w audit 2>&1
timeout 30 ruflo daemon trigger -w optimize 2>&1
timeout 30 ruflo daemon trigger -w consolidate 2>&1
timeout 30 ruflo daemon trigger -w map 2>&1
```

### enable — Toggle Workers
```bash
timeout 10 ruflo daemon enable map audit optimize 2>&1
```

## Available Workers (12)

| Worker | Purpose |
|--------|---------|
| UltraLearn | Deep knowledge acquisition |
| Optimize | Performance suggestions |
| Consolidate | Memory consolidation |
| Audit | Security scanning |
| Map | Codebase mapping |
| DeepDive | Deep code analysis |
| Document | Auto-documentation |
| Refactor | Refactoring detection |
| Benchmark | Performance benchmarking |
| TestGaps | Test coverage analysis |
| Federation | Cross-machine collaboration |
| CostTracker | API cost monitoring |
