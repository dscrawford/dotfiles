---
name: ruflo-session
description: Ruflo session management — save, restore, export, import agent sessions for continuity across conversations. Use when the user wants to persist or recover agent state.
argument-hint: "[subcommand] e.g. 'list', 'save -n checkpoint-1', 'restore session-123', 'export -o backup.json'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo session — Session Management

Save, restore, and transfer agent session state for continuity.

## Commands

### list — Show All Sessions
```bash
timeout 10 ruflo session list 2>&1
```

### current — Active Session
```bash
timeout 10 ruflo session current 2>&1
```

### save — Checkpoint Current State
```bash
timeout 30 ruflo session save -n "checkpoint-1" 2>&1
```

### restore — Load a Saved Session
```bash
timeout 30 ruflo session restore session-123 2>&1
```

### delete — Remove a Session
```bash
timeout 10 ruflo session delete session-123 2>&1
```

### export — Save to File
```bash
timeout 30 ruflo session export -o backup.json 2>&1
```

### import — Load from File
```bash
timeout 30 ruflo session import backup.json 2>&1
```

## Workflow

1. Check current session: `timeout 10 ruflo session current 2>&1`
2. Save before risky operations: `timeout 30 ruflo session save -n "pre-refactor" 2>&1`
3. If something goes wrong, restore: `timeout 30 ruflo session restore <id> 2>&1`
4. Export for backup: `timeout 30 ruflo session export -o sessions/$(date +%Y%m%d).json 2>&1`
