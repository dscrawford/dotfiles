#!/usr/bin/env bash
# PostToolUse nudge: flag runs of 3+ consecutive comment lines in added code.
# Advisory only — instructions alone did not hold, dense neighbouring files
# out-voted them.
set -euo pipefail

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[ -z "$file" ] && exit 0

case "${file,,}" in
*.md|*.markdown|*.txt|*.org|*.rst|*.adoc) exit 0 ;;
esac

added=$(jq -r '
  [ (.tool_input.new_string // empty),
    (.tool_input.content // empty),
    ((.tool_input.edits // []) | map(.new_string) | join("\n")) ]
  | map(select(. != "")) | join("\n")' <<<"$input")
[ -z "$added" ] && exit 0

worst=$(awk '
  { line = $0; sub(/^[ \t]*/, "", line) }
  line ~ /^(#|\/\/|--|;|%)/ && line !~ /^#!/ { run++; if (run > max) { max = run } ; next }
  { run = 0 }
  END { print max + 0 }' <<<"$added")

[ "$worst" -lt 3 ] && exit 0

jq -n --arg f "$(basename "$file")" --arg n "$worst" '
  {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
    ("Comment density: \($f) has a \($n)-line comment run you just added. "
     + "Cut it to the shortest form that keeps the non-obvious part, or drop it "
     + "entirely if the reasoning belongs in the commit message or is already "
     + "implied by the code. Do not re-edit if it is already minimal.")}}'
exit 0
