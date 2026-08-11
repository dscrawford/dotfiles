---
description: "PII Scan (Ruflo) — check pending changes for secrets and personal data before pushing"
argument-hint: "[path or ref, default: working tree diff]"
---

Scan for PII and secrets in: $ARGUMENTS (default: `git diff HEAD` plus
staged changes).

Gather the text to scan, then call `mcp__ruflo__aidefence_scan` and
`mcp__ruflo__aidefence_has_pii` (load via ToolSearch if deferred).
Report findings with file:line and category (secret, email, key, token,
personal data); state clearly if clean. On any finding, recommend the
fix (remove, env var, sops secret) before any push.
