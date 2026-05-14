---
name: ruflo-claims
description: Ruflo claims-based authorization — manage permissions, roles, and access control policies for agents and users. Use when the user needs to control agent permissions or manage access policies.
argument-hint: "[subcommand] e.g. 'list', 'check -c swarm:create', 'grant -c agent:spawn -r developer'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo claims — Authorization & Access Control

Claims-based permissions for agents and users.

## Commands

### list — All Claims
```bash
timeout 10 ruflo claims list 2>&1
```

### check — Verify Permission
```bash
timeout 10 ruflo claims check -c swarm:create 2>&1
timeout 10 ruflo claims check -c agent:spawn 2>&1
```

### grant — Assign Claim
```bash
timeout 10 ruflo claims grant -c agent:spawn -r developer 2>&1
```

### revoke — Remove Claim
```bash
timeout 10 ruflo claims revoke -c agent:spawn -r developer 2>&1
```

### roles — Manage Roles
```bash
timeout 10 ruflo claims roles 2>&1
```

### policies — Manage Policies
```bash
timeout 10 ruflo claims policies 2>&1
```
