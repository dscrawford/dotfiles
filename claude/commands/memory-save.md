---
description: "Memory Save (Ruflo) — store a fact in persistent cross-session memory"
argument-hint: "<fact to remember>"
---

Store this in ruflo memory: $ARGUMENTS

Call `mcp__ruflo__memory_store` (load via ToolSearch if deferred): key = a
short kebab-case slug of the fact; value = the fact, with why/how-to-apply
if it is feedback; metadata/namespace carries the type
(user/feedback/project/reference) and a one-line description.
Before storing, run `mcp__ruflo__memory_search_unified` for near-duplicates;
update the existing key instead of creating one. Confirm the stored key.
