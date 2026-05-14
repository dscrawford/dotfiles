---
name: ruflo-security
description: Ruflo security scanning — CVE detection, threat modeling, secret detection, AI manipulation defense, security audit. Use when the user needs security analysis, vulnerability scanning, or compliance checks.
argument-hint: "[subcommand] e.g. 'scan', 'cve --list', 'secrets', 'defend', 'threats'"
allowed-tools: Bash, Read, Grep, Glob
---

# ruflo security — Security Scanning

Security scanning, CVE detection, threat modeling, and AI defense.

## Commands

### scan — Security Scan
```bash
# Default scan
timeout 30 ruflo security scan 2>&1

# Full depth scan
timeout 120 ruflo security scan --depth full 2>&1

# Scan specific component
timeout 30 ruflo security scan --component auth 2>&1
```

### cve — CVE Vulnerability Check
```bash
timeout 30 ruflo security cve --list 2>&1
```

### threats — Threat Modeling
```bash
timeout 30 ruflo security threats 2>&1
```

### audit — Security Audit
```bash
timeout 30 ruflo security audit 2>&1
```

### secrets — Detect Secrets in Codebase
```bash
timeout 30 ruflo security secrets 2>&1
```

### defend — AI Manipulation Defense
Detect prompt injection, jailbreaks, and PII leakage:
```bash
timeout 30 ruflo security defend 2>&1
```

## Workflow

1. Run full scan before commits: `timeout 120 ruflo security scan --depth full 2>&1`
2. Check for secrets: `timeout 30 ruflo security secrets 2>&1`
3. If issues found, run threat analysis: `timeout 30 ruflo security threats 2>&1`
4. For AI-specific threats: `timeout 30 ruflo security defend 2>&1`
