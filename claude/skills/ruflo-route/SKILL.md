---
name: ruflo-route
description: Ruflo Q-Learning task routing — intelligently assign tasks to optimal agents using reinforcement learning. Use when the user needs smart task-to-agent assignment or wants to understand routing decisions.
argument-hint: "[subcommand] e.g. 'task \"implement feature\"', 'list-agents', 'stats', 'feedback', 'coverage'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo route — Intelligent Task Routing

Q-Learning-based task-to-agent routing for optimal agent selection.

## Commands

### Route a Task
```bash
# Auto-route to best agent
timeout 30 ruflo route task "implement feature" 2>&1

# Force specific agent
timeout 30 ruflo route task "fix bug" --agent coder 2>&1

# Use Q-Learning explicitly
timeout 30 ruflo route task "write tests" --q-learning 2>&1
```

### list-agents — Available Agent Types
```bash
timeout 10 ruflo route list-agents 2>&1
```

### stats — Routing Statistics
```bash
timeout 10 ruflo route stats 2>&1
```

### feedback — Improve Routing
```bash
timeout 10 ruflo route feedback 2>&1
```

### reset — Clear Q-Table
```bash
timeout 10 ruflo route reset 2>&1
```

### export / import — Persist Q-Table
```bash
timeout 10 ruflo route export 2>&1
timeout 10 ruflo route import q-table.json 2>&1
```

### coverage — Test Coverage-Based Routing (ADR-017)
```bash
timeout 30 ruflo route coverage 2>&1
```
