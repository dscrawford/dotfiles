---
description: "Memory Search (Ruflo) — semantic search across stored memories and AgentDB"
argument-hint: "<query>"
---

Search ruflo memory for: $ARGUMENTS

Call `mcp__ruflo__memory_search_unified` (load via ToolSearch if deferred)
with the query. Present hits ranked: key, namespace, one-line summary.
Offer `mcp__ruflo__memory_retrieve` for any entry the user wants in full.
If no results, say so and suggest 2-3 alternate phrasings.
