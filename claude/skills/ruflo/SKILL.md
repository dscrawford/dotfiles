---
name: ruflo
description: AI agent orchestration — deploy and coordinate specialized agent swarms for complex multi-step tasks. Use when the user needs multi-agent workflows, swarm intelligence, or task decomposition across many agents.
argument-hint: "[command] e.g. 'init', 'agent spawn researcher', 'swarm spawn', 'status'"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# ruflo — Agent Orchestration

Launch and manage ruflo agent orchestration from Claude Code.

## Commands

- `ruflo init` — Initialize ruflo in current project
- `ruflo agent spawn <type>` — Deploy a specific agent
- `ruflo agent list` — List available agents
- `ruflo swarm spawn` — Launch multi-agent swarm
- `ruflo hive-mind spawn` — Full swarm orchestration
- `ruflo status` — Check system status
- `ruflo memory` — Manage agent memory
- `ruflo mcp start` — Start MCP server (313 tools)
- `ruflo config` — Configuration management

## When to Activate

- User asks for multi-agent orchestration or swarm coordination
- User needs to decompose complex tasks across specialized agents
- User wants to manage agent memory or workflows
- User references ruflo directly

## Execution

Run the command via Bash:

```bash
ruflo $ARGUMENTS
```

If no arguments provided, show available commands:

```bash
ruflo --help
```
