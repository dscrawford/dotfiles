#!/usr/bin/env bash
# PreToolUse guard: deny git commits whose subject isn't conventional
# format or whose message runs long; the deny reason prompts a rewrite.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/commands.sh"

input=$(</dev/stdin)
[[ $input == *commit* ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

commit_re='^git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
msg_re="(^|[[:space:]])-[a-zA-Z]*m[[:space:]]*['\"]([^'\"]*)"

check() {
  local unit=$1 first=${1%%$'\n'*} msg
  grep -qE -- '--no-edit|--amend|-F |--file|--fixup|--squash' <<<"$first" && return 0
  if [[ $first == *'<<'* ]]; then
    msg=$(heredoc_body "$unit") || return 0
  elif [[ $unit =~ $msg_re ]]; then
    msg=${BASH_REMATCH[2]}
  else
    return 0
  fi
  local subject=${msg%%$'\n'*}
  local lines
  lines=$(grep -c '' <<<"$msg")
  [ -z "$subject" ] && return 0

  if ! [[ "$subject" =~ ^(feat|fix|refactor|docs|test|chore|perf|ci|build|style)(\([a-z0-9./-]+\))?:\ .+ ]]; then
    echo "Subject must be conventional format '<type>: <description>' with type in feat|fix|refactor|docs|test|chore|perf|ci|build|style."
  elif [ ${#subject} -gt 72 ]; then
    echo "Subject is ${#subject} chars; keep it <=72."
  elif [ "$lines" -gt 10 ]; then
    echo "Message is $lines lines; keep it <=10 — subject plus a short body only when the why is non-obvious."
  fi
}

while IFS= read -r -d $'\036' unit; do
  words=$(command_words "$unit")
  [[ $words =~ $commit_re ]] || continue
  reason=$(check "$words")
  if [ -n "$reason" ]; then
    jq -n --arg r "$reason Rewrite the commit message and retry; files staged earlier stay staged, so check git status first." \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
done < <(bash_commands "$cmd")
exit 0
