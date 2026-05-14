---
name: ruflo-appliance
description: Ruflo RVFA appliance management — build, inspect, verify, extract, run, sign, and publish self-contained appliances. Use when the user needs portable ruflo deployments or appliance packaging.
argument-hint: "[subcommand] e.g. 'build -p cloud', 'inspect -f ruflo.rvf', 'verify -f ruflo.rvf', 'run -f ruflo.rvf'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo appliance — RVFA Appliances

Self-contained ruflo appliance management (build, inspect, verify, extract, run).

## Commands

### build — Create Appliance
```bash
timeout 120 ruflo appliance build -p cloud 2>&1
```

### inspect — View Contents
```bash
timeout 10 ruflo appliance inspect -f ruflo.rvf 2>&1
```

### verify — Integrity Check
```bash
timeout 30 ruflo appliance verify -f ruflo.rvf 2>&1
```

### extract — Unpack Sections
```bash
timeout 30 ruflo appliance extract -f ruflo.rvf 2>&1
```

### run — Boot Appliance
```bash
timeout 120 ruflo appliance run -f ruflo.rvf 2>&1
```

### sign — Ed25519 Signing
```bash
timeout 30 ruflo appliance sign -f ruflo.rvf --generate-keys 2>&1
```

### publish — Upload to IPFS via Pinata
```bash
timeout 60 ruflo appliance publish -f ruflo.rvf 2>&1
```

### update — Hot-Patch Section
```bash
timeout 30 ruflo appliance update -f ruflo.rvf -s ruflo -d ./new-ruflo.bin 2>&1
```
