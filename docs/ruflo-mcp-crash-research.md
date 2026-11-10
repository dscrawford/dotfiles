# Why the ruflo MCP server dies mid-session

*2026-09-17. Sources: local coredumps, `~/.cache/claude-cli-nodejs/*/mcp-logs-ruflo`,
node 24.19 headers, upstream better-sqlite3 reports. Crash reproduced and fix verified
locally.*

## Summary

Every ruflo "connection closed" is one crash: **node 24.19 aborts better-sqlite3 12.x
during GC**. Not a timeout, OOM or protocol error; only the number of memory tool calls
matters.

| | |
|---|---|
| Symptom | `MCP error -32000: Connection closed` on `memory_store` / `memory_search*`; server gone |
| Trigger | a GC that finalizes a better-sqlite3 `Statement`, ~45–50 memory calls into a server's life |
| Mechanism | node 24.19 backported cleanup hooks into header-only `node::ObjectWrap`; `~ObjectWrap()` calls `RemoveEnvironmentCleanupHook(Isolate::GetCurrent())` with no entered context; node asserts `(env) != nullptr` → `SIGABRT` |
| Why it looks clean | Claude Code sees only the stdio pipe close and logs "closed (cleanly)" |
| Fix | build ruflo against `nodejs_22`, which predates the backport (upstream's fix, better-sqlite3 13.x, is outside ruflo's `^12.9.0`) |
| Second layer | `pkgs/ruflo-mcp` supervises the server, so a crash is one retryable tool error |

## Evidence

```
Command Line: node .../ruflo/bin/ruflo.js mcp start
      Signal: 6 (ABRT)
          #3  node::Assert(node::AssertionInfo const&)
          #4  node::RemoveEnvironmentCleanupHook(v8::Isolate*, void (*)(void*), void*)
          #5  Statement::~Statement()  (better_sqlite3.node)
          #7  v8::internal::GlobalHandles::InvokeFirstPassWeakCallbacks()
          #8  v8::internal::Heap::PerformGarbageCollection(...)
```

Aborts at 20:13:50 and 20:14:01 PDT match `memory_store` failures at 03:13:51 and
03:14:01 UTC. A stdio client looping memory calls gets `SIGABRT` after 46 replies,
every run.

The call comes from node's `include/node/node_object_wrap.h` in 24.19:

```cpp
void RemoveCleanupHook() {
  RemoveEnvironmentCleanupHook(v8::Isolate::GetCurrent(), CleanupHook, this);
}
```

22.23.2's header has no cleanup-hook code. better-sqlite3 13.x moved to N-API and
dropped `ObjectWrap`, but every ruflo dependent declares it optional in `^11`/`^12`.

Same stack upstream: [BetterDesk #377](https://github.com/UNITRONIX/BetterDesk/issues/377),
[cavemem #70](https://github.com/JuliusBrussee/cavemem/issues/70),
[Rhythm #1505](https://github.com/ajhochy/Rhythm/issues/1505),
[rhdh #5359](https://github.com/redhat-developer/rhdh/pull/5359).

| Check | Before | After |
|---|---|---|
| 80 memory calls, one server | `SIGABRT` after 46 | 80/80, exit 0 |
| 120 calls via supervisor, *unfixed* node-24 build | session dead at first abort | 72 results + 48 retryable errors, 3 restarts, session alive |

## The supervisor

`pkgs/ruflo-mcp` owns stdio and runs `ruflo mcp start` as a child. On respawn it
replays the recorded `initialize`, answers in-flight requests with JSON-RPC `-32603`
("retry the call"), drops late responses for ids it already failed, and dispatches
queued requests to the new server. It kills a server silent on a request for
`RUFLO_MCP_TOOL_TIMEOUT_MS` (default 180 s; `memory_search_unified` hangs were seen)
and gives up after `RUFLO_MCP_MAX_RESTARTS` (default 20) in 10 minutes.

## 2026-09-23: SIGSEGV loading sharp (ruflo 3.42.5)

Unrelated crash: `SIGSEGV` on every memory call, faulting in `libvips-cpp.so.8.18.6`
during `dlopen` (from `@huggingface/transformers` importing sharp 0.35.4).

Our build breaks it: `autoPatchelf` adds a program header, and upstream puts `.init`
at `0x25c` right after the nine original headers, so the tenth (`0x238`–`0x270`)
overwrites it and `DT_INIT` jumps into header bytes. libvips 8.17.3 has slack there.

Fix: `pkgs/ruflo` restores the unpatched `libvips*.so*` after autoPatchelf (no RUNPATH
needed; node already loads libstdc++), and an install check renders an image through
every bundled sharp.

| Check | Before | After |
|---|---|---|
| `require('sharp')` 0.35.4 | SIGSEGV | renders PNG |
| install check without the restore | — | build fails, exit 139 |
| memory calls via `ruflo-mcp` | 10/10 SIGSEGV; supervisor hits restart cap at 60 | 120/120, 0 restarts |

## Residual risks

- Node 22 is EOL April 2027. Drop the pin once a ruflo release allows better-sqlite3 13.x.
- A write in the crashing call may or may not have committed; retry is idempotent for
  `memory_store` (same key).
- Only `initialize` is replayed; other client session state (roots, sampling) isn't,
  as Claude Code sends none to ruflo.
