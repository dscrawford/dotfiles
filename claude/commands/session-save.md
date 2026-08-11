---
description: "Session Save (Ruflo) — snapshot this session's state for later restore"
argument-hint: "[snapshot name, default: project + date]"
---

Save the current session state to ruflo as: $ARGUMENTS (default
`<project>-<topic>` — derive topic from this session's main task).

Call `mcp__ruflo__session_save` (load via ToolSearch if deferred) with the
name. Include in the saved state a 3-5 line summary of: what was being
worked on, decisions made, and next steps. Confirm the snapshot name and
mention `mcp__ruflo__session_restore` / `/memory-search` for retrieval.
