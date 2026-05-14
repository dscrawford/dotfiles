---
name: ruflo-issues
description: Ruflo collaborative issue claims — claim, handoff, steal, and rebalance issues across human-agent workflows (ADR-016). Use when coordinating work between agents and humans on issue trackers.
argument-hint: "[subcommand] e.g. 'list', 'claim 123 --agent coder:coder-1', 'board', 'rebalance', 'handoff 123 --to agent:tester:tester-1'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo issues — Collaborative Issue Claims

Manage issue ownership across human-agent workflows (ADR-016).

## Commands

### list — All Claims
```bash
timeout 10 ruflo issues list 2>&1
```

### claim — Take an Issue
```bash
timeout 10 ruflo issues claim 123 --agent coder:coder-1 2>&1
```

### release — Give Up a Claim
```bash
timeout 10 ruflo issues release 123 2>&1
```

### handoff — Transfer to Another Agent/User
```bash
timeout 10 ruflo issues handoff 123 --to agent:tester:tester-1 2>&1
```

### status — Update Claim Status
```bash
timeout 10 ruflo issues status 123 2>&1
```

### stealable — List Available Issues
```bash
timeout 10 ruflo issues stealable 2>&1
```

### steal — Take a Stealable Issue
```bash
timeout 10 ruflo issues steal 123 --agent coder:coder-2 2>&1
```

### load — Agent Load Distribution
```bash
timeout 10 ruflo issues load 2>&1
```

### rebalance — Redistribute Work
```bash
timeout 30 ruflo issues rebalance 2>&1
```

### board — Visual Board View
```bash
timeout 10 ruflo issues board 2>&1
```
