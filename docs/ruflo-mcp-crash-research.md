# Why the ruflo MCP server dies mid-session: research report

*Generated: 2026-09-17 | Sources: local coredumps, `~/.cache/claude-cli-nodejs/*/mcp-logs-ruflo`, node 24.19 headers, upstream better-sqlite3 reports | Confidence: High (crash reproduced and fixed, both verified locally)*

## Executive summary

Every "connection closed" from ruflo is the same crash: **node 24.19 aborts
better-sqlite3 12.x during garbage collection**. It is not a timeout, an OOM, or
a protocol error, and nothing in the session state makes it more or less likely —
only the number of memory tool calls does.

| | |
|---|---|
| Symptom | `MCP error -32000: Connection closed` on `memory_store` / `memory_search*`, the whole server gone |
| Trigger | any GC that finalizes a better-sqlite3 `Statement` — in practice ~45–50 memory tool calls into a server's life |
| Mechanism | node 24.19 backported cleanup hooks into the header-only `node::ObjectWrap`; `~ObjectWrap()` calls `RemoveEnvironmentCleanupHook(Isolate::GetCurrent())` with no entered context, and node asserts `(env) != nullptr` → `SIGABRT` |
| Why it looks clean | the abort kills the process, so Claude Code sees only the stdio pipe close and logs "closed (cleanly)" |
| Fix | build ruflo against `nodejs_22`, which predates the backport (upstream's own fix is better-sqlite3 13.x, outside the `^12.9.0` range ruflo pins) |
| Second layer | `pkgs/ruflo-mcp` supervises the server so any future crash is one retryable tool error, not a dead session |

## Evidence

`coredumpctl` had the answer already — the process aborts, it does not exit:

```
Command Line: node .../ruflo/bin/ruflo.js mcp start
      Signal: 6 (ABRT)
          #3  node::Assert(node::AssertionInfo const&)
          #4  node::RemoveEnvironmentCleanupHook(v8::Isolate*, void (*)(void*), void*)
          #5  Statement::~Statement()  (better_sqlite3.node)
          #7  v8::internal::GlobalHandles::InvokeFirstPassWeakCallbacks()
          #8  v8::internal::Heap::PerformGarbageCollection(...)
```

The timestamps line up exactly with the client-side log: two aborts at 20:13:50
and 20:14:01 PDT against two `memory_store` failures at 03:13:51 and 03:14:01
UTC. Reproduced deterministically with a stdio client that issues memory tool
calls in a loop: `SIGABRT` after 46 replies, every run.

`RemoveEnvironmentCleanupHook` is not better-sqlite3's own call. It comes from
node's `include/node/node_object_wrap.h`, which in 24.19 reads:

```cpp
void RemoveCleanupHook() {
  RemoveEnvironmentCleanupHook(v8::Isolate::GetCurrent(), CleanupHook, this);
}
```

The same header in 22.23.2 has no cleanup-hook code at all, which is why the
node pin fixes it. better-sqlite3 13.x moved to N-API and no longer derives from
`ObjectWrap`; it is the upstream fix, but every ruflo dependent declares
`better-sqlite3` as an optional dependency in the `^11`/`^12` range, so taking
13.x means editing the pinned lockfile out of range.

Upstream reports of the identical stack:
[BetterDesk #377](https://github.com/UNITRONIX/BetterDesk/issues/377),
[cavemem #70](https://github.com/JuliusBrussee/cavemem/issues/70),
[Rhythm #1505](https://github.com/ajhochy/Rhythm/issues/1505),
[rhdh #5359](https://github.com/redhat-developer/rhdh/pull/5359).

## Verification

| Check | Before | After |
|---|---|---|
| 80 memory tool calls, one server | `SIGABRT` after 46 | 80/80 replies, exit 0 |
| 120 calls through the supervisor against the *unfixed* node-24 build | session dead after the first abort | 72 results + 48 retryable errors, 3 restarts, session alive |

## The supervisor

`pkgs/ruflo-mcp` owns the stdio transport and keeps `ruflo mcp start` as a
child. It replays the recorded `initialize` on respawn, answers in-flight
requests with JSON-RPC `-32603` ("retry the call"), never lets a second response
reach the client for an id it already failed, and kills a server that has not
answered a dispatched request in `RUFLO_MCP_TOOL_TIMEOUT_MS` (default 180 s —
`memory_search_unified` hangs have been seen in the logs too). It gives up after
`RUFLO_MCP_MAX_RESTARTS` (default 20) restarts in 10 minutes so a boot-loop
cannot spin forever.

Requests that were still queued during a restart are dispatched to the new
server rather than failed, so a crash between a client's write and the server's
read costs nothing.

## 2026-09-23: SIGSEGV loading sharp (ruflo 3.42.5)

A second, unrelated crash: `signal=SIGSEGV` on every `memory_store` /
`memory_search` call. The coredumps show a fault in `libvips-cpp.so.8.18.6`
during `dlopen`, reached from `@huggingface/transformers` importing sharp 0.35.4.

The library is broken by our build, not upstream. `autoPatchelf` adds a
program header; upstream places `.init` at `0x25c`, directly after the nine
original headers, so the tenth (`0x238`–`0x270`) overwrites it and `DT_INIT`
jumps into header bytes. The older libvips 8.17.3 has slack there and survives.

Fix: `pkgs/ruflo` restores the unpatched `libvips*.so*` after autoPatchelf (it
needs no RUNPATH; node already has libstdc++ loaded), and an install check
renders an image through every bundled sharp so the build fails if it recurs.

| Check | Before | After |
|---|---|---|
| `require('sharp')` 0.35.4 | SIGSEGV | loads, renders PNG |
| install check without the restore | — | build fails, exit 139 |
| memory tool calls through `ruflo-mcp` | 10/10 SIGSEGV; at 60 iterations the supervisor hits its restart cap and exits | 120/120 ok, 0 restarts |

## Residual risks

- Node 22 goes EOL in April 2027. The exit is better-sqlite3 13.x: once a ruflo
  release widens the optional-dependency range, drop the `nodejs_22` pin.
- Memory written in the tool call that crashes is lost — the abort happens
  during GC, so the write may or may not have committed. The supervisor's error
  tells the caller to retry, which is idempotent for `memory_store` (same key).
- The supervisor replays only `initialize`; any other client-side session state
  (roots, sampling config) is not restored, because Claude Code does not send
  any to ruflo today.
