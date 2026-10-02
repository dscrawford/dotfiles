#!/usr/bin/env bats

setup() {
  GUARD="$BATS_TEST_DIRNAME/../../claude/hooks/pr-guard.sh"
}

guard() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]; }
words() { yes word | head -"$1" | tr '\n' ' '; }

demo=$'```console\n$ deploy-nodes\nnode1 switched\n```'

@test "non-PR commands pass through silently" {
  run guard "gh pr list"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "short body with a code demo is allowed" {
  run guard "gh pr create --title 'feat: x' --body \"Adds deploy.
$demo\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "heredoc body with a screenshot is allowed" {
  run guard "gh pr create --title t --body \"\$(cat <<'EOF'
Waybar shows battery.
![after](https://example.com/after.png)
EOF
)\""
  [ -z "$output" ]
}

@test "body over 100 prose words is denied with the count" {
  run guard "gh pr create --body \"$(words 101)
$demo\""
  denied
  [[ "$output" == *"101"* ]]
}

@test "words inside code fences do not count" {
  run guard "gh pr create --body 'Adds it.
\`\`\`
$(words 300)
\`\`\`'"
  [ -z "$output" ]
}

@test "attribution footer does not count" {
  run guard "gh pr create --body \"$(words 95)
$demo
🤖 Generated with [Claude Code](https://claude.com/claude-code)\""
  [ -z "$output" ]
}

@test "body with no code, CLI, or image is denied" {
  run guard "gh pr create --body 'Refactors the thing.'"
  denied
  [[ "$output" == *"code block"* ]]
}

@test "gh pr edit and -b short flag are checked" {
  run guard "gh pr edit 4 -b 'Just words.'"
  denied
}

@test "body-file is read" {
  f="$BATS_TEST_TMPDIR/body.md"
  printf 'Only prose here.\n' >"$f"
  run guard "gh pr create --body-file $f"
  denied
}

@test "create without a body is left alone" {
  run guard "gh pr create --fill"
  [ -z "$output" ]
}
