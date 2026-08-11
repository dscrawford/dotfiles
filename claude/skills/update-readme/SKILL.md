---
name: update-readme
description: Validate and update README.md by verifying each section against the actual codebase. Fixes stale commands, outdated structure trees, incorrect parameters, and missing information.
argument-hint: "[path/to/README.md] or leave blank for ./README.md"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Update README

## Phase 1: Parse Sections

Read the README (`$ARGUMENTS` path, else `./README.md`); split by h2/h3 heading; list each section's claims (commands, file paths, parameters, structure, etc.).

## Phase 2: Parallel Verification

One Agent per section (group small related ones); each checks:

1. **Commands/code blocks** — commands, flags, scripts exist and are correct (`flake.nix`, `Makefile`, `package.json`, shell scripts, etc.).
2. **File paths/structure trees** — Glob every listed file/dir; flag missing or renamed.
3. **Parameters/configuration** — Grep parameter names, default values, type signatures vs the README.
4. **Links** — relative links point to existing files.
5. **Descriptions** — read referenced sources; confirm still accurate.

Return `[OK]` or `[STALE]` + correction.

## Phase 3: Apply Fixes

Fix each `[STALE]`; leave `[OK]` untouched. Never change style/tone/voice, structure, or add sections unless content is missing.

## Phase 4: Summary

Print: sections checked; issues found and fixed; unverifiable sections (e.g., external links).
