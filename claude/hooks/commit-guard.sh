#!/usr/bin/env bash
# PreToolUse guard: deny git commits whose subject isn't conventional
# format or whose message runs long; the deny reason prompts a rewrite.
set -euo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

case "$cmd" in
*"git commit"*) ;;
*) exit 0 ;;
esac
grep -qE -- '--no-edit|--amend|-F |--file|--fixup|--squash' <<<"$cmd" && exit 0

subject=""
lines=0
if grep -q '<<' <<<"$cmd"; then
  body=$(sed -n "/<<[-']*EOF/,/^EOF/p" <<<"$cmd" | sed '1d;$d')
  subject=$(head -1 <<<"$body")
  lines=$(grep -c '' <<<"$body")
else
  subject=$(grep -oP -- "-m ['\"]\K[^'\"]*" <<<"$cmd" | head -1)
  lines=1
fi
[ -z "$subject" ] && exit 0

reason=""
if ! [[ "$subject" =~ ^(feat|fix|refactor|docs|test|chore|perf|ci|build|style)(\([a-z0-9./-]+\))?:\ .+ ]]; then
  reason="Subject must be conventional format '<type>: <description>' with type in feat|fix|refactor|docs|test|chore|perf|ci|build|style."
elif [ ${#subject} -gt 72 ]; then
  reason="Subject is ${#subject} chars; keep it <=72."
elif [ "$lines" -gt 10 ]; then
  reason="Message is $lines lines; keep it <=10 — subject plus a short body only when the why is non-obvious."
fi

if [ -n "$reason" ]; then
  jq -n --arg r "$reason Rewrite the commit message and retry." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
fi
exit 0
