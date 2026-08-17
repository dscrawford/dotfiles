---
name: local-llm-routing
description: Route small, scoped subagent tasks through a self-hosted Ollama model via the local-llm-router MCP server, while keeping the main orchestrator on remote models.
argument-hint: "task text plus optional requested model and profile (general, test-review, security-review)"
---

# Local LLM Routing

Use this skill to keep the main assistant/orchestrator on remote hosted
models while offloading narrow, bounded sub-tasks to a local Ollama model.

Requires the `local-llm-router` MCP server in the current session
(agent-shell wires it automatically; the CLI needs a one-time
`claude mcp add --scope user local-llm-router -- local-llm-mcp`).

## Core behavior

1. Keep orchestration/planning in the main model.
2. Offload small, bounded analysis to the local MCP tools.
3. Pass any upstream model hint as `requestedModel`; the router applies
   `LOCAL_LLM_MODEL_OVERRIDES` and uses the mapped local model if it is
   pulled. Sonnet-tier hints map to the local default; opus hints stay
   unmapped on purpose (security review keeps the top-tier remote model).
4. If no mapped model is available, the router falls back to the default,
   then the configured fallback. It never picks an arbitrary pulled model,
   and provisioning accepts official library tags only (no registry hosts) —
   both guard against prompt-injected model poisoning.

## Local tools (via MCP)

- `local_model_status` — check Ollama reachability, pulled models, and the
  override map.
- `local_model_provision` — pull a model (for example `qwen3:8b`).
- `local_model_run` — run scoped prompts with profile tuning:
  `general`, `test-review`, `security-review`.

## Recommended workflow

```text
1) local_model_status
2) if model missing -> local_model_provision(model)
3) local_model_run(task, requestedModel, profile)
4) return concise synthesis to caller
```

## Example prompts

- "Review this test diff for flaky risks and missing coverage"
  - Use `profile: test-review`
- "Scan this patch for auth and injection issues"
  - Use `profile: security-review`
- "Summarize these logs and suggest next 3 actions"
  - Use `profile: general`

## Notes

- This is a **tool-offload** pattern: the subagent still reasons normally,
  but heavy bounded analysis can be delegated to local inference.
- If Ollama is down, report that clearly and continue remote-only.
