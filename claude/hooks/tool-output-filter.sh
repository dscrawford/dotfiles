#!/usr/bin/env bash
# PreToolUse filter: rewrite known-verbose test runners to keep only the
# last 120 lines of output (summaries and failures print at the end), so
# thousands of passing-noise lines never enter the context window.
# Deliberately never emits a permissionDecision: rewritten commands must
# still go through the normal permission flow, or a "pytest; <anything>"
# chain would be auto-approved.
set -euo pipefail

# $(</dev/stdin) and [[ =~ ]] over cat/grep: this runs on every Bash call,
# and the two forks were half the per-invocation cost.
input=$(</dev/stdin)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

rest=$cmd
prefix=""
if [[ $cmd =~ ^cd\ ([A-Za-z0-9_./@+-]+)\ \&\&\ (.*)$ ]]; then
  prefix="cd ${BASH_REMATCH[1]} && "
  rest=${BASH_REMATCH[2]}
fi

# Any shell metacharacter, quote, or escape means the command can chain,
# substitute, or redirect — never rewrite it.
case "$rest" in
*[\|\&\;\<\>\`\$\(\)\{\}\#\!\\\'\"]* | *$'\n'* | *$'\r'*) exit 0 ;;
esac

runner='pytest|python3? -m pytest|npm (test|run test[a-z:-]*)|yarn test|pnpm test|go test|cargo test|bats|node --test'
runner_re="^($runner)( [A-Za-z0-9_./:=@,+-]+)* *$"
[[ $rest =~ $runner_re ]] || exit 0

# pipefail keeps the runner's exit code; tail always exits 0.
jq -cn --arg cmd "set -o pipefail; { $prefix$rest; } 2>&1 | tail -n 120" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { command: $cmd }
  }
}'
