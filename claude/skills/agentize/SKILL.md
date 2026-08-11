---
name: agentize
description: Initialize agentic-coding standards on the current repo — generate a tailored AGENTS.md (with CLAUDE.md link), and optionally a scoped .mcp.json, a safety hook, and spec-kit scaffolding. Use when setting up a repo to work well with AI coding agents (Claude Code, Codex, Cursor, Copilot, etc.).
argument-hint: "[--full] [--mcp] [--hook] [--spec-kit] — default generates AGENTS.md + CLAUDE.md link only"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Agentize

Generate tool-agnostic agent config files tailored to *this* codebase — never a generic template. Core deliverable: `AGENTS.md`; rest opt-in.

Formats:
- **AGENTS.md** — open, Linux-Foundation-stewarded format read by Claude Code, Codex, Cursor, Copilot, Gemini CLI, Windsurf, Aider, and 20+ others. Single source of truth; `CLAUDE.md` symlinks to it.
- **MCP (Model Context Protocol)** — scoped `.mcp.json`, only servers this repo needs.
- **Spec-Driven Development** — optional GitHub Spec Kit (spec→plan→tasks→implement).

## Arguments

Parse `$ARGUMENTS` flags (combinable, order-independent):

| Flag | Effect |
|------|--------|
| (none) | Default: Phase 1 (detect) + Phase 2 (AGENTS.md) + Phase 3 (CLAUDE.md link) |
| `--mcp` | Also generate/update `.mcp.json` |
| `--hook` | Also add pre-tool safety hook |
| `--spec-kit` | Also run Spec Kit init (Phase 5) |
| `--full` | All of the above (spec-kit offered) |

Unsure → run default, then offer extras.

## Phase 1: Detect (always)

Read the repo first. Gather:

1. **Language(s) & package manager** — `pyproject.toml`/`requirements.txt` (Python + uv/poetry/pip), `package.json` + lockfile (npm/pnpm/yarn/bun), `go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Gemfile`, `flake.nix`/`.envrc`, etc.
2. **Exact commands, with flags** — build; install/setup (direnv/nix: may be just `direnv allow`); test suite **and single-test invocation** (agents need this most); lint/typecheck/format; dev server/run. Sources: `package.json` `scripts`, `Makefile`/`justfile`/`Taskfile`, `.github/workflows/*`, `CONTRIBUTING.md`/`README.md`. Never invent commands.
3. **Structure & boundaries** — key dirs; never-edit dirs (`dist/`, `build/`, `node_modules/`, `*.generated.*`, lockfiles, migrations); secret locations (never committed).
4. **Non-default conventions** — from `.editorconfig`, linter/formatter config, code patterns, `.cursorrules`/`.cursor/rules`/`.windsurfrules`/existing `CLAUDE.md`. Only non-obvious rules (agents know PEP 8; not "tabs, no `default export`").
5. **Monorepo?** — multiple packages → root + nested per-package `AGENTS.md` (agents read the nearest).
6. **Existing `AGENTS.md`/`CLAUDE.md`/`.mcp.json`/`.cursorrules`** — read and merge/update, never overwrite. Migrate `.cursorrules`/legacy `CLAUDE.md` into `AGENTS.md`.

Summarize detection in one paragraph before writing, for user correction.

## Phase 2: Generate AGENTS.md (default)

Write `AGENTS.md` at repo root, concise and high-signal (GitHub, 2,500+ repos: short specific files outperform long). Every line must be non-inferable. Omit inapplicable sections:

```markdown
# <Project Name>

<1–2 sentences: what this is and its stack.>

## Setup
<Exact install/bootstrap commands. If direnv/nix: note `direnv allow`.>

## Build / Run
<Exact commands to build and to run locally.>

## Test
<Command to run the full suite.>
<Command to run a SINGLE test/file — agents need this to iterate cheaply.>

## Lint & Typecheck
<Exact commands. State that these must pass before a change is "done".>

## Code Style & Conventions
<Only rules that differ from language defaults, or are easy to get wrong.
 Immutability preferences, file-size limits, naming, import style, error handling.
 Bullet points, imperative voice.>

## Architecture
<Terse map of key directories and the boundaries between them.
 What each top-level dir is for. Where NOT to put things.>

## Boundaries / Do Not Touch
<Generated dirs, lockfiles, migrations, secrets, vendored code.
 Anything the agent must never edit or commit.>

## Commits & PRs
<Commit message format (e.g. conventional commits), branch naming,
 whether commits must pass CI, PR expectations.>

## Gotchas
<Non-obvious footguns: flaky test setup, required env vars, service deps,
 ordering constraints. This section pays for itself.>
```

- Imperative, not prose: "Run `pnpm test -- <file>` for one test."
- Verified commands only. No test suite → `## Test\n_No test suite yet._`; never invent `npm test`.
- Monorepo: root = cross-cutting rules; package commands in nested `packages/*/AGENTS.md`.
- Fold repo-relevant user global standards (immutability, many-small-files, comprehensive error handling) into **Code Style & Conventions** — repo-specific only.
- Flag inferred sections for user review (Architecture intent, "why" decisions, guessed conventions) — output is a strong draft, not final.

## Phase 3: Link CLAUDE.md (default)

1. No `CLAUDE.md` → `ln -s AGENTS.md CLAUDE.md`.
2. Existing `CLAUDE.md` with real content → never clobber; ask: (a) migrate unique content into `AGENTS.md`, replace with symlink, or (b) keep, adding a top pointer line to `AGENTS.md`.
3. Verify: `readlink CLAUDE.md`.
4. Warn: git commits symlinks as symlinks (fine on macOS/Linux); Windows checkouts may materialize a path-containing text file — for Windows contributors offer a stub `CLAUDE.md` (`See [AGENTS.md](./AGENTS.md).`).

## Phase 4a: Scoped .mcp.json (opt-in: --mcp or --full)

Only servers the repo genuinely benefits from — never kitchen-sink (each costs context and attack surface). Stack → candidates: Postgres/MySQL → database MCP (read-only default); heavy GitHub workflow → GitHub MCP; browser/E2E tests → Playwright/browser MCP. `${ENV_VAR}` placeholders for credentials; never inline secrets. Nothing warranted → skip the file, say so. Get approval on proposed servers before writing.

## Phase 4b: Safety hook (opt-in: --hook or --full)

One lightweight pre-tool-use hook blocking obviously destructive commands: `rm -rf` outside repo, force-push to main, edits under `Boundaries / Do Not Touch` paths. Claude Code: `.claude/settings.json` hooks. Warn/deny narrowly — seatbelt, not straitjacket. Confirm rules with user before enabling.

## Phase 5: Spec Kit scaffolding (opt-in: --spec-kit or --full)

Pulls `uv` + network — **always confirm first**:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
specify init .        # detects the installed agent, drops .specify/ scaffolding
```

Creates `.specify/` (spec/plan/tasks templates + `constitution.md`) and agent slash commands. `uv` missing → `curl -LsSf https://astral.sh/uv/install.sh | sh`, don't proceed. Declined → `AGENTS.md` covers essentials; spec-kit is additive.

## Phase 6: Summary

List created/changed files; remind review of flagged inferred sections; suggest `git add AGENTS.md CLAUDE.md ...` (do NOT commit unless asked); name the flag for each skipped phase (`--mcp`, `--hook`, `--spec-kit`, `--full`).

## Quality checklist

- [ ] Every `AGENTS.md` command verified to exist (not invented).
- [ ] Single-test command documented.
- [ ] `Boundaries / Do Not Touch` covers generated dirs, lockfiles, secrets.
- [ ] `CLAUDE.md` resolves to `AGENTS.md` (or agreed alternative).
- [ ] No secrets inlined; `.mcp.json` uses env placeholders.
- [ ] Inferred sections flagged for review.
- [ ] Existing files merged, not overwritten.
