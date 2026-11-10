#!/usr/bin/env bats

setup() {
  GUARD="$BATS_TEST_DIRNAME/../../claude/hooks/commit-guard.sh"
}

guard() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$GUARD"; }
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = deny ]; }

@test "non-conventional subjects are denied however git is invoked" {
  for cmd in "git commit -m 'bad message'" "git -C /tmp/repo commit -m 'bad'" "git -c core.x=y commit -am 'bad'" "git --no-pager commit -m 'bad'"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    denied
  done
}

@test "conventional subjects and non-commit commands pass through" {
  for cmd in "git commit -m 'fix(hooks): guard sees git -C'" "git log --oneline" "echo git commits" "git commit --amend -m 'whatever'"; do
    run guard "$cmd"
    echo "cmd: $cmd | out: $output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}
