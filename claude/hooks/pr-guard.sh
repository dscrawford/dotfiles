#!/usr/bin/env bash
# PreToolUse guard: deny PR bodies that tell instead of show — over 100
# words of prose, or no code block, CLI demo, or screenshot.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/commands.sh"

MAX_WORDS=100

input=$(</dev/stdin)
[[ $input == *"gh pr"* ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

pr_re='^gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)'
pr=""
while IFS= read -r -d $'\036' unit; do
  pr=$(command_words "$unit")
  [[ $pr =~ $pr_re ]] && break
  pr=""
done < <(bash_commands "$cmd")
[ -z "$pr" ] && exit 0

body=""
if [[ ${pr%%$'\n'*} == *'<<'* ]]; then
  body=$(heredoc_body "$pr") || true
elif [[ "$pr" =~ (--body|-b)[=\ ]+\"([^\"]*)\" ]] || [[ "$pr" =~ (--body|-b)[=\ ]+\'([^\']*)\' ]]; then
  body=${BASH_REMATCH[2]}
elif [[ "$pr" =~ (--body-file|-F)[=\ ]+([^\ ]+) ]] && [ -f "${BASH_REMATCH[2]}" ]; then
  body=$(cat "${BASH_REMATCH[2]}")
fi
[ -z "$body" ] && exit 0

prose=$(awk '/^[[:space:]]*```/ { fenced = !fenced; next } !fenced' <<<"$body" |
  grep -v '🤖 Generated with' |
  sed -E 's/`[^`]*`//g; s/!\[[^]]*\]\([^)]*\)//g; s/<(img|video)[^>]*>//g; s#https?://[^ )]+##g')
words=$(wc -w <<<"$prose")

reason=""
if ! grep -qE '```|!\[|<img|<video' <<<"$body"; then
  reason="PR body shows nothing. Lead with a code block of the change and the output it enables, a CLI call and its result, or a screenshot of the UI change."
elif [ "$words" -gt "$MAX_WORDS" ]; then
  reason="PR body has $words words of prose; keep it <=$MAX_WORDS. Let the code, CLI output, or screenshots carry the explanation."
fi

if [ -n "$reason" ]; then
  jq -n --arg r "$reason Rewrite the PR body and retry." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
fi
exit 0
