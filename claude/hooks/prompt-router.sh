#!/usr/bin/env bash
# UserPromptSubmit router: CoD-style brevity for easy prompts, a full-
# reasoning guard for hard ones, comment-policy nudge every 5th prompt.
# COD_CLASSIFIER=llm swaps the heuristic for a Haiku call (slower).
set -euo pipefail

# Recursion guard: the llm classifier spawns claude -p, which re-runs hooks.
[ -n "${CLAUDE_PROMPT_ROUTER_NESTED:-}" ] && exit 0

input=$(cat)
prompt=$(jq -r '.prompt // empty' <<<"$input")

ctx=""

c=$(cat ~/.claude/.comment-nudge 2>/dev/null || echo 0)
c=$((c + 1))
echo "$c" >~/.claude/.comment-nudge
if [ $((c % 5)) -eq 0 ]; then
  ctx="Comment policy: minimal — comments only for non-obvious constraints; no narration, banners, or boilerplate docstrings."
fi

if [ -n "$prompt" ]; then
  hard=0
  feature=0
  feature_re='\b(implement|new feature|new product|add (a |an )?(feature|command|endpoint|api|module|service|skill)|build (a |an |out )|create (a |an )?(feature|command|endpoint|api|module|service|skill|tool|app))'
  grep -qiE "$feature_re" <<<"$prompt" && feature=1 hard=1
  if [ "${COD_CLASSIFIER:-heuristic}" = "llm" ] && command -v claude >/dev/null; then
    cls=$(CLAUDE_PROMPT_ROUTER_NESTED=1 claude -p --model claude-haiku-4-5-20251001 \
      "Classify this request as HARD (debugging, design, multi-step analysis, unfamiliar problem) or EASY (lookup, mechanical edit, simple question). Reply with one word. Request: $prompt" 2>/dev/null || echo EASY)
    [[ "$cls" == *HARD* ]] && hard=1
  else
    hard_re='debug|why (does|is|would)|race condition|deadlock|architect|design|refactor|migrat|security|audit|prove|root cause|investigate|performance|optimi[sz]e|tricky|complex'
    if grep -qiE "$hard_re" <<<"$prompt" || [ ${#prompt} -gt 600 ]; then
      hard=1
    fi
  fi

  if [ "$hard" = 1 ]; then
    ctx="$ctx${ctx:+ }This looks like a hard task: reason fully and carefully; do not compress your analysis or skip verification steps."
  else
    ctx="$ctx${ctx:+ }Simple task: use draft-style reasoning — terse steps, minimal prose, lead with the answer."
  fi

  if [ "$feature" = 1 ]; then
    ctx="$ctx Feature task: implement the feature and write its tests yourself first. When implementation and tests are done, launch the test-scout, security-scout, and performance-scout agents in parallel (single message, all three tool calls) to review the finished work. They are read-only advisors — you alone edit files; apply their test refactors, security fixes, and performance fixes yourself when their reports arrive."
  fi
fi

if [ -n "$ctx" ]; then
  jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
fi
exit 0
