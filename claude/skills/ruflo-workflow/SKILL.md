---
name: ruflo-workflow
description: Ruflo workflow execution — run, validate, and manage workflow templates for automated multi-step tasks. Use when the user needs to execute or manage predefined workflows.
argument-hint: "[subcommand] e.g. 'run -t development --task \"Build feature\"', 'validate -f workflow.yaml', 'list'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo workflow — Workflow Execution

Execute and manage predefined workflow templates.

## Commands

### run — Execute a Workflow
```bash
timeout 120 ruflo workflow run -t development --task "Build feature" 2>&1
timeout 120 ruflo workflow run -t research --task "Investigate API options" 2>&1
```

### validate — Check Workflow Definition
```bash
timeout 10 ruflo workflow validate -f ./workflow.yaml 2>&1
```

### list — Show Available Workflows
```bash
timeout 10 ruflo workflow list 2>&1
```

### status — Check Running Workflow
```bash
timeout 10 ruflo workflow status 2>&1
```

### stop — Cancel Running Workflow
```bash
timeout 10 ruflo workflow stop 2>&1
```

### template — Manage Templates
```bash
timeout 10 ruflo workflow template 2>&1
```
