---
name: ruflo-process
description: Ruflo background process management — daemon control, resource monitoring, worker management, signal handling, log viewing. Use when the user needs to manage ruflo background processes or monitor resources.
argument-hint: "[subcommand] e.g. 'daemon --action start', 'monitor --watch', 'workers --action list', 'logs --follow'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo process — Process Management

Background process management, monitoring, and logging.

## Commands

### daemon — Manage Daemon Process
```bash
timeout 30 ruflo process daemon --action start 2>&1
timeout 10 ruflo process daemon --action stop 2>&1
timeout 10 ruflo process daemon --action status 2>&1
```

### monitor — Real-Time Resource Monitoring
```bash
timeout 30 ruflo process monitor --watch 2>&1
```

### workers — Manage Workers
```bash
timeout 10 ruflo process workers --action list 2>&1
```

### signals — Send Signals to Processes
```bash
timeout 10 ruflo process signals 2>&1
```

### logs — View Process Logs
```bash
timeout 30 ruflo process logs --follow 2>&1
```
