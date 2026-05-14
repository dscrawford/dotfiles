---
name: ruflo-autopilot
description: Ruflo autopilot — persistent swarm completion that keeps agents working until all tasks are done. Use when the user needs autonomous task completion, iteration management, or wants agents to work unattended.
argument-hint: "[subcommand] e.g. 'enable', 'status', 'config --max-iterations 100', 'predict', 'check'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo autopilot — Persistent Completion

Keeps agents working until ALL tasks are done. Manages iteration loops,
timeout limits, and autonomous re-engagement.

## Commands

### status — Current State & Progress
```bash
timeout 10 ruflo autopilot status 2>&1
```

### enable / disable
```bash
timeout 10 ruflo autopilot enable 2>&1
timeout 10 ruflo autopilot disable 2>&1
```

### config — Configure Limits
```bash
timeout 10 ruflo autopilot config --max-iterations 100 --timeout 180 2>&1
```

### reset — Clear Iteration Counter
```bash
timeout 10 ruflo autopilot reset 2>&1
```

### log — View Event Log
```bash
timeout 10 ruflo autopilot log 2>&1
```

### learn — Discover Success Patterns
```bash
timeout 30 ruflo autopilot learn 2>&1
```

### history — Past Completion Episodes
```bash
timeout 10 ruflo autopilot history 2>&1
```

### predict — Optimal Next Action
```bash
timeout 30 ruflo autopilot predict 2>&1
```

### check — Completion Check (used by stop hook)
```bash
timeout 10 ruflo autopilot check 2>&1
```
