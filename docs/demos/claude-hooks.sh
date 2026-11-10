#!/usr/bin/env bash
# Demo driver for claude-hooks.tape: feeds one Bash command through the
# PreToolUse hooks the way Claude Code does, and prints what each decides.
set -euo pipefail
cd "$(dirname "$0")/../.."

input=$(jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')
verdict=allow
for hook in commit-guard pr-guard session-guard tool-output-filter; do
  out=$(bash "claude/hooks/$hook.sh" <<<"$input")
  [ -z "$out" ] && continue
  reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out")
  rewrite=$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$out")
  if [ -n "$reason" ]; then
    printf '\e[31mdeny\e[0m  %s: %s\n' "$hook" "$reason" | fold -s -w "$(tput cols 2>/dev/null || echo 90)"
    verdict=deny
  elif [ -n "$rewrite" ]; then
    printf '\e[33mrewrite\e[0m  %s: %s\n' "$hook" "$rewrite"
    verdict=rewrite
  fi
done
[ "$verdict" = allow ] && printf '\e[32mallow\e[0m\n'
exit 0
