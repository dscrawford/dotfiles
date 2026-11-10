# Offloading simple tasks from the main agent to a local model

*2026-08-17. 34 sources; official docs and peer-reviewed papers for core claims;
benchmark numbers are task-specific.*

## Summary

Frontier model plans, judges and edits; the local 8B model transforms, classifies,
summarizes and drafts. Production agents (aider, claude-code-router) use **static
role-based routing** (whole task categories to the cheap model), not learned per-query
routers. Academic routers/cascades report 50–98% cost cuts at near-parity on their
benchmarks. Claude Code has **no native per-call split between Ollama and Anthropic**;
the levers are MCP tools backed by the local model (`local-llm-router`), PreToolUse
input rewriting, subagent `model:` pinning to cheaper hosted tiers, and an external
proxy.

## 1. What qwen3:8b can own

**Safe:**
- **Summarization / gist extraction** ([8B Reality Check](https://moto-westai.github.io/blog/2026/02/23/8b-parameter-reality-check/), [bleap](https://www.bleap.finance/en-us/blog/all-about-qwen-3-8)).
- **Classification / triage / extraction over supplied context**: Qwen3-8B ranked #1 of 12 SLMs across 8 tasks ([distil labs](https://www.distillabs.ai/blog/we-benchmarked-12-small-language-models-across-8-tasks-to-find-the-best-base-model-for-fine-tuning/), single source). Flat JSON schemas are safe, deeply nested ones aren't.
- **Commit messages from diffs**: solved at 7B and even 3B ([mljourney](https://mljourney.com/how-to-generate-git-commit-messages-with-a-local-llm/), [Lobsters](https://lobste.rs/s/ndcp7o/conventional_commit_message_generator)).
- **Embedding / search / reranking, the strongest offload**: Qwen3-Embedding-8B #1 on MTEB multilingual (70.58); Qwen3-Reranker-8B 81.22 on MTEB-Code ([blog](https://qwenlm.github.io/blog/qwen3-embedding/)). Separate checkpoints from qwen3:8b chat.
- Qwen3-8B beats Qwen2.5-14B on over half of benchmarks, with tool calling and a thinking toggle ([blog](https://qwenlm.github.io/blog/qwen3/), [report](https://arxiv.org/html/2505.09388v1)).

**Unsafe:**
- **Autonomous multi-turn agent loops**: small models miss completion/failure states and loop; one source puts the floor at 30B–70B ([8B Reality Check](https://moto-westai.github.io/blog/2026/02/23/8b-parameter-reality-check/)).
- **Multi-step reasoning**: ~27.5% drop for Llama-3.1-8B vs 70B ([Analytics Vidhya](https://www.analyticsvidhya.com/blog/2024/10/complex-reasoning-in-llms/)).
- **Long-context synthesis**: effective context degrades well before the window ([LongBench v2](https://arxiv.org/pdf/2412.15204)).
- **Subtle bugs / security review**: a 35B-class model missed cross-service bugs Claude found ([HN](https://news.ycombinator.com/item?id=48863171)).
- **Negative constraints** ("do X but not Y") (single source; test locally).

## 2. Routing methods

- **Learned routers**: [RouteLLM](https://arxiv.org/abs/2406.18665) (ICLR 2025), up to 85% cost cut at 95% of GPT-4 quality on MT-Bench; [Hybrid LLM](https://openreview.net/pdf?id=8sSqNntaMr), ~40% fewer large-model calls (unverified).
- **Cascades**: [FrugalGPT](https://arxiv.org/abs/2305.05176), cheapest first with a learned escalation score, up to 98%; [AutoMix](https://arxiv.org/abs/2310.12963) (NeurIPS 2024), small model self-verifies and escalates on low confidence, >50%, no training data; Google's [speculative cascades](https://research.google/blog/speculative-cascades-a-hybrid-approach-for-smarter-faster-llm-inference/).
- **Prompt compression**: [LLMLingua-2](https://arxiv.org/pdf/2403.12968), ~3x at ~1 pt QA loss, 0.4–0.5 s overhead; [LongLLMLingua](https://arxiv.org/pdf/2310.06839), +17.1% at 4x on long context.
- **Production**: aider's `--weak-model` does commit messages and history summarization ([options](https://aider.chat/docs/config/options.html)); [claude-code-router](https://github.com/musistudio/claude-code-router) routes `default`/`background`/`think`/`longContext` with per-subagent pinning.

## 3. Claude Code integration points

Per official docs: **hooks cannot reroute model calls**; `ANTHROPIC_BASE_URL` is
process-global; subagent `model:` only picks models at the same endpoint; PostToolUse
**cannot** modify tool output ([hooks](https://code.claude.com/docs/en/hooks),
[model config](https://code.claude.com/docs/en/model-config)). The main token sink is
long context resent every turn; agent teams cost ~7x; haiku background calls are
<$0.04/session ([costs](https://code.claude.com/docs/en/costs)).

Levers, least to most invasive:

1. **Local MCP tools backed by Ollama** (`local-llm-router`): local inference with full
   control over what enters context.
2. **PreToolUse `updatedInput` rewriting**: the costs doc ships a hook that grep-filters
   test output; piping through a local summarizer extends it.
3. **Subagent `model:` / `CLAUDE_CODE_SUBAGENT_MODEL`**: cheaper hosted tiers ([sub-agents](https://code.claude.com/docs/en/sub-agents)).
4. **External proxy**: claude-code-router, or [LiteLLM](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models)
   mapping haiku-class names to Ollama. Ollama v0.14+ speaks the Anthropic Messages API
   (`ANTHROPIC_BASE_URL=http://localhost:11434`) but lacks prompt caching and
   `count_tokens` ([docs](https://docs.ollama.com/api/anthropic-compatibility)). LiteLLM
   PyPI 1.82.7/1.82.8 were reported compromised; pin versions.

Similar projects: [claude-local-offload](https://github.com/ikalinin/claude-local-offload),
[claude-ollama-agents](https://github.com/PratikHotchandani22/claude-ollama-agents);
upstream request [#38698](https://github.com/anthropics/claude-code/issues/38698).

## Takeaways

1. Add single-shot transform tools to `local-llm-mcp` (`summarize_log`, `classify_diff`,
   `draft_commit_message`).
2. A PreToolUse hook that pipes verbose output through `local_model_run`/grep attacks
   the main token sink.
3. Commit messages from the local model (aider's weak-model pattern).
4. Scouts may draft through `local_model_run`, but severity and verdicts stay hosted
   (AutoMix-style escalation).
5. Skip learned routers and proxies: haiku-class background traffic is small.
6. Never route to 8B: agent loops, long-context synthesis, security review, subtle bugs.

Gaps: no 8B benchmark for log analysis or test brainstorming; cost figures are
benchmark-specific, none measured end-to-end in Claude Code.
