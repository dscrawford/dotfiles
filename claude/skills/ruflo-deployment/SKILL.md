---
name: ruflo-deployment
description: Ruflo deployment management — deploy, rollback, manage environments, view history and logs. Use when the user needs deployment operations or environment management.
argument-hint: "[subcommand] e.g. 'deploy -e prod', 'status', 'rollback -e prod', 'release -v 3.5.0'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo deployment — Deployment Management

Deploy, rollback, and manage environments.

## Commands

### deploy — Deploy to Environment
```bash
timeout 120 ruflo deployment deploy -e prod 2>&1
timeout 120 ruflo deployment deploy -e staging 2>&1
```

### status — All Environments
```bash
timeout 10 ruflo deployment status 2>&1
```

### rollback — Revert Deployment
```bash
timeout 60 ruflo deployment rollback -e prod 2>&1
```

### history — Deployment History
```bash
timeout 10 ruflo deployment history 2>&1
```

### environments — Manage Environments
```bash
timeout 10 ruflo deployment environments 2>&1
```

### logs — Deployment Logs
```bash
timeout 10 ruflo deployment logs 2>&1
```

### release — Create Release
```bash
timeout 60 ruflo deployment release -v 3.5.0 2>&1
```
