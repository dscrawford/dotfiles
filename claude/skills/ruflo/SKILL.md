---
name: ruflo
description: AI agent orchestration — deploy and coordinate specialized agent swarms for complex multi-step tasks. Use when the user needs multi-agent workflows, swarm intelligence, or task decomposition across many agents.
argument-hint: "[command] e.g. 'init', 'agent spawn researcher', 'swarm spawn', 'status'"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# ruflo — Agent Orchestration (v3.5.51)

Launch and manage ruflo agent orchestration from Claude Code.

## Critical: Timeout Wrapping

All ruflo commands MUST use `timeout` to prevent process hangs:

```bash
# Quick lookups (10s): status, list, doctor, config get
timeout 10 ruflo status 2>&1

# Standard operations (30s): search, store, scan, analyze, route
timeout 30 ruflo memory search -q "query" 2>&1

# Long operations (120s): swarm, hive-mind, neural train, benchmark
timeout 120 ruflo swarm init --v3-mode 2>&1

# Persistent services: use nohup + background
nohup ruflo daemon start &>/dev/null &
```

Check output for `[OK]` instead of relying on exit codes.

## ARG_MAX Workaround

For `memory store` with large values (>50KB), truncate first:

```bash
content=$(head -c 50000 large_file.txt)
timeout 30 ruflo memory store -k "key" -v "$content" 2>&1
```

## Initialization

```bash
if [ ! -f .swarm/memory.db ]; then
  timeout 30 ruflo memory init 2>&1
fi
```

## All Commands (35 top-level)

### Primary
| Command | Purpose | Skill |
|---------|---------|-------|
| `init` | Initialize ruflo in project | `/ruflo-lifecycle` |
| `start` | Start orchestration system | `/ruflo-lifecycle` |
| `status` | Show system status | `/ruflo-lifecycle` |
| `agent` | Agent management (spawn, list, stop, metrics) | `/ruflo:swarm-orchestration` |
| `swarm` | Swarm coordination (init, start, scale) | `/ruflo:swarm-orchestration` |
| `memory` | Vector memory (store, search, retrieve) | `/ruflo:agentdb-memory-patterns` |
| `task` | Task management (create, assign, cancel) | `/ruflo:swarm-orchestration` |
| `session` | Session save/restore/export | `/ruflo-session` |
| `mcp` | MCP server management | `/ruflo-lifecycle` |
| `hooks` | Self-learning hooks automation | `/ruflo:hooks-automation` |

### Advanced
| Command | Purpose | Skill |
|---------|---------|-------|
| `neural` | Neural pattern training, MoE, Flash Attention | `/ruflo-neural` |
| `security` | Security scanning, CVE, threat modeling | `/ruflo-security` |
| `performance` | Profiling, benchmarks, optimization | `/ruflo:performance-analysis` |
| `embeddings` | Vector embeddings, semantic search | `/ruflo-embeddings` |
| `hive-mind` | Queen-led consensus swarms | `/ruflo:hive-mind-advanced` |
| `ruvector` | PostgreSQL vector bridge | `/ruflo-ruvector` |
| `guidance` | CLAUDE.md policy compilation & enforcement | `/ruflo-guidance` |
| `autopilot` | Persistent swarm completion | `/ruflo-autopilot` |

### Utility
| Command | Purpose | Skill |
|---------|---------|-------|
| `config` | Configuration management | `/ruflo-lifecycle` |
| `doctor` | System diagnostics | `/ruflo-lifecycle` |
| `daemon` | Background worker management | `/ruflo-daemon` |
| `completions` | Shell completion scripts | `/ruflo-lifecycle` |
| `migrate` | V2 to V3 migration | `/ruflo-lifecycle` |
| `workflow` | Workflow execution | `/ruflo-workflow` |
| `cleanup` | Remove project artifacts | `/ruflo-lifecycle` |

### Analysis
| Command | Purpose | Skill |
|---------|---------|-------|
| `analyze` | Code analysis, diff, complexity, AST | `/ruflo-analyze` |
| `route` | Q-Learning task-to-agent routing | `/ruflo-route` |
| `progress` | V3 implementation progress | `/ruflo-lifecycle` |

### Management
| Command | Purpose | Skill |
|---------|---------|-------|
| `providers` | AI provider management | `/ruflo-providers` |
| `plugins` | Plugin management (IPFS registry) | `/ruflo-lifecycle` |
| `deployment` | Deploy, rollback, environments | `/ruflo-deployment` |
| `claims` | Authorization & access control | `/ruflo-claims` |
| `issues` | Collaborative issue claims | `/ruflo-issues` |
| `update` | Package updates | `/ruflo-lifecycle` |
| `process` | Background process management | `/ruflo-process` |
| `appliance` | RVFA appliance management | `/ruflo-appliance` |

## Bundled Skills (38)

**Swarm:** swarm-orchestration, swarm-advanced, hive-mind-advanced, stream-chain
**AgentDB:** agentdb-advanced, agentdb-learning, agentdb-memory-patterns, agentdb-optimization, agentdb-vector-search
**GitHub:** github-code-review, github-multi-repo, github-project-management, github-release-management, github-workflow-automation
**ReasoningBank:** reasoningbank-agentdb, reasoningbank-intelligence
**Flow Nexus:** flow-nexus-neural, flow-nexus-platform, flow-nexus-swarm
**Development:** pair-programming, browser, hooks-automation, skill-builder, sparc-methodology, agentic-jujutsu
**V3 Architecture:** v3-core-implementation, v3-ddd-architecture, v3-cli-modernization, v3-integration-deep, v3-mcp-optimization, v3-memory-unification, v3-performance-optimization, v3-security-overhaul, v3-swarm-coordination
**Quality:** verification-quality, performance-analysis

## Emacs Integration

See `/ruflo-agent-shell` for controlling ruflo agents from within Emacs agent-shell sessions.

## Execution

1. Ensure memory DB exists (see Initialization)
2. For complex tasks, search memory for context first
3. Run the command via Bash with timeout:

```bash
timeout 30 ruflo $ARGUMENTS 2>&1
```

If no arguments provided:

```bash
timeout 10 ruflo --help 2>&1
```
