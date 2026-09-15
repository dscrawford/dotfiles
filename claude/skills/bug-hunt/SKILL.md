---
name: bug-hunt
description: Clone a repo into a throwaway Nix sandbox, review it read-only, then write unit and e2e tests that try to prove the suspected bugs are real. Reports findings with a failing test as evidence; never posts, pushes, or touches the original checkout.
argument-hint: "<repo-url | owner/repo | local path> [ref] [-- focus area]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
---

# Bug Hunt

Review finds *suspects*. A test is what turns a suspect into a bug. This skill does both
in a sandbox, and reports — it changes nothing the user depends on.

## Ground rules

- Everything happens inside the clone. Never edit, stage, or run anything in the source
  checkout, even when given a local path.
- **Never post.** Invoke review without `--comment`, `--post`, or `--fix`.
- Never `git push`, open a PR, or `gh` anything mutating. No `git commit` in the clone
  unless the user asks for a patch.
- Keep the clone when done and print its path. Ask before deleting.

## Phase 1: Clone

```bash
dir=$(mktemp -d /tmp/bug-hunt-XXXXXX)
git clone --depth 100 <url-or-local-path> "$dir/repo"   # local paths clone too, leaving the source untouched
git -C "$dir/repo" checkout <ref>                       # if a ref was given
```

`owner/repo` → `gh repo clone`. Record the HEAD sha; every finding is reported against it.

## Phase 2: Enter an isolated environment

First match wins:

| Repo has | Use |
|---|---|
| `flake.nix` with `devShells` | `nix develop "$dir/repo" -c <cmd>` |
| `shell.nix` / `default.nix` | `nix-shell --run <cmd>` |
| `.envrc` only | read it, then reproduce as `nix shell nixpkgs#…` |
| none | detect the stack and `nix shell nixpkgs#<toolchain> -c <cmd>` |

Never install globally, never `sudo`, never mutate the user's profile. If the repo's own
setup wants network (`npm ci`, `cargo fetch`, `uv sync`), that is fine — it lands in the
clone. Say so in the report if a dependency fetch was needed.

Confirm the environment works by running the repo's existing test suite **first**: a
pre-existing failure invalidates everything downstream, so report it and stop for
instructions rather than blaming your own tests.

## Phase 3: Read-only review

```
Skill(code-review, args: "high")
```

No flags that write. Also run `Agent(security-scout)` and `Agent(test-scout)` in parallel
over the areas the review flags, for coverage gaps worth probing. Merge into one suspect
list, most-severe first, and cap it — roughly the top 8. Drop style-only items; this skill
is about behavior.

## Phase 4: Prove or disprove, with tests

For each suspect, write the smallest test that would fail **if and only if** the bug is
real, in the repo's own framework and directory layout.

- **Unit** for logic, boundaries, error paths: the default.
- **E2E** when the claim is about a user-visible flow — CLI invocation, HTTP route, UI
  path. Use the repo's existing harness (playwright, pytest+httpx, `bats`, …). Do not
  introduce a second framework; if there is none, scaffold the minimal one in the clone
  and say so.

Verdicts, in the report's words:

| Verdict | Requires |
|---|---|
| CONFIRMED | Test fails on unmodified code, and the failure message matches the claimed cause |
| NOT REPRODUCED | Test expresses the claim and passes — the suspect was wrong |
| UNTESTABLE | State exactly what blocks it (needs a cluster, a paid API, a GPU) |

A test that fails for an unrelated reason — wrong fixture, missing env var, your own
typo — is not evidence. Fix the test and re-run before reporting.

Do not fix the bug. If a one-line fix is obvious, put it in the report as a suggestion and
optionally verify it flips the test to green, then revert it.

## Phase 5: Report

```markdown
# Bug hunt: <repo> @ <sha>
Environment: <nix develop | nix shell nixpkgs#…>  |  Baseline suite: <pass/fail, counts>

## Confirmed (N)
### 1. <one-line defect> — `path/file.ext:LINE`
Repro: `<exact command>`
Failing assertion: <the message the test prints>
Cause: <one or two sentences>
Test: `<path to the test you wrote in the clone>`

## Not reproduced (N)
<suspect — one line on what the test showed instead>

## Untestable (N)
<suspect — what blocks it>

## Verified behavior
<what the passing tests now pin down — the useful by-product>

Clone: <path>   (tests live here; nothing was pushed)
```

Lead with confirmed bugs. If nothing is confirmed, say that plainly — "reviewed N
suspects, none reproduced" is a real result, and the tests written along the way are the
deliverable.
