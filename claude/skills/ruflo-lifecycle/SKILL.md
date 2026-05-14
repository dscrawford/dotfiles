---
name: ruflo-lifecycle
description: Ruflo system lifecycle — init, start, stop, config, doctor, cleanup, migrate, completions, status, plugins, update, progress. Use when managing ruflo installation, configuration, or system health.
argument-hint: "[command] e.g. 'init --wizard', 'start --daemon', 'doctor --fix', 'config get swarm.topology'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo lifecycle — System Management

Manage ruflo installation, startup, configuration, diagnostics, and cleanup.

## init — Initialize Project

```bash
# Interactive wizard
timeout 30 ruflo init wizard 2>&1

# Default init
timeout 30 ruflo init 2>&1

# Full init with all components + auto-start
timeout 60 ruflo init --full --start-all 2>&1

# Minimal init
timeout 30 ruflo init --minimal 2>&1

# Only Claude Code integration (skip runtime)
timeout 30 ruflo init --only-claude 2>&1

# Only runtime (skip .claude/ directory)
timeout 30 ruflo init --skip-claude 2>&1

# With ONNX embeddings
timeout 60 ruflo init --with-embeddings 2>&1

# For OpenAI Codex CLI
timeout 30 ruflo init --codex 2>&1

# Dual-mode (Claude + Codex)
timeout 30 ruflo init --dual 2>&1

# Upgrade existing installation
timeout 30 ruflo init upgrade 2>&1
timeout 30 ruflo init upgrade --settings --verbose 2>&1

# Init only skills or hooks
timeout 30 ruflo init skills --all 2>&1
timeout 30 ruflo init hooks --minimal 2>&1
```

## start / stop — System Lifecycle

```bash
# Start with defaults
timeout 30 ruflo start 2>&1

# Quick start
timeout 30 ruflo start quick 2>&1

# Start as background daemon
timeout 30 ruflo start --daemon 2>&1

# Start with specific topology
timeout 30 ruflo start --topology mesh 2>&1

# Start on custom MCP port
timeout 30 ruflo start --port 3001 2>&1

# Start without MCP server
timeout 30 ruflo start --skip-mcp 2>&1

# Stop / Restart
timeout 10 ruflo start stop 2>&1
timeout 30 ruflo start restart 2>&1
```

## status — System Overview

```bash
timeout 10 ruflo status 2>&1
```

## config — Configuration

```bash
# Initialize config
timeout 10 ruflo config init --v3 2>&1

# Get/Set values
timeout 10 ruflo config get swarm.topology 2>&1
timeout 10 ruflo config set swarm.maxAgents 20 2>&1

# Manage providers
timeout 10 ruflo config providers 2>&1

# Reset to defaults
timeout 10 ruflo config reset 2>&1

# Export/Import
timeout 10 ruflo config export 2>&1
timeout 10 ruflo config import config.json 2>&1
```

## doctor — Diagnostics

```bash
# Full health check
timeout 30 ruflo doctor 2>&1

# With fix suggestions
timeout 30 ruflo doctor --fix 2>&1

# Auto-install missing dependencies
timeout 60 ruflo doctor --install 2>&1

# Check specific component
timeout 10 ruflo doctor -c memory 2>&1
timeout 10 ruflo doctor -c claude 2>&1
timeout 10 ruflo doctor -c version 2>&1
# Components: version, node, npm, config, daemon, memory, api, git, mcp, claude, disk, typescript

# Verbose output
timeout 30 ruflo doctor --verbose 2>&1
```

## cleanup — Remove Artifacts

```bash
# Dry run (default — shows what would be removed)
timeout 10 ruflo cleanup 2>&1

# Actually delete
timeout 30 ruflo cleanup --force 2>&1

# Delete but keep config files
timeout 30 ruflo cleanup --force --keep-config 2>&1
```

## migrate — V2 to V3

```bash
timeout 30 ruflo migrate status 2>&1
timeout 60 ruflo migrate run 2>&1
timeout 30 ruflo migrate verify 2>&1
timeout 30 ruflo migrate rollback 2>&1
```

## completions — Shell Scripts

```bash
timeout 10 ruflo completions bash 2>&1
timeout 10 ruflo completions zsh 2>&1
timeout 10 ruflo completions fish 2>&1
```

## plugins — Plugin Management

```bash
timeout 10 ruflo plugins list 2>&1
timeout 10 ruflo plugins list --installed 2>&1
timeout 30 ruflo plugins install @claude-flow/plugin-name 2>&1
```

## update — Package Updates

```bash
timeout 10 ruflo update check 2>&1
timeout 60 ruflo update all 2>&1
timeout 10 ruflo update history 2>&1
timeout 30 ruflo update rollback 2>&1
```

## progress — V3 Progress

```bash
timeout 10 ruflo progress check 2>&1
timeout 10 ruflo progress summary 2>&1
timeout 10 ruflo progress watch 2>&1
```

## mcp — MCP Server

```bash
# Start MCP server (313 tools)
nohup ruflo mcp start &>/dev/null &

# Start on custom port with HTTP transport
nohup ruflo mcp start --transport http --port 3000 &>/dev/null &
```
