---
name: deep-research
description: Multi-source deep research using free tools — built-in WebSearch/WebFetch, the open-websearch MCP (no API key), and Jina Reader. Searches the web across multiple engines, synthesizes findings, and delivers cited reports with source attribution. Use when the user wants thorough research on any topic with evidence and citations.
---

# Deep Research

Cited, multi-source research reports using free tools only — no paid API keys.

## When to Activate

Use for in-depth topic research; competitive analysis, technology evaluation, market sizing; due diligence on companies/investors/technologies; multi-source synthesis. Triggers: "research", "deep dive", "investigate", "what's the current state of".

## Tooling (all free)

- `WebSearch` (built-in): primary search, no key.
- `search` from the **web-search** MCP (open-websearch): second engine — DuckDuckGo, Bing, Brave, Startpage; no key; `engines` picks one.
- `WebFetch` (built-in): guided read — answers a prompt against a fetched URL.
- Jina Reader via Bash `curl -s --max-time 30 "https://r.jina.ai/<url>"`: raw markdown; free without a key (~20 req/min); renders JS-heavy pages (~10s uncached — never omit `--max-time`); `-H "X-No-Cache: true"` skips stale snapshots.
- `fetchWebContent` (web-search MCP): fallback when WebFetch fails or truncates.
- `gh search repos` / `gh search code` / `gh api`: GitHub research, authenticated CLI.

Reading fallback chain: `WebFetch` → Jina Reader → `fetchWebContent`; if all fail, mark the source inaccessible — never guess.

## Workflow

**1. Goal.** Ask 1-2 clarifiers (learning/decision/writing? angle? depth?); "just research it" ⇒ defaults.

**2. Plan.** 3-5 sub-questions, e.g. "AI in healthcare" → applications; measured clinical outcomes; regulation; leading companies; market size/growth.

**3. Search.** Per sub-question: `WebSearch(query: "<keywords>")`, then cross-check important ones on a second engine (escapes single-engine ranking bias):

```
mcp web-search: search(query: "<keywords>", limit: 8)
mcp web-search: search(query: "<keywords>", engines: ["brave"], limit: 5)
```

- 2-3 keyword variations; mix general + news; add the current year for recency.
- `WebSearch` `allowed_domains` for authoritative sites (arxiv.org, sec.gov, docs sites).
- 15-30 unique sources; academic/official/reputable news > blogs > forums.
- Software: also `gh search repos` / `gh search code`.

**4. Deep-read** 3-5 key sources in full — snippets aren't enough. Guided (preferred):

```
WebFetch(url: "<url>", prompt: "Extract the key claims, data points, and dates relevant to <sub-question>")
```

Full text/tables/JS-heavy:

```bash
curl -s --max-time 30 "https://r.jina.ai/<url>"
```

Jina ≤ ~15/min (free tier rate-limits); space out or batch the most valuable URLs.

**5. Report.**

```markdown
# [Topic]: Research Report
*Generated: [date] | Sources: [N] | Confidence: [High/Medium/Low]*

## Executive Summary
[3-5 sentence overview of key findings]

## 1. [First Major Theme]
[Findings with inline citations]
- Key point ([Source Name](url))
- Supporting data ([Source Name](url))

## 2. [...]

## Key Takeaways
- [Actionable insights]

## Sources
1. [Title](url) — [one-line summary]

## Methodology
Searched [N] queries across web and news. Analyzed [M] sources.
Sub-questions investigated: [list]
```

**6. Deliver.** Short: full report in chat. Long: exec summary + key takeaways in chat, full report to a file.

## Parallel Research with Subagents

Broad topics: split sub-questions across parallel Agent-tool agents (e.g. 1-2 / 3-4 / 5 + cross-cutting); agents return findings with URLs, main session synthesizes. Contested/high-stakes claims: add a verification agent prompted to REFUTE each key claim with contradicting sources; drop or flag claims that don't survive.

**Concurrency limits (important — free engines rate-limit bursts):**
- Max 3 parallel research agents.
- Subagents: built-in `WebSearch`/`WebFetch` only; reserve the web-search MCP and Jina Reader for the main session, which can pace its calls — N agents hitting the same scraped engines at once gets everyone blocked, and a blocked scrape stalls until timeout.
- MCP search or Jina fetch fails/hangs ⇒ no immediate retry; fall back to the built-in tool for that query, revisit later.

## Quality Rules

1. Every claim sourced; no unsourced assertions.
2. Cross-reference: flag single-source claims unverified; prefer two engines or two independent sources.
3. Prefer sources from the last 12 months.
4. State gaps when a sub-question came up thin.
5. Never hallucinate — say "insufficient data found."
6. Separate fact from inference; label estimates, projections, opinions.
7. Respect rate limits: space out MCP searches and Jina fetches, never hammer.

## Examples

```
"Research the current state of nuclear fusion energy"
"Investigate the competitive landscape for AI code editors"
```
