---
name: bug-hunt
description: Clone a repo into a disposable /tmp sandbox with its own HOME and no credentials, review it read-only, then write unit and e2e tests that try to prove the suspected bugs are real. Reports findings with a failing test as evidence; never posts, pushes, or touches the original checkout.
argument-hint: "<repo-url | owner/repo | local path> [ref] [-- focus area]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
---

# Bug Hunt

Review finds *suspects*. A test is what turns a suspect into a bug. This skill does both
in a sandbox, and reports — it changes nothing the user depends on.

## Ground rules

- Everything happens inside the sandbox. Never edit, stage, or run anything in the source
  checkout, even when given a local path.
- **Never post.** Invoke review without `--comment`, `--post`, or `--fix`.
- Never `git push`, open a PR, or `gh` anything mutating. No `git commit` in the clone
  unless the user asks for a patch.
- Leave the sandbox in place and print its path. `/tmp` is swept for you; deleting it by
  hand only throws away the evidence while the user is still reading the report.

## Phase 1: Sandbox and clone

```bash
sandbox=$(mktemp -d /tmp/bug-hunt-XXXXXX)
mkdir -p "$sandbox/home"
git clone --depth 100 "file://$(realpath <local-path>)" "$sandbox/repo"   # local source
git clone --depth 100 <url> "$sandbox/repo"                              # remote source
git -C "$sandbox/repo" checkout <ref>      # if a ref was given
```

A local path needs the `file://` form: git ignores `--depth` for plain local clones (it
says so, on stderr) and links the object stores together instead of copying. `file://`
forces a real transport, so the clone is shallow and shares nothing. `owner/repo` →
`gh repo clone`. Record the HEAD sha; every finding is reported against it.

Nothing to clean up: `systemd-tmpfiles` sweeps `/tmp` on its own. Never `rm -rf` the
sandbox — the user may want to re-run a failing test or read the code behind a finding.

## Phase 1b: Cut the sandbox off from the user

Every command after the clone runs with:

```bash
HOME="$sandbox/home" XDG_CONFIG_HOME="$sandbox/home/.config" XDG_CACHE_HOME="$sandbox/home/.cache" \
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GIT_CONFIG_GLOBAL=/dev/null SSH_AUTH_SOCK= \
  <cmd>
```

A redirected `HOME` is the load-bearing one: it keeps `npm install` lifecycle scripts,
`cargo build.rs`, `pip` and friends out of `~/.ssh`, `~/.claude`, `~/.config/sops`, and
out of the user's caches. Dropping `SSH_AUTH_SOCK` and the git credential helpers means
repo code cannot borrow the user's push rights even if it tries.

For a repo you have reason to distrust, go further and run the build and test phases under
bubblewrap, which is not installed but is one command away:

```bash
nix shell nixpkgs#bubblewrap -c bwrap \
  --unshare-all --share-net --die-with-parent \
  --ro-bind /nix/store /nix/store --proc /proc --dev /dev \
  --bind "$sandbox" "$sandbox" --chdir "$sandbox/repo" \
  --setenv HOME "$sandbox/home" \
  -- <cmd>
```

Drop `--share-net` once dependencies are fetched; a test suite that then fails on network
access is itself worth reporting.

## Phase 2: Enter an isolated environment

First match wins:

| Repo has | Use |
|---|---|
| `flake.nix` with `devShells` | `nix develop --ignore-environment "$sandbox/repo" -c <cmd>` |
| `shell.nix` / `default.nix` | `nix-shell --pure "$sandbox/repo" --run <cmd>` |
| `.envrc` only | read it, then reproduce as `nix shell nixpkgs#…` |
| none | detect the stack and `nix shell nixpkgs#<toolchain> -c <cmd>` |

`--ignore-environment` / `--pure` drop the ambient shell, so the run depends on what the
repo declares rather than on what happens to be installed — which is also how you catch a
repo that only builds because of something in *your* profile.

Never install globally, never `sudo`, never mutate the user's profile. If the repo's own
setup wants network (`npm ci`, `cargo fetch`, `uv sync`), that is fine — it writes into the
sandbox `HOME`, not the user's caches. Say so in the report if a fetch was needed.

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
Repro: `<exact command, including the nix develop/shell wrapper>`
Failing assertion: <the message the test prints>
Cause: <one or two sentences>
Test: `<path in the sandbox>`, source in a fenced block — /tmp gets swept eventually,
      and a confirmed bug should still be readable after it does


## Not reproduced (N)
<suspect — one line on what the test showed instead>

## Untestable (N)
<suspect — what blocks it>

## Verified behavior
<what the passing tests pinned down — the useful by-product, with their source>

Sandbox: <path> — re-run anything from there. Nothing was pushed; the source checkout is
untouched.
```

Lead with confirmed bugs. If nothing is confirmed, say that plainly — "reviewed N
suspects, none reproduced" is a real result, and the tests written along the way are the
deliverable. Offer to open the confirmed ones as a patch or an issue; do not do it unasked.
