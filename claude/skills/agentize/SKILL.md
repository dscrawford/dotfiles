---
name: agentize
description: Initialize agentic-coding standards on the current repo — generate a tailored AGENTS.md (with CLAUDE.md link), and optionally a scoped .mcp.json, a safety hook, and spec-kit scaffolding. Use when setting up a repo to work well with AI coding agents (Claude Code, Codex, Cursor, Copilot, etc.).
argument-hint: "[--full] [--mcp] [--hook] [--spec-kit] — default generates AGENTS.md + CLAUDE.md link only"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Agentize

Make the current repository "agent-ready": generate the open, tool-agnostic config files that AI coding agents read, tailored to *this* codebase rather than a generic template. The core deliverable is a good `AGENTS.md`; everything else is opt-in.

Standards followed:
- **AGENTS.md** — the open, Linux-Foundation-stewarded format read by Claude Code, Codex, Cursor, Copilot, Gemini CLI, Windsurf, Aider, and 20+ others. It is the single source of truth; `CLAUDE.md` symlinks to it so both ecosystems read the same rules.
- **MCP (Model Context Protocol)** — scoped `.mcp.json` listing only the servers this repo actually needs.
- **Spec-Driven Development** — optional GitHub Spec Kit scaffolding for spec→plan→tasks→implement workflows.

## Argument parsing

Read `$ARGUMENTS` for flags (any combination; order-independent):
- `--full` → do everything: AGENTS.md, CLAUDE.md link, .mcp.json, safety hook, and offer spec-kit.
- `--mcp` → also generate/update `.mcp.json`.
- `--hook` → also add a pre-tool safety hook.
- `--spec-kit` → also run Spec Kit initialization (Phase 5).
- No flags → **default**: Phase 1 (detect) + Phase 2 (AGENTS.md) + Phase 3 (CLAUDE.md link) only.

If unsure what the user wants, do the default and then *offer* the optional phases rather than assuming.

## Phase 1: Detect the project (always)

Never write a generic template — read the repo first. Gather:

1. **Language(s) & package manager** — inspect `pyproject.toml`/`requirements.txt` (Python + uv/poetry/pip), `package.json` (+ lockfile → npm/pnpm/yarn/bun), `go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Gemfile`, `flake.nix`/`.envrc`, etc.
2. **Exact commands** — extract the *real* ones, with flags:
   - Build/compile
   - Install/setup (respect `flake.nix` + direnv if present — the setup command may just be `direnv allow`)
   - Test suite, **and how to run a single test** (agents need this most)
   - Lint / typecheck / format
   - Dev server / run
   Read `package.json` `scripts`, `Makefile`/`justfile`/`Taskfile`, CI workflows (`.github/workflows/*`), and existing `CONTRIBUTING.md`/`README.md` to find them. Prefer commands that already exist over inventing new ones.
3. **Structure & boundaries** — key directories and what lives where; generated/vendored dirs the agent must NOT edit (`dist/`, `build/`, `node_modules/`, `*.generated.*`, lockfiles, migrations); where secrets live (never to be committed).
4. **Conventions that differ from language defaults** — from `.editorconfig`, linter/formatter config, existing code patterns, and any `.cursorrules`/`.cursor/rules`/`.windsurfrules`/existing `CLAUDE.md`. Capture only the *non-obvious* rules (an agent already knows PEP 8; it doesn't know "we use tabs and forbid `default export`").
5. **Monorepo?** — if there are multiple independent packages/apps, plan a root `AGENTS.md` plus per-package nested `AGENTS.md` files (agents read the nearest one).
6. **Existing files** — if `AGENTS.md`, `CLAUDE.md`, `.mcp.json`, or `.cursorrules` already exist, READ them first and *merge/update* rather than overwrite. Migrate content from `.cursorrules`/legacy `CLAUDE.md` into `AGENTS.md`.

Report a one-paragraph summary of what you detected before writing, so the user can correct you.

## Phase 2: Generate AGENTS.md (default)

Write `AGENTS.md` at the repo root. Keep it **concise and high-signal** — GitHub's analysis of 2,500+ repos found short, specific files outperform long ones. Every line should tell the agent something it can't infer. Use this structure (omit sections that don't apply):

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

Guidelines:
- **Imperative, not prose.** "Run `pnpm test -- <file>` for one test," not "You can run tests by…".
- **No aspirational fiction.** Only document commands you verified exist. If you can't find a real test command, say so in the file (`## Test\n_No test suite yet._`) rather than inventing `npm test`.
- For monorepos, keep the root file about cross-cutting rules and put package-specific commands in nested `packages/*/AGENTS.md`.
- If the user has global coding standards (immutability, many-small-files, comprehensive error handling), fold the repo-relevant ones into **Code Style & Conventions** — but keep it about *this* repo.

**Flag the human-judgment parts.** After writing, explicitly tell the user which sections are your best inference and should be reviewed — typically Architecture intent, "why" decisions, and any convention you guessed from limited signal. Auto-generated AGENTS.md files are a strong draft, not a finished artifact.

## Phase 3: Link CLAUDE.md (default)

So Claude Code and the AGENTS.md ecosystem stay in sync from one source:

1. If no `CLAUDE.md` exists → create a symlink: `ln -s AGENTS.md CLAUDE.md`.
2. If a `CLAUDE.md` already exists with real content → do NOT clobber it. Either (a) migrate its unique content into `AGENTS.md` and replace it with the symlink (ask first), or (b) leave it and add a top line pointing to `AGENTS.md`. Ask the user which they prefer.
3. Verify the symlink resolves (`readlink CLAUDE.md`).

Note for the user: symlinks are committed as symlinks in git and work on macOS/Linux; on Windows checkouts they may materialize as a text file containing the path. If the repo targets Windows contributors, offer a thin `CLAUDE.md` stub (`See [AGENTS.md](./AGENTS.md).`) instead of a symlink.

## Phase 4a: Scoped .mcp.json (opt-in: --mcp or --full)

Generate `.mcp.json` listing **only** MCP servers this repo genuinely benefits from — never a kitchen-sink list (each server costs context and adds attack surface). Infer candidates from the stack:
- Postgres/MySQL present → a database MCP server (read-only by default).
- Heavy GitHub workflow → GitHub MCP server.
- Browser/E2E testing → a browser/Playwright MCP server.

Use `${ENV_VAR}` placeholders for any credentials; never inline secrets. If nothing clearly warrants an MCP server, say so and skip the file rather than adding empty scaffolding. Show the user the proposed servers and let them approve before writing.

## Phase 4b: Safety hook (opt-in: --hook or --full)

Add one lightweight guardrail, not a wall of them. A pre-tool-use hook that blocks obviously destructive shell commands (e.g. `rm -rf` outside the repo, force-push to main, editing files under a `Boundaries / Do Not Touch` path) is the highest-value single hook. Place it per the repo's agent (`.claude/settings.json` hooks for Claude Code) and keep it a "seatbelt," not a straitjacket — it should warn/deny narrowly, not remove the agent's agency. Confirm the exact rules with the user before enabling.

## Phase 5: Spec Kit scaffolding (opt-in: --spec-kit or --full, with confirmation)

For teams wanting full spec-driven development, offer GitHub Spec Kit. This pulls a dependency (`uv` + network), so **always confirm before running**:

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
specify init .        # detects the installed agent, drops .specify/ scaffolding
```

It creates a `.specify/` folder (spec/plan/tasks templates + a project `constitution.md`) and agent slash commands. If `uv` isn't installed, tell the user how to get it (`curl -LsSf https://astral.sh/uv/install.sh | sh`) rather than proceeding. If they decline the dependency, note that the `AGENTS.md` already captures the essentials and spec-kit is additive.

## Phase 6: Summary

Report what was created/changed as a short list, then:
- Remind the user to review the **flagged human-judgment sections** of `AGENTS.md`.
- Suggest committing the new files (`git add AGENTS.md CLAUDE.md ...`) but do NOT commit unless asked.
- If any phase was skipped, mention the flag to enable it (`--mcp`, `--hook`, `--spec-kit`, or `--full`).

## Quality checklist

Before declaring done:
- [ ] Every command in `AGENTS.md` actually exists in the repo (verified, not invented).
- [ ] A single-test command is documented.
- [ ] `Boundaries / Do Not Touch` covers generated dirs, lockfiles, and secrets.
- [ ] `CLAUDE.md` resolves to `AGENTS.md` (or the agreed alternative).
- [ ] No secrets inlined anywhere; `.mcp.json` uses env placeholders.
- [ ] Inferred/guessed sections were flagged to the user for review.
- [ ] Existing files were merged, not blindly overwritten.
