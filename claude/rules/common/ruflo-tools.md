# Ruflo MCP Tools: Use Proactively

Prefer ruflo MCP tools over local skills or hand-rolled equivalents. Load
via ToolSearch when deferred.

- Before committing: `mcp__ruflo__analyze_diff-risk`; surface the score if
  medium or higher.
- Before pushing or publishing anything: `mcp__ruflo__aidefence_scan` and
  `mcp__ruflo__aidefence_has_pii` on the outgoing diff.
- Analyzing changes: `mcp__ruflo__analyze_diff-classify` / `-stats` /
  `-reviewers` instead of ad-hoc diff parsing.
- End of a significant work session: `mcp__ruflo__session_save` with a
  short state summary.
- Memory: see the ruflo-memory rule — `memory_search_unified` before
  non-trivial tasks, `memory_store` for new facts.
