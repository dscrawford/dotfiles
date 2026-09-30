#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
file=$(jq -r '.tool_input.file_path // .toolArgs.path // empty' <<<"$input")
[ -z "$file" ] && exit 0

base=$(basename "$file")
ext="${base##*.}"
[ "$ext" = "$base" ] && ext=""
ext="${ext,,}"

case "$ext" in
md|markdown|txt|org|rst|adoc) exit 0 ;;
esac

case "$ext" in
sh|bash|zsh|bats|py|rb|nix|yaml|yml|toml|pl|r|mk|cfg|ini|conf|tf|ex|exs|ps1) leader='#+' ;;
js|mjs|cjs|jsx|ts|tsx|go|rs|c|h|cpp|hpp|cc|cxx|java|kt|kts|swift|scala|cs|php|dart|zig|proto|groovy) leader='//+' ;;
lua|hs|sql|elm|ada|vhdl) leader='--+' ;;
el|lisp|cl|clj|cljs|cljc|edn|scm|rkt|asm|s) leader=';+' ;;
tex|sty|erl|hrl|m) leader='%+' ;;
*) leader='' ;;
esac

added=$(jq -r '
  [ (.tool_input.new_string // .toolArgs.new_str // empty),
    (.tool_input.content // .toolArgs.file_text // empty),
    ((.tool_input.edits // []) | map(.new_string) | join("\n")) ]
  | map(select(. != "")) | join("\n")' <<<"$input")
[ -z "$added" ] && exit 0

found=$(awk -v leader="$leader" '
  function whole_line(line) {
    if (line ~ /^#/)
      return line !~ /^#(!|\[|(include|define|if|ifdef|ifndef|elif|else|endif|undef|pragma|import|error|warning|line)([ \t<"(]|$))/
    if (line ~ /^\/\//) return 1
    if (line ~ /^--([ \t]|$)/) return 1
    if (line ~ /^;/) return 1
    if (line ~ /^\/\*/) return 1
    if (line ~ /^\*([ \t]|$|\/)/) return 1
    if (leader == "%+" && line ~ /^%/) return 1
    return 0
  }
  function trailing(line) {
    if (leader == "") return ""
    if (match(line, "[ \t]" leader "([ \t]|$)")) return substr(line, RSTART + 1)
    return ""
  }
  function exempt(comment,   t) {
    if (comment ~ /^(\/\/[\/!]|\/\*[*!]|;;;###autoload)/) return 1
    if (comment ~ /^;;;[ \t]+[^ \t]+\.el[ \t]+---/) return 1
    if (comment ~ /^;;;[ \t]+(Commentary|Code):/) return 1
    if (comment ~ /^;;;.*ends here[ \t]*$/) return 1
    t = comment
    sub(/^([#\/;%*-]+|\/\*)[ \t]*/, "", t)
    return t ~ /^(shellcheck|noqa|type: ?ignore|eslint|prettier|pylint|pyright|mypy|flake8|fmt:|nolint|nosec|pragma|-\*-|SPDX|@ts-|go:|\+build|Copyright|License|coding[:=])/
  }
  {
    line = $0
    sub(/^[ \t]+/, "", line)
    comment = whole_line(line) ? line : trailing(line)
    if (comment == "" || exempt(comment)) next
    n++
    if (n == 1) first = line
  }
  END { if (n) printf "%d\t%s\n", n, substr(first, 1, 60) }' <<<"$added")

[ -z "$found" ] && exit 0

count="${found%%$'\t'*}"
first="${found#*$'\t'}"

message="Comment challenge: $base +$count (\`$first\`). Delete or make the code say it; keep only for a workaround the code cannot express. Decide once."

if jq -e '.toolName' <<<"$input" >/dev/null; then
  jq -n --arg m "$message" '{additionalContext: $m}'
else
  jq -n --arg m "$message" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
fi
exit 0
