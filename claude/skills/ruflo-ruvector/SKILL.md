---
name: ruflo-ruvector
description: Ruflo RuVector PostgreSQL bridge — initialize, migrate, benchmark, and optimize vector storage in PostgreSQL. Use when the user needs PostgreSQL-backed vector operations or wants to migrate from SQLite.
argument-hint: "[subcommand] e.g. 'setup', 'init --database mydb', 'import --input memory.json', 'benchmark --vectors 10000'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo ruvector — PostgreSQL Vector Bridge

Manage RuVector PostgreSQL integration for production vector storage.

## Commands

### setup — Docker & SQL Scaffold
```bash
timeout 10 ruflo ruvector setup 2>&1
```

### init — Initialize in PostgreSQL
```bash
timeout 30 ruflo ruvector init --database mydb 2>&1
```

Options: `--host`, `--port`, `--database`, `--user`, `--schema` (default: claude_flow)

### import — Migrate from SQLite/JSON
```bash
timeout 60 ruflo ruvector import --input memory.json 2>&1
```

### migrate — Run DB Migrations
```bash
timeout 30 ruflo ruvector migrate --up 2>&1
```

### status — Connection & Schema Check
```bash
timeout 10 ruflo ruvector status --verbose 2>&1
```

### benchmark — Performance Testing
```bash
timeout 120 ruflo ruvector benchmark --vectors 10000 2>&1
```

### optimize — Analysis & Recommendations
```bash
timeout 30 ruflo ruvector optimize --analyze 2>&1
```

### backup — Backup/Restore
```bash
timeout 60 ruflo ruvector backup --output backup.sql 2>&1
```
