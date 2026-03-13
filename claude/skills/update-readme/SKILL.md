---
name: update-readme
description: Validate and update README.md by verifying each section against the actual codebase. Fixes stale commands, outdated structure trees, incorrect parameters, and missing information.
argument-hint: "[path/to/README.md] or leave blank for ./README.md"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Update README

Validate and update the project README by checking every section against the actual codebase.

## Phase 1: Parse Sections

1. Read the README file (use `$ARGUMENTS` if provided, otherwise `./README.md`)
2. Parse it into logical sections by heading (h2/h3)
3. For each section, note what claims it makes: commands, file paths, parameters, structure, etc.

## Phase 2: Parallel Verification

Launch one Agent per section (or group small related sections). Each agent should:

1. **Commands/code blocks** — Verify that referenced commands, flags, and scripts exist and are correct. Check `flake.nix`, `Makefile`, `package.json`, shell scripts, etc.
2. **File paths and structure trees** — Use Glob to confirm every listed file/directory exists. Flag any that are missing or renamed.
3. **Parameters and configuration** — Grep for parameter names, default values, and type signatures. Confirm they match what the README states.
4. **Links** — Check that relative links point to existing files.
5. **Descriptions** — Read the referenced source files to confirm the README's description of what they do is still accurate.

Each agent returns a list of findings: `[OK]` if accurate, `[STALE]` with the correction if not.

## Phase 3: Apply Fixes

Aggregate findings from all agents. For each `[STALE]` finding:
- Edit the README to fix it
- Do NOT rewrite sections that are `[OK]`
- Do NOT change writing style, tone, or add new sections unless something is missing
- Preserve the existing structure and voice

## Phase 4: Summary

Print a short summary:
- Sections checked
- Issues found and fixed
- Any sections that could not be verified (e.g., external links)
