#!/usr/bin/env bats
# The UserPromptSubmit router: classification context and the scout roster.

setup() {
  ROUTER="$BATS_TEST_DIRNAME/../../claude/hooks/prompt-router.sh"
  export HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.claude"
}

route() { printf '{"prompt": %s}' "$(jq -Rn --arg p "$1" '$p')" | bash "$ROUTER"; }

@test "a feature prompt names all four scouts" {
  run route "implement a new feature for the parser"
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [[ "$ctx" == *"test-scout"* ]]
  [[ "$ctx" == *"security-scout"* ]]
  [[ "$ctx" == *"performance-scout"* ]]
  [[ "$ctx" == *"comment-scout"* ]]
  [[ "$ctx" == *"all four"* ]]
}

@test "the comment-policy nudge is gone, every prompt, not just most" {
  local i out
  for i in 1 2 3 4 5 6 7 8 9 10; do
    out="$(route "question $i")"
    [[ "$out" != *"Comment policy"* ]]
  done
}

@test "a hard prompt still gets the full-reasoning guard" {
  run route "debug why the race condition corrupts the cache"
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"hard task"* ]]
}

@test "a simple prompt still gets draft-style brevity" {
  run route "what does this flag do"
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"Simple task"* ]]
}

@test "an empty prompt emits nothing rather than malformed json" {
  run bash -c "printf '{}' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
