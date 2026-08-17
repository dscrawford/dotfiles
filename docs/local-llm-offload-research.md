# Offloading Simple Tasks from the Main Agent to a Local Model: Research Report
*Generated: 2026-08-17 | Sources: 34 | Confidence: High (official docs + peer-reviewed papers for core claims; benchmark numbers are task-specific)*

## Executive Summary

The research converges on a clear division of labor: frontier model plans, judges, and edits; the local 8B model transforms, classifies, summarizes, and drafts. Production coding-agent practice (aider, claude-code-router) uses **static role-based routing** — assign whole task categories to the cheap model — rather than learned per-query routers, and that's where the biggest wins per unit of complexity are. Academic routing/cascade systems report 50–98% cost reductions at near-parity quality on their benchmarks. Inside Claude Code specifically, there is **no native way to send some calls to Ollama and the rest to Anthropic** — the four workable levers are MCP tools backed by the local model (what local-llm-router already is), PreToolUse input rewriting to shrink tool outputs, subagent `model:` pinning to cheaper hosted tiers, and an external Anthropic-API proxy for a true split.

## 1. What qwen3:8b can safely own

**Safe (multi-source evidence):**
- **Summarization / gist extraction** — reliable and "highly predictable when kept in their lane" ([8B Parameter Reality Check](https://moto-westai.github.io/blog/2026/02/23/8b-parameter-reality-check/), [bleap Qwen3-8B overview](https://www.bleap.finance/en-us/blog/all-about-qwen-3-8)).
- **Classification / triage / extraction over supplied context** — Qwen3-8B ranked #1 base model among 12 SLMs across 8 classification/QA/doc-understanding tasks ([distil labs benchmark](https://www.distillabs.ai/blog/we-benchmarked-12-small-language-models-across-8-tasks-to-find-the-best-base-model-for-fine-tuning/), single source for rankings); flat-schema JSON extraction is safe, deeply nested schemas are not.
- **Commit messages from diffs** — solved at 7B and even 3B; qwen2.5-coder-7B classifies conventional-commit types more accurately than same-size general models ([mljourney guide](https://mljourney.com/how-to-generate-git-commit-messages-with-a-local-llm/), [Lobsters thread](https://lobste.rs/s/ndcp7o/conventional_commit_message_generator)).
- **Embedding / semantic search / reranking — the strongest offload**: Qwen3-Embedding-8B was #1 on MTEB multilingual (70.58); Qwen3-Reranker-8B scored 81.22 on MTEB-Code ([Qwen3-Embedding blog](https://qwenlm.github.io/blog/qwen3-embedding/)). These are separate checkpoints from qwen3:8b chat — pull them separately.
- Qwen3-8B itself is top-of-class: beats Qwen2.5-14B on over half of benchmarks, supports tool calling and a thinking-mode toggle ([Qwen3 blog](https://qwenlm.github.io/blog/qwen3/), [technical report](https://arxiv.org/html/2505.09388v1)).

**Unsafe to delegate (the boundary):**
- **Autonomous multi-turn agent loops** — small models can't reliably recognize completion/failure states; infinite tool-loop failure mode; one source puts the floor for agentic autonomy at 30B–70B ([8B Reality Check](https://moto-westai.github.io/blog/2026/02/23/8b-parameter-reality-check/), single source for the threshold).
- **Multi-step compositional reasoning** — ~27.5% drop for Llama-3.1-8B vs its 70B sibling ([Analytics Vidhya](https://www.analyticsvidhya.com/blog/2024/10/complex-reasoning-in-llms/)).
- **Long-context synthesis** — effective context degrades well before the advertised window ([LongBench v2](https://arxiv.org/pdf/2412.15204)).
- **Subtle bug hunting / security review** — even a 35B-class model missed cross-service bugs Claude found; frontier models found real RCEs where lesser models produced false positives ([HN practitioner thread](https://news.ycombinator.com/item?id=48863171)).
- **Negative constraints** ("do X but not Y") are a specific 8B reliability trap ([8B Reality Check](https://moto-westai.github.io/blog/2026/02/23/8b-parameter-reality-check/), single source — test locally).

## 2. Routing methods from the literature

- **Learned routers**: [RouteLLM](https://arxiv.org/abs/2406.18665) (ICLR 2025) predicts strong-model win rate per query — up to 85% cost reduction at 95% of GPT-4 quality on MT-Bench; routers generalize across model pairs. [Hybrid LLM](https://openreview.net/pdf?id=8sSqNntaMr) frames it as difficulty classification (~40% fewer large-model calls, unverified this session).
- **Cascades with escalation**: [FrugalGPT](https://arxiv.org/abs/2305.05176) — cheapest model first, learned reliability score gates escalation; up to 98% cost reduction (task-specific). [AutoMix](https://arxiv.org/abs/2310.12963) (NeurIPS 2024) — small model answers, few-shot self-verifies, POMDP router escalates on low confidence; >50% cost reduction, no training data needed. Google's speculative cascades blend token-level draft-and-verify with routing ([blog](https://research.google/blog/speculative-cascades-a-hybrid-approach-for-smarter-faster-llm-inference/), not directly verified).
- **Prompt compression by a small model**: [LLMLingua-2](https://arxiv.org/pdf/2403.12968) — BERT-size token-classification compressor, ~3x compression at ~1pt QA loss, 0.4–0.5s overhead; [LongLLMLingua](https://arxiv.org/pdf/2310.06839) got +17.1% *better* results at 4x compression on long context (compression fights lost-in-the-middle).
- **Production practice — static role-based routing**: aider's `--weak-model` handles exactly two jobs (commit messages, chat-history summarization) ([aider options](https://aider.chat/docs/config/options.html)); [claude-code-router](https://github.com/musistudio/claude-code-router) (~37k stars) routes by scenario: `default`, `background`, `think`, `longContext`, with per-subagent pinning. Third-party guides call routing `background` traffic to cheap models "the biggest cost reducer" (no hard numbers).

## 3. Claude Code integration points (what's actually possible)

Confirmed against official docs: **hooks cannot reroute model calls**, `ANTHROPIC_BASE_URL` is process-global ("changes where requests are sent, not which model answers"), subagent `model:` only selects among models at the same endpoint, and PostToolUse **cannot** modify tool output after the fact ([hooks reference](https://code.claude.com/docs/en/hooks), [model config](https://code.claude.com/docs/en/model-config)). Also officially documented: the dominant token sink is long context resent every turn, agent teams cost ~7x, and haiku background calls are minor (<$0.04/session) ([costs doc](https://code.claude.com/docs/en/costs)).

The four levers, in increasing invasiveness:

1. **Local MCP tools backed by Ollama** — the only mechanism that both runs local inference and controls exactly what enters Claude's context. (This is what `local-llm-router` is.)
2. **PreToolUse `updatedInput` rewriting** — officially sanctioned: the costs doc itself ships a hook that rewrites test commands to grep-filter output before it enters context. Piping through a local summarizer is a direct extension.
3. **Subagent `model:` pinning / `CLAUDE_CODE_SUBAGENT_MODEL`** — hosted-but-cheap tier routing (haiku for simple subagents); the official cost lever ([sub-agents doc](https://code.claude.com/docs/en/sub-agents)).
4. **External proxy for a true hosted/local split** — [claude-code-router](https://github.com/musistudio/claude-code-router) scenario routing, or [LiteLLM](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models) mapping haiku-class names → Ollama while sonnet/opus stay on Anthropic. Ollama v0.14+ natively speaks the Anthropic Messages API (`ANTHROPIC_BASE_URL=http://localhost:11434`) but lacks prompt caching and `count_tokens` ([Ollama docs](https://docs.ollama.com/api/anthropic-compatibility)). Security note: LiteLLM PyPI 1.82.7/1.82.8 were reported compromised — pin versions carefully (single source, verify).

Community projects doing exactly this split: [claude-local-offload](https://github.com/ikalinin/claude-local-offload), [claude-ollama-agents](https://github.com/PratikHotchandani22/claude-ollama-agents) ("Claude plans and reviews; Ollama writes"), plus an open upstream feature request for native per-agent providers ([#38698](https://github.com/anthropics/claude-code/issues/38698)).

## Key Takeaways (ranked for this setup)

1. **Extend `local-llm-mcp` with more single-shot transform tools** — `summarize_log`, `classify_diff`, `draft_commit_message` profiles. Highest leverage, zero middleware, already the right architecture.
2. **Add a PreToolUse hook that pipes verbose command output through `local_model_run`/grep** before it enters context — the officially sanctioned pattern; attacks the #1 token sink (tool results resent every turn).
3. **Adopt the aider weak-model pattern**: commit messages from `qwen3:8b` (7B-class evidence says this is solved).
4. **Consider pinning test-scout/performance-scout drafting work through the local model** via their prompts using `local_model_run` — but keep judgment (severity, verdicts) on the hosted model; escalation-on-uncertainty (AutoMix pattern) fits the scout reports' structure.
5. **Skip learned routers and proxies for now** — static role assignment captures most of the win; a LiteLLM/CCR proxy only becomes worth it if you want haiku-class *background* traffic off-host, and official numbers say that traffic is small.
6. **Never route to 8B**: agentic loops, long-context synthesis, security review, subtle bug hunting — the evidence boundary is consistent across sources.

## Gaps

- No direct benchmark found for log analysis or test-case brainstorming at 8B (inferred from summarization/codegen competence).
- CCR's Ollama-for-background support is consistent across blogs but wasn't verified in the current repo README (possibly version-dependent).
- Cost figures (85%, 98%, >50%) are benchmark-specific; no source measured a Claude Code + local-offload workflow end-to-end.

## Methodology

3 parallel research agents (18 searches, 12 deep-reads) + 3 main-session cross-checks on a second engine. Sub-questions: (1) 8B-class task competence boundary, (2) routing/cascade/compression methods, (3) Claude Code integration mechanics and token sinks.
