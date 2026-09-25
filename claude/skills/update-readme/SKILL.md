---
name: update-readme
description: Validate and rewrite README.md so every claim matches the codebase and every section reads in as few words as possible. Fixes stale commands, paths, and parameters; cuts filler, narration, and restated code; keeps every fact.
argument-hint: "[path/to/README.md] or leave blank for ./README.md"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Update README

Goal: a reader answers *what is this, is it for me, how do I start* in under a
minute, and can still find every fact the old README held. Readership roughly
halves with each section after Usage, so the front of the file earns the most
words and the tail the fewest.

## Phase 1: Parse

Read the README (`$ARGUMENTS` path, else `./README.md`). Split by h2/h3. For
each section record two things:

- **Claims** — commands, paths, parameters, defaults, links, structure trees.
- **Facts** — every distinct piece of information a reader could need. This
  ledger is the contract for Phase 3: nothing on it may vanish.

## Phase 2: Verify (parallel)

One Agent per section, small related ones grouped. Each checks claims against
the tree and returns `[OK]` or `[STALE] + correction`:

1. **Commands** — flags, scripts, targets exist (`flake.nix`, `Makefile`, `package.json`, shell scripts).
2. **Paths and trees** — Glob every listed file/dir; flag missing or renamed.
3. **Parameters** — Grep names, defaults, types against source.
4. **Links** — relative links resolve; external links left as unverifiable.
5. **Descriptions** — read the referenced source; confirm the prose still holds.

Also report which files at the repo root or in `docs/` already cover a
section in depth (`AGENTS.md`, `CONTRIBUTING.md`, runbooks). Those become link
targets in Phase 3.

## Phase 3: Rewrite

Apply every `[STALE]` correction, then rewrite each section under these rules.
Rewriting changes words, order, and form. It never changes meaning.

**Order.** Title and one-line description, then why it exists, then quick
start, then usage, then everything else. Move sections to match.

**Budget.** One sentence per fact. A paragraph holds at most four sentences;
if it needs more, it is two paragraphs or a list. A section past Usage that
runs over roughly ten lines gets its detail moved to a linked doc and a
one-line pointer left behind.

**Form.** Choose by content, not habit:

| Content | Form |
|---|---|
| Parallel items (systems, flags, files) | Bulleted list, one line each |
| Name / default / meaning | Table |
| Steps in order | Numbered list |
| A command | Fenced block, language hint, one line of context above it |
| Cause and effect, a constraint, a gotcha | Prose, one or two sentences |

**Cut** on sight:

- Narration of history or process ("I used X to generate this", "was added
  when", "kinda"). The commit log holds that.
- Comments inside code blocks that restate the command. Keep only comments
  that carry a constraint the command does not show.
- The same command shown twice. Keep one copy and link the other spot to it.
- Hedges, apologies, personal asides, and adverbs that add no fact.
- Headings with one line under them. Fold the line into the parent.
- Generic reference lists (links to a tool's own homepage). Keep links the
  reader needs to complete a step.

**Keep**, without exception:

- Every fact on the Phase 1 ledger. A fact may move to a linked doc, a table
  cell, or a code comment. It may not disappear.
- Every constraint that changes what a reader does: an order dependency
  ("`git add -A` before every build"), a platform split, a pinned version and
  why, a known failure and its fix.
- Demos, diagrams, and their regeneration command.
- Terms the codebase uses. Rename nothing.

**Do not** add sections, invent facts, change the project's name or claims,
or reformat code the README quotes from the tree.

When a fact has no home in the shorter README and no linked doc covers it,
create `docs/<topic>.md` for it rather than dropping it, and link that file.

## Phase 4: Check

Reread the result as a stranger. Each h2 must answer its heading in the first
line. Diff the fact ledger against the new file plus any new docs; anything
missing goes back in. Confirm every link still resolves.

## Phase 5: Summary

Print, in this order and nothing else:

- Sections checked, and which were `[STALE]` with the fix applied.
- Word count before and after.
- Facts moved to linked docs, with the target file for each.
- Unverifiable claims (external links, hosts not reachable from here).
