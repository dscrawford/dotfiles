---
name: ruflo-providers
description: Ruflo AI provider management — configure, test, and monitor AI providers (Anthropic, OpenAI, Google, etc.). Use when the user needs to manage API keys, test connectivity, or check usage/costs.
argument-hint: "[subcommand] e.g. 'list', 'configure -p openai', 'test --all', 'models', 'usage'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo providers — AI Provider Management

Manage AI providers, models, and configurations.

## Commands

### list — Available Providers
```bash
timeout 10 ruflo providers list 2>&1
```

### configure — Set Up Provider
```bash
timeout 10 ruflo providers configure -p openai 2>&1
timeout 10 ruflo providers configure -p anthropic 2>&1
```

### test — Verify Connectivity
```bash
timeout 30 ruflo providers test --all 2>&1
```

### models — Available Models
```bash
timeout 10 ruflo providers models 2>&1
```

### usage — Costs & Usage
```bash
timeout 10 ruflo providers usage 2>&1
```
