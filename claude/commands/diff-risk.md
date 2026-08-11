---
description: "Diff Risk (Ruflo) — LLM-graded risk score and classification for pending changes"
argument-hint: "[git ref to compare against, default HEAD]"
---

Assess the risk of current changes against ref: $ARGUMENTS (default HEAD).

Call `mcp__ruflo__analyze_diff-risk` (load via ToolSearch if deferred) with
that ref; optionally `mcp__ruflo__analyze_diff-classify` for change type.
Report: overall risk + score, the breakdown, and which files drive any
high/critical entries (inspect the diff yourself to name them). If risk is
high or critical, recommend concrete next steps (review, tests, split the
commit) — do not just relay the number.
