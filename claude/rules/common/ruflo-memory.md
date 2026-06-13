# Memory: Use ruflo MCP Tools

This OVERRIDES the default file-based memory behavior (writing
`memory/*.md` files and a `MEMORY.md` index).

## Saving memories

- ALWAYS store memories with `mcp__ruflo__memory_store` (load it via
  ToolSearch first if deferred). Use a key derived from the memory's
  kebab-case slug and put the memory type (user/feedback/project/reference)
  and a one-line description in the metadata/namespace.
- Do NOT create or update `MEMORY.md` or files under the project's
  `memory/` directory.

## Recalling memories

- Search with `mcp__ruflo__memory_search` (or
  `mcp__ruflo__memory_search_unified`) before starting non-trivial tasks
  and when the user references past context.
- Retrieve specific entries with `mcp__ruflo__memory_retrieve`.

## Editing and deleting

- Update an existing memory by re-storing under the same key with
  `mcp__ruflo__memory_store`; delete stale or wrong memories with
  `mcp__ruflo__memory_delete`.

## Fallback

- Only if the ruflo MCP server is unavailable (tools fail or the server
  is disconnected), fall back to the default file-based memory.
