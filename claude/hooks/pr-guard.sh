#!/usr/bin/env bash
# PreToolUse guard: deny PR bodies that tell instead of show — over 100
# words of prose, or no code block, CLI demo, or screenshot.
set -euo pipefail

MAX_WORDS=100

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

case "$cmd" in
*"gh pr create"* | *"gh pr edit"*) ;;
*) exit 0 ;;
esac

body=""
if grep -q '<<' <<<"$cmd"; then
  body=$(sed -n "/<<[-']*EOF/,/^EOF/p" <<<"$cmd" | sed '1d;$d')
elif [[ "$cmd" =~ (--body|-b)[=\ ]+\"([^\"]*)\" ]] || [[ "$cmd" =~ (--body|-b)[=\ ]+\'([^\']*)\' ]]; then
  body=${BASH_REMATCH[2]}
elif [[ "$cmd" =~ --body-file[=\ ]+([^\ ]+) ]] && [ -f "${BASH_REMATCH[1]}" ]; then
  body=$(cat "${BASH_REMATCH[1]}")
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
