#!/usr/bin/env bats
# The UserPromptSubmit router: classification context and the scout roster.

setup() {
  ROUTER="$BATS_TEST_DIRNAME/../../claude/hooks/prompt-router.sh"
  export HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.claude"
}

route() { printf '{"prompt": %s}' "$(jq -Rn --arg p "$1" '$p')" | bash "$ROUTER"; }
ctx_of() { jq -r '.hookSpecificOutput.additionalContext' <<<"$1"; }

@test "a feature prompt names all four scouts and the hard guard" {
  run route "implement a new feature for the parser"
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(ctx_of "$output")"
  [[ "$ctx" == *"test-scout"* ]]
  [[ "$ctx" == *"security-scout"* ]]
  [[ "$ctx" == *"performance-scout"* ]]
  [[ "$ctx" == *"comment-scout"* ]]
  [[ "$ctx" == *"all four"* ]]
  [[ "$ctx" == *"hard task"* ]]
}

@test "the comment-policy nudge is gone and its counter file is never written" {
  local i out
  for i in 1 2 3 4 5 6 7 8 9 10; do
    out="$(route "question $i")"
    [[ "$out" != *"Comment policy"* ]]
  done
  [ ! -e "$HOME/.claude/.comment-nudge" ]
}

@test "classification table: prompt to context marker" {
  local prompt want ctx
  while IFS='|' read -r prompt want; do
    [ -n "$prompt" ] || continue
    ctx="$(ctx_of "$(route "$prompt")")"
    echo "prompt: $prompt | want: $want | got: $ctx"
    case "$want" in
      feature) [[ "$ctx" == *"Feature task"* ]] ;;
      hard)    [[ "$ctx" == *"hard task"* && "$ctx" != *"Feature task"* ]] ;;
      simple)  [[ "$ctx" == *"Simple task"* && "$ctx" != *"Feature task"* ]] ;;
    esac
  done <<'EOF'
implement a new feature for the parser|feature
Implement retries with backoff|feature
add a feature flag to gate rollout|feature
add an endpoint for health checks|feature
create a command to sync photos|feature
build a parser for the manifest|feature
write implementation notes for the parser|simple
reimplement the cache|simple
build the parser|simple
debug why the race condition corrupts the cache|hard
why does the deadlock happen on shutdown|hard
audit the token handling|hard
optimise the hot loop|hard
optimize the hot loop|hard
what does this flag do|simple
rename the variable|simple
EOF
}

@test "length boundary: 600 chars stays simple, 601 turns hard" {
  local p600
  p600="$(printf 'a%.0s' $(seq 1 600))"
  [[ "$(ctx_of "$(route "$p600")")" == *"Simple task"* ]]
  [[ "$(ctx_of "$(route "${p600}a")")" == *"hard task"* ]]
}

@test "prompts survive quotes, newlines, unicode, and shell metacharacters" {
  [[ "$(ctx_of "$(route $'implement a "quoted"\nnew feature — naïve 日本語')")" == *"Feature task"* ]]
  [[ "$(ctx_of "$(route 'what does $HOME `backtick` \" do')")" == *"Simple task"* ]]
}

@test "degenerate payloads emit nothing and exit zero" {
  local payload
  for payload in '{}' '{"prompt": ""}' '{"prompt": null}'; do
    run bash -c "printf '%s' '$payload' | bash '$ROUTER'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "invalid json on stdin fails without emitting garbage context" {
  run bash -c "printf 'not json' | bash '$ROUTER'"
  [ "$status" -ne 0 ]
  [[ "$output" != *hookSpecificOutput* ]]
}

@test "recursion guard short-circuits with no output" {
  run bash -c "printf '{\"prompt\": \"implement a new feature\"}' | CLAUDE_PROMPT_ROUTER_NESTED=1 bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "llm classifier: HARD verdict routes hard and the nested guard is set" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\necho "nested=$CLAUDE_PROMPT_ROUTER_NESTED" > "%s/claude-env"\necho HARD\n' \
    "$BATS_TEST_TMPDIR" > "$bin/claude"
  chmod +x "$bin/claude"
  local out
  out="$(printf '{"prompt": "what does this flag do"}' | PATH="$bin:$PATH" COD_CLASSIFIER=llm bash "$ROUTER")"
  [[ "$(ctx_of "$out")" == *"hard task"* ]]
  grep -q 'nested=1' "$BATS_TEST_TMPDIR/claude-env"
}

@test "llm classifier failure falls back to EASY" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$bin/claude"
  chmod +x "$bin/claude"
  local out
  out="$(printf '{"prompt": "what does this flag do"}' | PATH="$bin:$PATH" COD_CLASSIFIER=llm bash "$ROUTER")"
  [[ "$(ctx_of "$out")" == *"Simple task"* ]]
}
