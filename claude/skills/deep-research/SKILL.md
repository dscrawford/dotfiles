---
name: deep-research
description: Multi-source deep research using free tools — built-in WebSearch/WebFetch, the open-websearch MCP (no API key), and Jina Reader. Searches the web across multiple engines, synthesizes findings, and delivers cited reports with source attribution. Use when the user wants thorough research on any topic with evidence and citations.
---

# Deep Research

Produce thorough, cited research reports from multiple web sources using only free tools — no paid API keys required.

## When to Activate

- User asks to research any topic in depth
- Competitive analysis, technology evaluation, or market sizing
- Due diligence on companies, investors, or technologies
- Any question requiring synthesis from multiple sources
- User says "research", "deep dive", "investigate", or "what's the current state of"

## Tooling (all free)

| Purpose | Tool | Notes |
|---------|------|-------|
| Primary search | `WebSearch` (built-in) | Included with Claude Code, no key |
| Second-engine search | `search` from the **web-search** MCP (open-websearch) | Multi-engine (DuckDuckGo, Bing, Brave, Startpage), no key; pass `engines` to pick one |
| Read a page (guided) | `WebFetch` (built-in) | Fetches URL, answers a prompt against it |
| Read a page (raw markdown) | Jina Reader via Bash: `curl -s --max-time 30 "https://r.jina.ai/<url>"` | Free without a key (~20 req/min); renders JS-heavy pages (can take ~10s uncached — never omit `--max-time`); add `-H "X-No-Cache: true"` to skip stale snapshots |
| Content extraction fallback | `fetchWebContent` from the web-search MCP | When WebFetch fails or truncates |
| GitHub research | `gh search repos`, `gh search code`, `gh api` | Authenticated CLI, no scraping needed |

Degradation order for reading a source: `WebFetch` → Jina Reader → `fetchWebContent`. If all three fail, note the source as inaccessible rather than guessing its content.

## Workflow

### Step 1: Understand the Goal

Ask 1-2 quick clarifying questions:
- "What's your goal — learning, making a decision, or writing something?"
- "Any specific angle or depth you want?"

If the user says "just research it" — skip ahead with reasonable defaults.

### Step 2: Plan the Research

Break the topic into 3-5 research sub-questions. Example:
- Topic: "Impact of AI on healthcare"
  - What are the main AI applications in healthcare today?
  - What clinical outcomes have been measured?
  - What are the regulatory challenges?
  - What companies are leading this space?
  - What's the market size and growth trajectory?

### Step 3: Execute Multi-Source Search

For EACH sub-question, search with the built-in tool first:

```
WebSearch(query: "<sub-question keywords>")
```

Then cross-check important sub-questions on a second engine to escape single-engine ranking bias:

```
mcp web-search: search(query: "<keywords>", limit: 8)
mcp web-search: search(query: "<keywords>", engines: ["brave"], limit: 5)
```

**Search strategy:**
- Use 2-3 different keyword variations per sub-question
- Mix general and news-focused queries; add the current year for recency
- Use `WebSearch` `allowed_domains` to target authoritative sites (e.g. arxiv.org, sec.gov, docs sites)
- Aim for 15-30 unique sources total
- Prioritize: academic, official, reputable news > blogs > forums
- For software topics, also run `gh search repos` / `gh search code`

### Step 4: Deep-Read Key Sources

Read 3-5 key sources in full for depth. Do not rely only on search snippets.

Guided read (preferred — cheap and targeted):

```
WebFetch(url: "<url>", prompt: "Extract the key claims, data points, and dates relevant to <sub-question>")
```

Raw markdown when you need full text, tables, or the page is JS-heavy:

```bash
curl -s --max-time 30 "https://r.jina.ai/<url>"
```

Keep Jina Reader calls under ~15/min (free tier is rate-limited); space them out or batch the most valuable URLs.

### Step 5: Synthesize and Write Report

Structure the report:

```markdown
# [Topic]: Research Report
*Generated: [date] | Sources: [N] | Confidence: [High/Medium/Low]*

## Executive Summary
[3-5 sentence overview of key findings]

## 1. [First Major Theme]
[Findings with inline citations]
- Key point ([Source Name](url))
- Supporting data ([Source Name](url))

## 2. [Second Major Theme]
...

## 3. [Third Major Theme]
...

## Key Takeaways
- [Actionable insight 1]
- [Actionable insight 2]
- [Actionable insight 3]

## Sources
1. [Title](url) — [one-line summary]
2. ...

## Methodology
Searched [N] queries across web and news. Analyzed [M] sources.
Sub-questions investigated: [list]
```

### Step 6: Deliver

- **Short topics**: Post the full report in chat
- **Long reports**: Post the executive summary + key takeaways, save full report to a file

## Parallel Research with Subagents

For broad topics, use the Agent tool to parallelize:

```
Launch 3 research agents in parallel:
1. Agent 1: Research sub-questions 1-2
2. Agent 2: Research sub-questions 3-4
3. Agent 3: Research sub-question 5 + cross-cutting themes
```

Each agent searches, reads sources, and returns findings with URLs. The main session synthesizes into the final report. For contested or high-stakes claims, add a verification agent prompted to REFUTE each key claim by finding contradicting sources — drop or flag claims that don't survive.

**Concurrency limits (important — the free engines rate-limit bursts):**
- Cap parallel research agents at 3.
- Subagents use built-in `WebSearch`/`WebFetch` only. Reserve the web-search MCP and Jina Reader for the main session, which can pace its own calls — N agents hitting the same scraped engines simultaneously gets everyone blocked, and a blocked scrape stalls until timeout.
- If an MCP search or Jina fetch fails or hangs, don't retry immediately — fall back to the built-in tool for that query and come back later.

## Quality Rules

1. **Every claim needs a source.** No unsourced assertions.
2. **Cross-reference.** If only one source says it, flag it as unverified. Prefer claims confirmed by two engines or two independent sources.
3. **Recency matters.** Prefer sources from the last 12 months.
4. **Acknowledge gaps.** If you couldn't find good info on a sub-question, say so.
5. **No hallucination.** If you don't know, say "insufficient data found."
6. **Separate fact from inference.** Label estimates, projections, and opinions clearly.
7. **Respect rate limits.** Free engines block bursts — space out MCP searches and Jina fetches instead of hammering them.

## Examples

```
"Research the current state of nuclear fusion energy"
"Deep dive into Rust vs Go for backend services in 2026"
"Research the best strategies for bootstrapping a SaaS business"
"What's happening with the US housing market right now?"
"Investigate the competitive landscape for AI code editors"
```
